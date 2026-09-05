import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../models/tutor_correction.dart';
import '../../models/voice_model.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/learning_language_provider.dart';
import '../../services/ai_error_message_formatter.dart';
import '../../services/ai_paywall_handler.dart';
import '../../services/analytics_service.dart';
import '../../services/api_service.dart';
import '../../services/chatbot_service.dart';
import '../../services/piper_tts_service.dart';
import '../../services/xp_manager.dart';
import '../services/nf_speech_capture.dart';
import '../services/nf_tutor_recall.dart';
import '../services/nf_tutor_sessions.dart';
import '../services/nf_tutor_voice.dart';
import '../theme/nf_theme_scope.dart';
import '../theme/nf_tokens.dart';
import '../widgets/nf_card.dart';
import '../widgets/nf_chip.dart';

/// The tutor tab: a spoken conversation with the AI partner, promoted from a
/// screen buried behind the AI menu to a top-level destination.
///
/// Voice in, voice out. There is no text field on purpose — the learner holds
/// the button, speaks, and the transcript is sent as soon as Whisper returns
/// it. Everything behind that is the same backend the existing chat screen
/// uses: [ChatbotService.chat] for the reply, [ChatbotService.transcribeSpeech]
/// (via [NfSpeechCapture]) for the transcript, and [PiperTtsService] with the
/// device TTS as fallback for the voice.
class NfTutorPage extends StatefulWidget {
  const NfTutorPage({super.key});

  @override
  State<NfTutorPage> createState() => _NfTutorPageState();
}

class _NfTutorPageState extends State<NfTutorPage> {
  /// Height reserved above the button for the live level meter and the short
  /// capture hints. Fixed, so the footer never reflows mid-gesture.
  static const double _statusStripHeight = 26;

  /// The speakers and the stored choice both live in [NfTutorVoice] so that the
  /// Today tab's shortcut card can name the same tutor this tab is showing.
  static List<VoiceModel> get _speakers => NfTutorVoice.speakers;

  final ChatbotService _chatbot = ChatbotService();
  final PiperTtsService _piper = PiperTtsService();
  final AudioPlayer _player = AudioPlayer();
  final FlutterTts _deviceTts = FlutterTts();
  final ScrollController _scrollController = ScrollController();
  final List<_NfTurn> _turns = <_NfTurn>[];

  /// The scene being played, or null for ordinary conversation.
  NfScene? _scene;

  late final NfSpeechCapture _capture;

  VoiceModel _voice = _speakers.first;
  bool _bootstrapping = true;
  bool _ttsAvailable = false;
  bool _isReplying = false;
  bool _wakelockOn = false;

  /// Which turn is being read aloud, if any.
  int? _speakingTurnId;

  /// Bumped on every playback start and every stop, so a playback that is
  /// unwound after a newer one began cannot clear the newer one's state.
  int _playbackSeq = 0;

  int _nextTurnId = 0;

  /// True between pointer-down and pointer-up on the speak button. The recorder
  /// starts asynchronously (permission, temp file), so a quick press can be
  /// over before it is running; this is what tells the start path to bin it.
  bool _holding = false;

  String? _hint;
  Timer? _hintTimer;

  String _sessionXpId = 'nf_tutor_${DateTime.now().millisecondsSinceEpoch}';
  bool _sessionXpAwarded = false;

  /// Identity of the conversation on screen, so that writing it out on every
  /// turn replaces the same row rather than appending a longer copy of it.
  String _threadId = DateTime.now().microsecondsSinceEpoch.toString();
  DateTime _threadStartedAt = DateTime.now();

  /// The other saved conversations, newest first, for the history sheet. Read
  /// once at bootstrap and kept in step from here.
  List<NfTutorSession> _history = const <NfTutorSession>[];

  /// One sentence about the previous conversation, waiting to be spent.
  ///
  /// Computed when a thread begins and cleared as soon as it has been sent,
  /// so the model is reminded once and then gets on with the conversation.
  /// Repeating it every turn would make the tutor bring up last Tuesday in
  /// the middle of ordering a coffee, and would pay for it in tokens on
  /// every single message.
  String? _pendingRecall;

  @override
  void initState() {
    super.initState();
    _capture = NfSpeechCapture(
      chatbot: _chatbot,
      onMaxDurationReached: _handleHoldEnd,
    );
    _capture.addListener(_onCaptureChanged);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _capture.removeListener(_onCaptureChanged);
    _capture.dispose();
    unawaited(_player.dispose());
    unawaited(_deviceTts.stop());
    _scrollController.dispose();
    if (_wakelockOn) {
      unawaited(WakelockPlus.disable());
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Setup
  // ---------------------------------------------------------------------------

  Future<void> _bootstrap() async {
    await NfTutorVoice.ensureLoaded();
    final VoiceModel voice = NfTutorVoice.current.value;

    // Read before the first frame: the alternative is greeting someone and
    // then replacing the greeting with their own conversation a moment later.
    final List<NfTutorSession> history = await NfTutorSessions.load();

    if (!mounted) {
      return;
    }
    setState(() {
      _voice = voice;
      _bootstrapping = false;
      _history = history;
      if (history.isEmpty) {
        _turns.add(_greeting(voice));
      } else {
        _adopt(history.first);
      }
    });

    unawaited(_probeTts());
  }

  /// Whether the backend can synthesise speech only decides which engine reads
  /// a bubble aloud, so it is deliberately not part of [_bootstrap]: a top-level
  /// tab must not sit behind a spinner for the five seconds that probe is
  /// allowed to take. Until it answers, playback uses the device voice.
  Future<void> _probeTts() async {
    final bool available = await _piper.isAvailable();
    if (!mounted || available == _ttsAvailable) {
      return;
    }
    setState(() => _ttsAvailable = available);
  }

  /// The opening line is written here rather than fetched, so landing on the
  /// tab costs nothing from the learner's daily AI quota. It is not spoken
  /// automatically — a tab that starts talking the moment you reach it is
  /// hostile in a way a screen you deliberately opened is not, and the play
  /// control on the bubble is right there.
  _NfTurn _greeting(VoiceModel voice) {
    return _NfTurn(
      id: _nextTurnId++,
      fromTutor: true,
      hasAudio: true,
      text: NfScene.freeChatOpening.replaceAll('{name}', voice.name),
    );
  }

  /// Put a saved conversation on screen. Caller is inside setState.
  ///
  /// The speaker and the scene come back with it: a thread restored under a
  /// different face reads as one person having changed voice halfway through,
  /// and under the wrong scene it reads as a barista answering the doctor.
  void _adopt(NfTutorSession saved) {
    _threadId = saved.id;
    _threadStartedAt = saved.startedAt;
    _scene = NfScene.all
        .where((NfScene scene) => scene.id == saved.sceneId)
        .firstOrNull;
    _voice = _speakers.firstWhere(
      (VoiceModel v) => v.id == saved.voiceId,
      orElse: () => _voice,
    );
    _turns
      ..clear()
      ..addAll(saved.turns.map((NfSavedTurn t) => _NfTurn(
            id: _nextTurnId++,
            text: t.text,
            fromTutor: t.fromTutor,
            hasAudio: t.hasAudio,
            note: t.note,
            correction: t.correction,
          )));
  }

  /// Start a fresh thread, keeping whatever is on screen as its own row.
  ///
  /// Switching speaker or scene used to throw the conversation away, which was
  /// the right behaviour when there was nowhere to put it: the server keeps no
  /// history for this endpoint, so turns left on screen would sit under a
  /// character who never read them. They are saved rather than dropped now,
  /// and reachable from the history sheet.
  void _beginThread() {
    _threadId = DateTime.now().microsecondsSinceEpoch.toString();
    _threadStartedAt = DateTime.now();
    _pendingRecall = NfTutorRecall.build(
      _history,
      currentThreadId: _threadId,
      now: _threadStartedAt,
    );
    // The server keeps the model's memory of the previous thread; clearing
    // the screen without clearing that left the barista answering in free
    // chat. Not awaited -- this runs inside setState, and a failure costs one
    // stale reply rather than the thread.
    unawaited(_chatbot.resetConversation().catchError(
      (Object e) => debugPrint('NfTutor reset conversation: $e'),
    ));
  }

  /// Write the conversation on screen, and refresh the list beside it.
  ///
  /// Called after every turn. The store upserts on [NfTutorSession.id] and
  /// refuses a thread nobody has spoken in, so this is cheap and repeatable.
  Future<void> _persist() async {
    final NfTutorSession current = NfTutorSession(
      id: _threadId,
      startedAt: _threadStartedAt,
      voiceId: _voice.id,
      sceneId: _scene?.id,
      turns: _turns
          .map((_NfTurn t) => NfSavedTurn(
                text: t.text,
                fromTutor: t.fromTutor,
                hasAudio: t.hasAudio,
                note: t.note,
                correction: t.correction,
              ))
          .toList(),
    );
    await NfTutorSessions.save(current);
    final List<NfTutorSession> history = await NfTutorSessions.load();
    if (mounted) {
      setState(() => _history = history);
    }
  }

  String get _speechLocale {
    final String locale = _voice.locale.trim();
    if (locale.isNotEmpty && locale.toLowerCase().startsWith('en')) {
      return locale;
    }
    return 'en_US';
  }

  void _onCaptureChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
    _updateWakelock();
  }

  /// Hold the screen awake only while the microphone or the speaker is live.
  /// This page is a tab, so it stays mounted behind the others; a wakelock tied
  /// to its lifetime would keep the whole app awake.
  void _updateWakelock() {
    final bool keepAwake = _capture.isRecording || _speakingTurnId != null;
    if (keepAwake == _wakelockOn) {
      return;
    }
    _wakelockOn = keepAwake;
    unawaited(keepAwake ? WakelockPlus.enable() : WakelockPlus.disable());
  }

  // ---------------------------------------------------------------------------
  // Speaking (hold to talk)
  // ---------------------------------------------------------------------------

  void _handleHoldStart() {
    if (_holding) {
      return;
    }
    _holding = true;
    unawaited(_beginCapture());
  }

  void _handleHoldEnd() {
    if (!_holding) {
      return;
    }
    _holding = false;
    unawaited(_finishCapture());
  }

  Future<void> _beginCapture() async {
    if (_capture.isBusy || _isReplying) {
      return;
    }

    // The learner talking wins over the tutor talking; the speaker falls silent
    // in parallel with the recorder coming up rather than ahead of it.
    _stopAudio();

    final NfCaptureStart result = await _capture.start();

    if (!_holding && result == NfCaptureStart.started) {
      // Released before the recorder was up: nothing worth uploading happened.
      await _capture.cancel();
      return;
    }
    if (!mounted) {
      return;
    }

    switch (result) {
      case NfCaptureStart.started:
        unawaited(AnalyticsService.logFirstSpeakingStarted(source: 'nf_tutor'));
        _updateWakelock();
      case NfCaptureStart.micDenied:
        _showHint(context.tr('tutor.err.micDenied'));
      case NfCaptureStart.micBlocked:
        unawaited(_showMicBlockedDialog());
      case NfCaptureStart.failed:
        _showHint(context.tr('tutor.err.recordStart'));
      case NfCaptureStart.busy:
        break;
    }
  }

  Future<void> _finishCapture() async {
    if (!_capture.isRecording) {
      return;
    }

    final NfCaptureResult result =
        await _capture.stopAndTranscribe(locale: _speechLocale);
    if (!mounted) {
      return;
    }
    _updateWakelock();

    switch (result.outcome) {
      case NfCaptureOutcome.transcribed:
        await _send(result.transcript);
      case NfCaptureOutcome.silent:
        _showHint(context.tr('tutor.hint.noSpeech'));
      case NfCaptureOutcome.tooShort:
        _showHint(context.tr('tutor.hint.holdWhileSpeaking'));
      case NfCaptureOutcome.notRecording:
        break;
      case NfCaptureOutcome.failed:
        await _reportCaptureFailure(result.error);
    }
  }

  /// A dialog, not the three-second hint the other capture failures get.
  ///
  /// Nothing the learner does on this screen can fix a blocked permission --
  /// the system will not prompt again, so pressing the button produces
  /// silence and a flash of grey text, every time, forever. This is the one
  /// capture failure whose remedy lives outside the app, so it is the one that
  /// has to interrupt and carry the way there.
  Future<void> _showMicBlockedDialog() async {
    final bool? open = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        content: Text(dialogContext.tr('tutor.err.micBlocked')),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
                MaterialLocalizations.of(dialogContext).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(dialogContext.tr('tutor.mic.openSettings')),
          ),
        ],
      ),
    );
    if (open ?? false) {
      await openAppSettings();
    }
  }

  Future<void> _reportCaptureFailure(Object? error) async {
    if (error == null) {
      _showHint(context.tr('tutor.err.captureFailed'));
      return;
    }
    if (!mounted) {
      return;
    }
    if (await AiPaywallHandler.handleIfUpgradeRequired(context, error)) {
      return;
    }
    if (!mounted) {
      return;
    }
    // Offline and timed-out are diagnosed here for the same reason the reply
    // path diagnoses them: neither is a transcription failure, and telling
    // someone with no signal that their speech could not be transcribed sends
    // them to repeat themselves louder. Matched on the text because these
    // arrive as a SocketException and a TimeoutException from two layers down,
    // neither of which this file can name without importing dart:io.
    final String detail = error.toString();
    final String fallback;
    if (detail.contains('SocketException') ||
        detail.contains('Failed host lookup')) {
      fallback = context.tr('tutor.err.offline');
    } else if (detail.contains('TimeoutException')) {
      fallback = context.tr('tutor.err.timeout');
    } else {
      fallback = context.tr('tutor.err.transcribe');
    }

    // forError still comes first: it knows quota and upgrade errors and
    // phrases them in the learner's language. The fallback above is only
    // reached for the ones it has no opinion about.
    _showSnack(AiErrorMessageFormatter.forError(error, fallback: fallback));
  }

  // ---------------------------------------------------------------------------
  // Conversation
  // ---------------------------------------------------------------------------

  Future<void> _send(String text) async {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }

    setState(() {
      _turns.add(_NfTurn(id: _nextTurnId++, text: trimmed, fromTutor: false));
      _isReplying = true;
    });
    _scrollToBottom();
    unawaited(_persist());

    try {
      // The header, the avatar and the voice all say who this is, so the model
      // is told as well — otherwise it introduces itself as whoever the
      // backend's own rotation picked.
      // In a scene the server prompt names its own character and ignores
      // speakerName entirely, so sending Amy's name alongside "You are Emma"
      // would tell the model two different things about who it is.
      final NfScene? scene = _scene;
      // Taken before the await, so a second message sent while the first is
      // still in flight cannot send the same recall twice.
      final String? recall = _pendingRecall;
      _pendingRecall = null;
      final TutorReply reply = await _chatbot.chatTurn(
        trimmed,
        scenario: scene?.id,
        speakerName: scene == null ? _voice.name : null,
        recall: recall,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isReplying = false;
        // The correction hangs off what the LEARNER said, not off the reply.
        // It is about their sentence, and putting it under the tutor's answer
        // would leave them looking for which of their own lines it meant.
        final TutorCorrection? fix = reply.correction;
        // Checked against the sentence that was actually sent, not against
        // whatever turn happens to be last. The correction is drawn struck
        // through under "Say it like this", so an invented one shows the
        // learner words they never spoke and crosses them out -- worse than
        // showing no correction at all, which is the ordinary case anyway.
        final bool corrected = fix != null && fix.isAbout(trimmed);
        if (corrected) {
          final int said =
              _turns.lastIndexWhere((_NfTurn turn) => !turn.fromTutor);
          if (said >= 0) {
            _turns[said] = _turns[said].withCorrection(fix);
          }
        }
        // A reply can come back empty: the model sometimes answers with the
        // correction line and nothing else, and stripping it leaves nothing to
        // say. Appending it anyway drew a blank bubble with a play control that
        // read out silence -- and the correction above is still shown, so the
        // turn is not lost, only the empty half of it.
        if (!reply.isEmpty) {
          _turns.add(_NfTurn(
            id: _nextTurnId++,
            text: reply.text,
            fromTutor: true,
            hasAudio: true,
          ));
        } else if (!corrected) {
          // Empty reply AND nothing to show under their turn. Without this the
          // typing dots simply vanish and nothing arrives -- no bubble, no
          // error, no retry -- which is indistinguishable from the app having
          // ignored them. Saying so is worse than a reply and far better than
          // silence.
          // Added directly rather than through _addNotice, which opens a
          // setState of its own and this is already inside one.
          _turns.add(_NfTurn(
            id: _nextTurnId++,
            text: context.tr('tutor.err.emptyReply'),
            fromTutor: true,
          ));
        }
      });
      _scrollToBottom();
      unawaited(_persist());
      await _maybeAwardSessionXp();
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _isReplying = false);
      await _handleChatError(e);
    }
  }

  Future<void> _handleChatError(Object error) async {
    if (await AiPaywallHandler.handleIfUpgradeRequired(context, error)) {
      if (error is ApiUpgradeRequiredException) {
        _addNotice(AiErrorMessageFormatter.forUpgrade(error));
      }
      return;
    }
    if (!mounted) {
      return;
    }
    if (error is ApiQuotaExceededException) {
      _addNotice(AiErrorMessageFormatter.forQuota(error));
      return;
    }
    if (error is ApiAiServiceException) {
      debugPrint('NfTutor chat backend failure: status=${error.statusCode} '
          'feature=${error.feature} reason=${error.reason}');
      _addNotice(AiErrorMessageFormatter.forError(error));
      return;
    }

    final String detail = error.toString();
    String message = context.tr('tutor.err.connection');
    if (detail.contains('SocketException') ||
        detail.contains('Failed host lookup')) {
      message = context.tr('tutor.err.offline');
    } else if (detail.contains('TimeoutException')) {
      message = context.tr('tutor.err.timeout');
    }
    _addNotice(message);
  }

  /// A service problem, shown in the thread where the reply would have been.
  /// [hasAudio] stays false: the tutor did not say this, the app did.
  void _addNotice(String text) {
    if (!mounted) {
      return;
    }
    setState(() {
      _turns.add(_NfTurn(id: _nextTurnId++, text: text, fromTutor: true));
    });
    _scrollToBottom();
  }

  Future<void> _maybeAwardSessionXp() async {
    if (!mounted || _sessionXpAwarded) {
      return;
    }
    final int learnerTurns =
        _turns.where((_NfTurn turn) => !turn.fromTutor).length;
    if (learnerTurns < 5) {
      return;
    }

    _sessionXpAwarded = true;
    // `source` is the ledger label, not UI copy, and it is Turkish because the
    // existing chat screen writes exactly this string. Translating it here
    // would split one activity into two names in the learner's XP history.
    final int added = await context.read<AppStateProvider>().addXPForAction(
          XPActionTypes.speakingComplete,
          source: 'Konuşma Pratiği',
          transactionId: '$_sessionXpId:complete',
        );
    if (!mounted || added <= 0) {
      return;
    }

    final int index = _turns.lastIndexWhere((_NfTurn turn) => !turn.fromTutor);
    if (index < 0) {
      return;
    }
    setState(() {
      _turns[index] = _turns[index].withNote(
        context.tr('tutor.note.sessionXp').replaceAll('{n}', '$added'),
      );
    });
  }

  void _resetSessionXp() {
    _sessionXpId = 'nf_tutor_${DateTime.now().millisecondsSinceEpoch}';
    _sessionXpAwarded = false;
  }

  /// Switch scenes, which starts the conversation over.
  ///
  /// It has to. The server keeps no history for this endpoint, so turns left on
  /// screen would sit under a character who has never read them, and the
  /// learner would watch a barista answer a question they asked their doctor.
  void _selectScene(NfScene? scene) {
    if (scene?.id == _scene?.id || _capture.isBusy || _isReplying) {
      return;
    }

    _stopAudio();

    setState(() {
      _scene = scene;
      _beginThread();
      _turns
        ..clear()
        ..add(scene == null
            ? _greeting(_voice)
            : _NfTurn(
                id: _nextTurnId++,
                fromTutor: true,
                hasAudio: true,
                text: scene.opening,
              ));
      _resetSessionXp();
    });
  }

  Future<void> _selectSpeaker(VoiceModel voice) async {
    if (voice.id == _voice.id || _capture.isBusy || _isReplying) {
      return;
    }

    _stopAudio();

    setState(() {
      _voice = voice;
      _beginThread();
      // The thread starts over with the speaker. The backend keeps no history
      // for this endpoint, so leaving Amy's turns above Ryan's face would read
      // as one person changing voice mid-conversation.
      _turns
        ..clear()
        ..add(_greeting(voice));
      _resetSessionXp();
    });

    // Persisting through the shared store is what tells the Today tab's card
    // to rename itself; writing prefs directly would leave it on the old name
    // until the next cold start.
    await NfTutorVoice.select(voice);
  }

  // ---------------------------------------------------------------------------
  // Playback
  // ---------------------------------------------------------------------------

  Future<void> _speak(_NfTurn turn) async {
    if (_speakingTurnId == turn.id) {
      _stopAudio();
      return;
    }
    _stopAudio();
    if (!mounted || _capture.isRecording) {
      return;
    }

    // Read from the turn the way the screen draws it, so the voice cannot say
    // one language while the bubble shows another. Only the opening line can
    // differ, and only after the interface language has changed under it.
    final String spoken = turn.text;

    final int seq = ++_playbackSeq;
    setState(() => _speakingTurnId = turn.id);
    _updateWakelock();

    try {
      await _readAloud(turn, spoken).timeout(_speechTimeout(spoken));
    } catch (e) {
      debugPrint('NfTutor TTS error: $e');
    } finally {
      if (_playbackSeq == seq) {
        if (mounted) {
          setState(() => _speakingTurnId = null);
        } else {
          _speakingTurnId = null;
        }
        _updateWakelock();
      }
    }
  }

  /// Piper first, the device voice if the backend has nothing to offer.
  Future<void> _readAloud(_NfTurn turn, String spoken) async {
    Uint8List? audio;
    if (_ttsAvailable) {
      try {
        audio = await _piper.synthesize(spoken, voice: _voice.piperVoice);
      } catch (e) {
        debugPrint('NfTutor Piper synthesize error: $e');
      }
      // One failure used to cost the rest of the session. The probe ran once
      // at bootstrap and never again, so a cold VPS or a dropped packet at the
      // wrong second left _ttsAvailable false until a restart and every reply
      // afterwards came out in the device voice instead of the persona the
      // header is showing. Re-asking is one cheap call and only happens on the
      // turn that already failed.
      if (audio == null) {
        unawaited(_probeTts());
      }
    }

    if (audio != null && mounted) {
      final Directory dir = await getTemporaryDirectory();
      final File file = File('${dir.path}/nf_tutor_reply.wav');
      await file.writeAsBytes(audio);
      await _player.setFilePath(file.path);
      await _player.play();
      // `idle` as well as `completed`: stopping the player is how the learner
      // interrupts, and waiting only for `completed` would leave this future
      // hanging and the bubble stuck showing a stop button.
      await _player.playerStateStream.firstWhere((PlayerState state) =>
          state.processingState == ProcessingState.completed ||
          state.processingState == ProcessingState.idle);
      return;
    }

    await _deviceTts.setLanguage(_voice.locale.replaceAll('_', '-'));
    await _deviceTts.setSpeechRate(0.5);
    await _deviceTts.setPitch(_voice.gender == 'female' ? 1.1 : 0.9);
    await _deviceTts.awaitSpeakCompletion(true);
    await _deviceTts.speak(spoken);
  }

  /// A ceiling on the whole read-aloud, not on the speech itself.
  ///
  /// Every step of it can hang: `flutter_tts` completes `speak` only when the
  /// platform fires its completion callback, which some Android engines never
  /// do — and in a widget test even `setLanguage` never returns. A player that
  /// dies mid-file reaches neither `completed` nor `idle`. Without a bound the
  /// bubble sits on a stop button and the wakelock stays on for the rest of the
  /// session, so the bound wraps the whole sequence rather than the last await.
  /// Sized far above real speech — around 11 characters a second — so it cannot
  /// fire first on a genuine reply.
  static Duration _speechTimeout(String text) =>
      Duration(milliseconds: 4000 + text.length * 90);

  /// Silences playback and hands control straight back to the caller.
  ///
  /// The platform teardown is deliberately not awaited. Every caller here is
  /// reacting to a press — the microphone, a speaker switch, a second tap on
  /// play — and none of them should wait on an audio engine to answer; a
  /// push-to-talk button that starts recording late loses the first word.
  void _stopAudio() {
    _playbackSeq++;
    if (_speakingTurnId != null) {
      if (mounted) {
        setState(() => _speakingTurnId = null);
      } else {
        _speakingTurnId = null;
      }
    }
    _fireAndForget(_player.stop(), 'player stop');
    _fireAndForget(_deviceTts.stop(), 'device TTS stop');
    _updateWakelock();
  }

  void _fireAndForget(Future<Object?> future, String label) {
    unawaited(future.then<void>((Object? _) {}).catchError((Object e) {
      debugPrint('NfTutor $label error: $e');
    }));
  }

  // ---------------------------------------------------------------------------
  // Small UI helpers
  // ---------------------------------------------------------------------------

  void _showHint(String message) {
    _hintTimer?.cancel();
    setState(() => _hint = message);
    _hintTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _hint = null);
      }
    });
  }

  void _showSnack(String message) {
    final NfTokens t = NfTokens.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: NfTokens.body(size: NfFont.s135, color: t.surface),
        ),
        backgroundColor: t.ink,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(
          borderRadius: NfRadius.controlAll,
        ),
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final String level = context.watch<LearningLanguageProvider>().englishLevel;

    return Scaffold(
      backgroundColor: t.ground,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _buildHeader(t, level),
            _buildSceneBar(t),
            Expanded(child: _buildConversation(t)),
            _buildFooter(t),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(NfTokens t, String level) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        NfSpace.s16,
        NfSpace.s12,
        NfSpace.s16,
        NfSpace.s14,
      ),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(bottom: t.side),
      ),
      child: Row(
        children: <Widget>[
          // In a scene the face has to go with the name. Leaving the chosen
          // speaker's photo above "Emma" was the exact mismatch the header
          // name was changed to avoid, only louder: a portrait of one person
          // labelled as another. The scene's own mark stands in instead --
          // there is no photograph of a barista to show, and inventing one
          // would be a second wrong answer.
          if (_scene == null)
            _SpeakerAvatar(voice: _voice, size: 48)
          else
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: t.primarySoft,
                borderRadius: NfRadius.iconTileAll,
                border: Border.fromBorderSide(t.sideOf(t.primary)),
              ),
              child: Icon(_scene!.icon, size: 24, color: t.primary),
            ),
          const SizedBox(width: NfSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  _scene?.character ?? _voice.name,
                  style: NfTokens.display(size: NfFont.s18, color: t.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: NfSpace.s4),
                Row(
                  children: <Widget>[
                    Container(
                      width: NfSpace.s8,
                      height: NfSpace.s8,
                      decoration: BoxDecoration(
                        color: t.correct,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: NfSpace.s6),
                    Flexible(
                      child: Text(
                        _scene?.nameOf(context) ??
                            context
                                .tr('tutor.header.status')
                                .replaceAll('{level}', level),
                        style: NfTokens.body(
                          size: NfFont.s125,
                          weight: NfTokens.bodyEmphasisWeight,
                          color: t.correct,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: NfSpace.s10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final VoiceModel speaker in _speakers) ...<Widget>[
                if (speaker != _speakers.first)
                  const SizedBox(width: NfSpace.s6),
                NfChip(
                  label: speaker.name,
                  dense: true,
                  variant: speaker.id == _voice.id
                      ? NfChipVariant.selected
                      : NfChipVariant.unselected,
                  onTap: () => unawaited(_selectSpeaker(speaker)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _openHistory() {
    _stopAudio();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: NfTokens.transparent,
      builder: (_) => NfThemeScope(
        child: _HistorySheet(
          sessions: _history,
          currentId: _threadId,
          onNew: () {
            Navigator.of(context).pop();
            setState(() {
              _beginThread();
              _scene = null;
              _turns
                ..clear()
                ..add(_greeting(_voice));
              _resetSessionXp();
            });
          },
          onOpen: (NfTutorSession saved) {
            Navigator.of(context).pop();
            setState(() {
              _adopt(saved);
              _resetSessionXp();
            });
            _scrollToBottom();
          },
          onDelete: (NfTutorSession saved) async {
            await NfTutorSessions.delete(saved.id);
            final List<NfTutorSession> rest = await NfTutorSessions.load();
            if (mounted) {
              setState(() => _history = rest);
            }
          },
        ),
      ),
    );
  }

  /// The scenes, as a rail rather than a menu behind a button.
  ///
  /// Visible without being asked for, because a feature nobody knows about may
  /// as well not exist: these roleplay prompts have been on the server all
  /// along and went unused for exactly that reason. Free chat stays first and
  /// selected, so the tab still does what it always did for anyone who wants
  /// nothing to do with a scene.
  Widget _buildSceneBar(NfTokens t) {
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(bottom: t.side),
      ),
      padding: const EdgeInsets.symmetric(vertical: NfSpace.s8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: NfSpace.s16),
              child: Row(
                children: <Widget>[
                  NfChip(
                    label: context.tr('tutor.scene.free'),
                    dense: true,
                    variant: _scene == null
                        ? NfChipVariant.selected
                        : NfChipVariant.unselected,
                    onTap: () => _selectScene(null),
                  ),
                  for (final NfScene scene in NfScene.all) ...<Widget>[
                    const SizedBox(width: NfSpace.s6),
                    NfChip(
                      label: scene.nameOf(context),
                      dense: true,
                      variant: scene.id == _scene?.id
                          ? NfChipVariant.selected
                          : NfChipVariant.unselected,
                      onTap: () => _selectScene(scene),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Beside the scenes rather than in the header, and outside the
          // scroll so it cannot slide away. It belongs here anyway: choosing a
          // scene and choosing a conversation are the same question.
          //
          // It started in the header and took 40dp out of a line that was
          // already losing an argument about width -- the status under the
          // speaker's name read "Konusma pr..." on a phone, which is the third
          // time that line has been truncated and the second time by something
          // added beside it. Moving it is the fix that does not need a number.
          Padding(
            padding: const EdgeInsets.only(right: NfSpace.s10),
            child: IconButton(
              onPressed: _openHistory,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              icon: Icon(Icons.history_rounded, size: 20, color: t.inkMuted),
              tooltip: context.tr('tutor.history.title'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversation(NfTokens t) {
    if (_bootstrapping) {
      return Center(
        child: SizedBox(
          width: NfSpace.s26,
          height: NfSpace.s26,
          child: CircularProgressIndicator(
            strokeWidth: NfStroke.icon,
            valueColor: AlwaysStoppedAnimation<Color>(t.primary),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(NfSpace.s16),
      itemCount: _turns.length + (_isReplying ? 1 : 0),
      itemBuilder: (BuildContext context, int index) {
        if (index == _turns.length) {
          return const Padding(
            padding: EdgeInsets.only(top: NfSpace.s14),
            child: _TypingBubble(),
          );
        }

        final _NfTurn turn = _turns[index];
        return Padding(
          padding: EdgeInsets.only(top: index == 0 ? 0 : NfSpace.s14),
          child: _TurnView(
            turn: turn,
            speaking: _speakingTurnId == turn.id,
            onPlay: () => unawaited(_speak(turn)),
          ),
        );
      },
    );
  }

  Widget _buildFooter(NfTokens t) {
    final bool enabled =
        !_bootstrapping && !_isReplying && !_capture.isTranscribing;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        NfSpace.s16,
        NfSpace.s12,
        NfSpace.s16,
        NfSpace.s16,
      ),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: t.side),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            height: _statusStripHeight,
            child: Center(child: _buildStatusStrip(t)),
          ),
          _HoldToSpeakButton(
            enabled: enabled,
            recording: _capture.isRecording,
            transcribing: _capture.isTranscribing,
            onHoldStart: _handleHoldStart,
            onHoldEnd: _handleHoldEnd,
          ),
          const SizedBox(height: NfSpace.s10),
          Text(
            _captionText(context),
            style: NfTokens.body(size: NfFont.s13, color: t.inkMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusStrip(NfTokens t) {
    if (_capture.isRecording) {
      return ValueListenableBuilder<List<double>>(
        valueListenable: _capture.levels,
        builder: (BuildContext context, List<double> levels, Widget? child) {
          return SizedBox(
            width: 132,
            height: 22,
            child: CustomPaint(
              painter: _WaveformPainter(bars: levels, color: t.primary),
            ),
          );
        },
      );
    }

    final String? hint = _hint;
    if (hint != null) {
      return Text(
        hint,
        style: NfTokens.body(size: NfFont.s125, color: t.inkFaint),
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return const SizedBox.shrink();
  }

  String _captionText(BuildContext context) {
    if (_capture.isTranscribing) {
      return context.tr('tutor.caption.transcribing');
    }
    if (_capture.isRecording) {
      return context.tr('tutor.caption.release');
    }
    if (_isReplying) {
      return context
          .tr('tutor.caption.thinking')
          .replaceAll('{name}', _voice.name);
    }
    if (_speakingTurnId != null) {
      return context
          .tr('tutor.caption.speaking')
          .replaceAll('{name}', _voice.name);
    }
    return context.tr('tutor.caption.hold');
  }
}

// -----------------------------------------------------------------------------
// Model
// -----------------------------------------------------------------------------

/// One line of the conversation.
@immutable
class _NfTurn {
  const _NfTurn({
    required this.id,
    required this.text,
    required this.fromTutor,
    this.hasAudio = false,
    this.note,
    this.correction,
  });

  final int id;

  /// What the speaker said, in English — see [NfScene.freeChatOpening].
  ///
  /// This used to be resolved at paint time for the opening line, because that
  /// line was translated and the tab lives in an IndexedStack that keeps it
  /// alive and unbuilt, so a sentence resolved once at bootstrap kept whatever
  /// language the app was in then. The greeting does not change with the
  /// interface language any more, so the whole mechanism is gone with it.
  final String text;

  final bool fromTutor;

  /// Tutor turns that can be read aloud get a play control and a waveform.
  /// False for app notices, which nobody said.
  final bool hasAudio;

  /// Inline feedback shown under a learner turn.
  final String? note;

  /// What the tutor would have said instead, shown under the same turn.
  ///
  /// Kept apart from [note] rather than folded into it: that slot carries the
  /// XP notice and is styled as praise, green with a tick. A mistake shown in
  /// the shape of a reward reads as "well done" for the thing you got wrong.
  final TutorCorrection? correction;

  _NfTurn withCorrection(TutorCorrection value) => _NfTurn(
        id: id,
        text: text,
        fromTutor: fromTutor,
        hasAudio: hasAudio,
        note: note,
        correction: value,
      );

  _NfTurn withNote(String value) => _NfTurn(
        id: id,
        text: text,
        fromTutor: fromTutor,
        hasAudio: hasAudio,
        note: value,
        correction: correction,
      );
}

// -----------------------------------------------------------------------------
// Conversation widgets
// -----------------------------------------------------------------------------

class _TurnView extends StatelessWidget {
  const _TurnView({
    required this.turn,
    required this.speaking,
    required this.onPlay,
  });

  final _NfTurn turn;
  final bool speaking;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final bool fromTutor = turn.fromTutor;
    final double maxWidth = MediaQuery.sizeOf(context).width * 0.78;

    final Widget bubble = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: _Bubble(
        fromTutor: fromTutor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              turn.text,
              style: NfTokens.body(
                size: NfFont.s145,
                color: fromTutor ? t.ink : t.primaryInk,
                height: 1.4,
              ),
            ),
            if (turn.hasAudio) ...<Widget>[
              const SizedBox(height: NfSpace.s10),
              _AudioRow(
                seed: _seedFor(turn.text),
                speaking: speaking,
                onTap: onPlay,
              ),
            ],
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment:
          fromTutor ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: <Widget>[
        bubble,
        if (turn.correction != null) ...<Widget>[
          const SizedBox(height: NfSpace.s8),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: _CorrectionNote(correction: turn.correction!),
          ),
        ],
        if (turn.note != null) ...<Widget>[
          const SizedBox(height: NfSpace.s8),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: _FeedbackNote(text: turn.note!),
          ),
        ],
      ],
    );
  }
}

/// A speech bubble: 2px outline, 20 radius, and a tail on the bottom corner
/// nearest the speaker.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.fromTutor, required this.child});

  final bool fromTutor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    return CustomPaint(
      painter: _BubblePainter(
        fromTutor: fromTutor,
        // The learner's bubble keeps the 2px outline the direction is built on;
        // primaryShadow is the same colour that sits under a primary button, so
        // the fill reads as one solid, pressable object rather than a flat
        // rectangle of colour.
        fill: fromTutor ? t.surface : t.primary,
        border: fromTutor ? t.border : t.primaryShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          NfSpace.s14,
          NfSpace.s12,
          NfSpace.s14,
          NfSpace.s12 + _BubblePainter.tailHeight,
        ),
        child: child,
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  const _BubblePainter({
    required this.fromTutor,
    required this.fill,
    required this.border,
  });

  /// How far the tail hangs below the body. Not a spec token — the design has
  /// no tail metric — so it lives here, next to the only thing that uses it.
  static const double tailHeight = 9;
  static const double _tailWidth = 12;

  final bool fromTutor;
  final Color fill;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    // The stroke straddles the path, so the geometry is inset by half a stroke
    // to keep the outline inside the widget's own box.
    const double half = NfStroke.border / 2;
    final Rect body = Rect.fromLTRB(
      half,
      half,
      size.width - half,
      size.height - tailHeight - half,
    );
    if (body.width <= 0 || body.height <= 0) {
      return;
    }

    const Radius corner = Radius.circular(NfRadius.card);
    final RRect rrect = RRect.fromRectAndCorners(
      body,
      topLeft: corner,
      topRight: corner,
      // The tail grows out of a square corner, so the two shapes meet flush.
      bottomLeft: fromTutor ? Radius.zero : corner,
      bottomRight: fromTutor ? corner : Radius.zero,
    );

    final Path tail = Path();
    final double tip = size.height - half;
    if (fromTutor) {
      tail
        ..moveTo(body.left, body.bottom - tailHeight)
        ..lineTo(body.left, tip)
        ..lineTo(body.left + _tailWidth, body.bottom)
        ..close();
    } else {
      tail
        ..moveTo(body.right, body.bottom - tailHeight)
        ..lineTo(body.right, tip)
        ..lineTo(body.right - _tailWidth, body.bottom)
        ..close();
    }

    // Union rather than two draws: one path means one continuous outline, with
    // no seam where the tail meets the body.
    final Path path = Path.combine(
      PathOperation.union,
      Path()..addRRect(rrect),
      tail,
    );

    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = NfStroke.border
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _BubblePainter old) =>
      old.fromTutor != fromTutor || old.fill != fill || old.border != border;
}

/// Play control plus the static waveform under a tutor bubble's text.
class _AudioRow extends StatelessWidget {
  const _AudioRow({
    required this.seed,
    required this.speaking,
    required this.onTap,
  });

  final int seed;
  final bool speaking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    return Row(
      children: <Widget>[
        Semantics(
          button: true,
          label: speaking
              ? context.tr('tutor.a11y.stop')
              : context.tr('tutor.a11y.play'),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: SizedBox(
                width: NfSize.minTap,
                height: NfSize.minTap,
                child: Center(
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: t.primarySoft,
                      shape: BoxShape.circle,
                      border: Border.fromBorderSide(t.sideOf(t.primary)),
                    ),
                    child: Icon(
                      speaking ? Icons.stop_rounded : Icons.play_arrow_rounded,
                      size: 18,
                      color: t.primaryText,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: NfSpace.s8),
        Expanded(
          child: SizedBox(
            height: 22,
            child: CustomPaint(
              painter: _WaveformPainter(
                seed: seed,
                color: speaking ? t.primary : t.inkFaint,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Thin rounded bars. Either a fixed pattern derived from [seed] — the static
/// waveform under a tutor turn — or live microphone levels passed as [bars].
class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({required this.color, this.bars, this.seed = 0});

  static const double _pitch = 5;
  static const double _minBar = 0.14;

  final Color color;
  final List<double>? bars;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }

    final List<double> values =
        bars ?? _generate((size.width / _pitch).floor());
    if (values.isEmpty) {
      return;
    }

    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = NfStroke.iconHeavy
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final double step = size.width / values.length;
    final double mid = size.height / 2;
    final double maxHalf = (size.height - NfStroke.iconHeavy) / 2;

    for (int i = 0; i < values.length; i++) {
      final double x = step * i + step / 2;
      final double half = maxHalf * values[i].clamp(_minBar, 1.0).toDouble();
      canvas.drawLine(Offset(x, mid - half), Offset(x, mid + half), paint);
    }
  }

  /// A fixed pattern for this message. Deterministic so the bars do not
  /// reshuffle on every rebuild — this is decoration standing in for an
  /// envelope we do not have, not a measurement.
  List<double> _generate(int count) {
    if (count <= 0) {
      return const <double>[];
    }
    final List<double> values = <double>[];
    int state = seed == 0 ? 1 : seed;
    for (int i = 0; i < count; i++) {
      state = (state * 1103515245 + 12345) & 0x7FFFFFFF;
      values.add(_minBar + (state % 1000) / 1000 * (1 - _minBar));
    }
    return values;
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.color != color || old.seed != seed || old.bars != bars;
}

/// Inline feedback under a learner turn. Wraps instead of truncating: praise
/// the learner cannot finish reading is worse than a two-line chip.
/// What the learner said, and the way to say it.
///
/// The correction the tutor has always been asked for and has never been able
/// to show. It sat folded into the reply — "that sounds lovely, so you WENT to
/// Paris" — where the one person who needed to notice it is the one least
/// likely to.
///
/// In streak amber rather than the wrong-answer red. Nothing here was marked
/// wrong: the learner said something and got understood, which in a
/// conversation is the whole job. Red would turn a spoken sentence into a
/// failed question, and the fastest way to stop someone speaking is to score
/// them while they do it.
class _CorrectionNote extends StatelessWidget {
  const _CorrectionNote({required this.correction});

  final TutorCorrection correction;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    return NfCard(
      backgroundColor: t.streakSoft,
      borderColor: t.streak,
      padding: const EdgeInsets.symmetric(
        horizontal: NfSpace.s12,
        vertical: NfSpace.s10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            context.tr('tutor.correction.label'),
            style: NfTokens.body(
              size: NfFont.s12,
              weight: NfTokens.bodyEmphasisWeight,
              color: t.streakText,
            ),
          ),
          const SizedBox(height: NfSpace.s6),
          // Struck through, and muted. The corrected line is the one to read,
          // so it is the one that looks like text; what they said is context
          // for it rather than the point.
          Text(
            correction.said,
            style: NfTokens.body(
              size: NfFont.s125,
              color: t.inkMuted,
              decoration: TextDecoration.lineThrough,
            ),
          ),
          const SizedBox(height: NfSpace.s4),
          Text(
            correction.better,
            style: NfTokens.body(
              size: NfFont.s135,
              weight: NfTokens.bodyEmphasisWeight,
              color: t.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedbackNote extends StatelessWidget {
  const _FeedbackNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    return NfCard(
      backgroundColor: t.correctSoft,
      borderColor: t.correct,
      borderRadius: NfRadius.pillAll,
      padding: const EdgeInsets.symmetric(
        horizontal: NfSpace.s12,
        vertical: NfSpace.s8,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.check_rounded, size: 15, color: t.correct),
          const SizedBox(width: NfSpace.s6),
          Flexible(
            child: Text(
              text,
              style: NfTokens.body(
                size: NfFont.s125,
                weight: NfTokens.bodyEmphasisWeight,
                color: t.correct,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Three dots in a tutor bubble while the reply is on its way.
class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1050),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    return Align(
      alignment: Alignment.centerLeft,
      child: _Bubble(
        fromTutor: true,
        child: SizedBox(
          height: NfSpace.s10,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (BuildContext context, Widget? child) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  for (int i = 0; i < 3; i++) ...<Widget>[
                    if (i > 0) const SizedBox(width: NfSpace.s6),
                    Transform.translate(
                      offset: Offset(0, _lift(i)),
                      child: Container(
                        width: NfSpace.s8,
                        height: NfSpace.s8,
                        decoration: BoxDecoration(
                          color: t.inkFaint,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Each dot runs the same hop, a third of a cycle apart.
  double _lift(int index) {
    final double phase = (_controller.value - index / 3) % 1.0;
    if (phase > 0.5) {
      return 0;
    }
    return -NfSpace.s4 * (1 - (phase * 4 - 1).abs()).clamp(0.0, 1.0);
  }
}

// -----------------------------------------------------------------------------
// Header and footer widgets
// -----------------------------------------------------------------------------

class _SpeakerAvatar extends StatelessWidget {
  const _SpeakerAvatar({required this.voice, required this.size});

  final VoiceModel voice;
  final double size;

  /// A soft ground per speaker, so Amy and Ryan are not the same tile.
  ///
  /// Opacity over the theme's own accents rather than fixed hex values, so
  /// the tiles stay legible in both light and dark without a second palette.
  static const List<double> _hues = <double>[0.10, 0.18, 0.26, 0.34, 0.42, 0.50];

  Color _tint(NfTokens t) {
    final int index =
        VoiceModel.availableVoices.indexWhere((VoiceModel v) => v.id == voice.id);
    if (index < 0) {
      return t.primarySoft;
    }
    return Color.lerp(t.primarySoft, t.primary, _hues[index % _hues.length])!;
  }

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _tint(t),
        borderRadius: NfRadius.iconTileAll,
        border: Border.fromBorderSide(t.side),
      ),
      child: _initial(t),
    );
  }

  /// The speaker's initial on a colour of its own.
  ///
  /// This was the fallback behind a network photograph and is now the whole
  /// thing — see [VoiceModel.avatarUrl] for why the photographs went. The
  /// colour comes from the voice's position in the built-in list rather than
  /// from a hash of its id: six names over a small palette collide often
  /// enough that two speakers would have shared a tile, which is the one job
  /// this has.
  Widget _initial(NfTokens t) {
    final String name = voice.name;
    return Center(
      child: Text(
        name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
        style: NfTokens.display(size: NfFont.s20, color: t.primaryText),
      ),
    );
  }
}

/// The 74px circle that runs the conversation. Push-to-talk: recording starts
/// on touch and the clip is sent on release.
class _HoldToSpeakButton extends StatefulWidget {
  const _HoldToSpeakButton({
    required this.enabled,
    required this.recording,
    required this.transcribing,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  final bool enabled;
  final bool recording;
  final bool transcribing;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;

  @override
  State<_HoldToSpeakButton> createState() => _HoldToSpeakButtonState();
}

class _HoldToSpeakButtonState extends State<_HoldToSpeakButton> {
  static const double _diameter = 74;

  bool _down = false;

  void _setDown(bool value) {
    if (_down == value) {
      return;
    }
    setState(() => _down = value);
  }

  @override
  void didUpdateWidget(covariant _HoldToSpeakButton old) {
    super.didUpdateWidget(old);
    if (!widget.enabled && _down) {
      _down = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final bool live = widget.enabled || widget.transcribing;
    final bool pressed = _down || widget.recording;

    final Widget face = Container(
      width: _diameter,
      height: _diameter,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: live ? t.primary : t.raised,
        shape: BoxShape.circle,
        border: live ? null : Border.fromBorderSide(t.side),
      ),
      child: _icon(t, live),
    );

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: context.tr('tutor.caption.hold'),
      excludeSemantics: true,
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        // Listener, not GestureDetector: the tap recogniser waits out its
        // deadline before reporting a press, and push-to-talk has to start on
        // contact or the first word is lost.
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) {
            if (!widget.enabled) {
              return;
            }
            _setDown(true);
            widget.onHoldStart();
          },
          onPointerUp: (_) {
            if (!_down) {
              return;
            }
            _setDown(false);
            widget.onHoldEnd();
          },
          onPointerCancel: (_) {
            if (!_down) {
              return;
            }
            _setDown(false);
            widget.onHoldEnd();
          },
          child: SizedBox(
            width: _diameter,
            height: _diameter + NfSize.pressDepth,
            child: Stack(
              children: <Widget>[
                Positioned(
                  left: 0,
                  top: NfSize.pressDepth,
                  child: Container(
                    width: _diameter,
                    height: _diameter,
                    decoration: BoxDecoration(
                      color: live ? t.primaryShadow : t.border,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 70),
                  curve: Curves.easeOut,
                  left: 0,
                  top: pressed ? NfSize.pressDepth : 0,
                  child: face,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _icon(NfTokens t, bool live) {
    final Color foreground = live ? t.primaryInk : t.inkFaint;

    if (widget.transcribing) {
      return SizedBox(
        width: NfSpace.s22,
        height: NfSpace.s22,
        child: CircularProgressIndicator(
          strokeWidth: NfStroke.iconHeavy,
          valueColor: AlwaysStoppedAnimation<Color>(foreground),
        ),
      );
    }

    return Icon(
      widget.recording ? Icons.mic_rounded : Icons.mic_none_rounded,
      size: 30,
      color: foreground,
    );
  }
}

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

/// FNV-1a over the message text. Written out rather than using [String.hashCode]
/// because that is only stable within a single run, and a waveform that changes
/// shape when the app restarts looks like a bug.
int _seedFor(String text) {
  int hash = 0x811C9DC5;
  for (final int unit in text.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0x7FFFFFFF;
  }
  return hash;
}

/// A situation the tutor plays instead of being itself.
///
/// The backend has had roleplay prompts since long before this tab existed,
/// reached through a `scenario` argument that only the retired chat screen ever
/// filled in. Everything worked except the part a learner could touch: the
/// server knew how to be a barista and the app never asked it to.
///
/// [opening] is written here rather than fetched, for the same reason the plain
/// greeting is: choosing a scene should not spend a request from someone's
/// daily quota before they have said a word. [character] is who the model
/// becomes, and has to match the name in that scene's server prompt -- the
/// header shows it, and a learner reading "Amy" while the voice says "I am
/// Emma" is being told the app does not know who is talking.
class NfScene {
  const NfScene({
    required this.id,
    required this.character,
    required this.opening,
    required this.icon,
  });

  /// Matches the scenario id the backend switches on. Not a display string.
  final String id;
  final String character;
  final String opening;
  final IconData icon;

  /// What the tutor opens with when no scene is chosen.
  ///
  /// English, like every [opening] below it, and for a reason that took a
  /// phone to see. This line used to be translated, so a Turkish learner was
  /// greeted with "Selam, ben Ryan" — and then Piper read that Turkish
  /// sentence with an English voice, which sounds exactly like a foreigner
  /// struggling through Turkish. The tutor is the one thing in this app that
  /// must never do that: it is here to be a native speaker.
  ///
  /// The interface around it stays translated. The caption under the button
  /// still reads "Konuşmak için basılı tut", so the instruction is available
  /// in the learner's own language without the tutor breaking character.
  static const String freeChatOpening =
      "Hi, I'm {name}. Hold the button below and tell me about your day — "
      "I'll answer out loud.";

  /// The scene's name in the learner's own language.
  String nameOf(BuildContext context) => context.tr('tutor.scene.$id');

  /// Everyday scenes first. The four that already existed are all office and
  /// lecture hall, and the person who needs those is not the person who most
  /// needs this feature.
  static const List<NfScene> all = <NfScene>[
    NfScene(
      id: 'cafe_order',
      character: 'Emma',
      opening: 'Hi there! What can I get started for you?',
      icon: Icons.local_cafe_outlined,
    ),
    NfScene(
      id: 'airport_checkin',
      character: 'Mark',
      opening:
          'Good morning. Passport, please — and where are you flying to today?',
      icon: Icons.flight_takeoff_outlined,
    ),
    NfScene(
      id: 'hotel_checkin',
      character: 'Nina',
      opening: 'Welcome! Could I have your booking name and some ID?',
      icon: Icons.hotel_outlined,
    ),
    NfScene(
      id: 'small_talk',
      character: 'Alex',
      opening:
          'I do not think we have met — I am Alex. How do you know the host?',
      icon: Icons.waving_hand_outlined,
    ),
    NfScene(
      id: 'doctor_visit',
      character: 'Dr. Patel',
      opening: 'Come in, have a seat. So, what has been bothering you?',
      icon: Icons.medical_services_outlined,
    ),
    NfScene(
      id: 'shopping_return',
      character: 'Sam',
      opening: 'Hello! What seems to be the problem with it?',
      icon: Icons.shopping_bag_outlined,
    ),
    NfScene(
      id: 'job_interview_followup',
      character: 'Sarah',
      opening: 'Thanks for calling back. How are you feeling about the role?',
      icon: Icons.business_center_outlined,
    ),
    NfScene(
      id: 'academic_presentation_qa',
      character: 'Dr. Johnson',
      opening:
          'Thank you for the presentation. I have a few questions about your method.',
      icon: Icons.school_outlined,
    ),
  ];
}

/// The last few conversations, and the way to start another.
///
/// Both live here rather than in the header because they are the same
/// decision — which conversation am I in — and because the header had room for
/// one control, not two.
class _HistorySheet extends StatelessWidget {
  const _HistorySheet({
    required this.sessions,
    required this.currentId,
    required this.onNew,
    required this.onOpen,
    required this.onDelete,
  });

  final List<NfTutorSession> sessions;
  final String currentId;
  final VoidCallback onNew;
  final void Function(NfTutorSession) onOpen;
  final Future<void> Function(NfTutorSession) onDelete;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final MaterialLocalizations dates = MaterialLocalizations.of(context);

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(NfSpace.s20)),
        ),
        padding: const EdgeInsets.fromLTRB(
            NfSpace.s16, NfSpace.s12, NfSpace.s16, NfSpace.s16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: t.border,
                  borderRadius: BorderRadius.circular(NfSpace.s4),
                ),
              ),
            ),
            const SizedBox(height: NfSpace.s12),
            Text(
              context.tr('tutor.history.title'),
              style: NfTokens.display(size: NfFont.s18, color: t.ink),
            ),
            const SizedBox(height: NfSpace.s10),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.add_comment_outlined, color: t.primary),
              title: Text(
                context.tr('tutor.history.new'),
                style: NfTokens.body(
                    size: NfFont.s145,
                    weight: NfTokens.bodyEmphasisWeight,
                    color: t.primary),
              ),
              onTap: onNew,
            ),
            if (sessions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: NfSpace.s16),
                child: Text(
                  context.tr('tutor.history.empty'),
                  style: NfTokens.body(size: NfFont.s135, color: t.inkMuted),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: sessions.length,
                  itemBuilder: (BuildContext context, int i) {
                    final NfTutorSession s = sessions[i];
                    final NfScene? scene = NfScene.all
                        .where((NfScene sc) => sc.id == s.sceneId)
                        .firstOrNull;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      selected: s.id == currentId,
                      leading: Icon(
                        scene?.icon ?? Icons.forum_outlined,
                        color: s.id == currentId ? t.primary : t.inkMuted,
                      ),
                      title: Text(
                        scene?.nameOf(context) ??
                            context.tr('tutor.scene.free'),
                        style: NfTokens.body(
                            size: NfFont.s14,
                            weight: NfTokens.bodyEmphasisWeight,
                            color: t.ink),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        // What they said, not the greeting: every thread opens
                        // with the same sentence and it names none of them.
                        s.preview,
                        style:
                            NfTokens.body(size: NfFont.s125, color: t.inkMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            // Formatted by MaterialLocalizations rather than
                            // by strings of our own, so it reads correctly in
                            // all seven languages for nothing.
                            dates.formatShortDate(s.startedAt),
                            style: NfTokens.body(
                                size: NfFont.s12, color: t.inkFaint),
                          ),
                          IconButton(
                            icon: Icon(Icons.close_rounded,
                                size: NfFont.s18, color: t.inkFaint),
                            tooltip: MaterialLocalizations.of(context)
                                .deleteButtonTooltip,
                            onPressed: () => unawaited(onDelete(s)),
                          ),
                        ],
                      ),
                      onTap: () => onOpen(s),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
