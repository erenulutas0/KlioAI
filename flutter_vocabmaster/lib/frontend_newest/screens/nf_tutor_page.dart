import 'dart:async';
import 'dart:math' show Random;
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
import '../../models/word.dart';
import '../../models/word_origins.dart';
import '../../models/xp_sources.dart';
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
import '../services/nf_scenes.dart';
import '../services/nf_speech_capture.dart';
import '../services/nf_spoken_pace.dart';
import '../services/nf_tutor_recall.dart';
import '../services/nf_tutor_sessions.dart';
import '../services/nf_tutor_voice.dart';
import '../theme/nf_theme_scope.dart';
import '../theme/nf_tokens.dart';
import '../widgets/nf_card.dart';
import '../widgets/nf_chip.dart';
import '../widgets/nf_word_lookup.dart';

// NfScene lived in this file until the catalog gave it a file of its own;
// everything that reached it through here still does.
export '../services/nf_scenes.dart' show NfScene;

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
  const NfTutorPage({super.key, this.apiService, this.visible = true});

  /// Injectable for tests, the same way the reader page takes one. Defaults to
  /// the shared [ApiService].
  final ApiService? apiService;

  /// Whether this tab is the one on screen. The shell keeps every tab alive in
  /// an IndexedStack, so a reply can arrive after the learner has gone to
  /// another tab -- and must not start talking from one they cannot see.
  final bool visible;

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

  /// Used by the tapped-word sheet and by keeping a correction. The tutor's own
  /// replies go through [ChatbotService]; this is the words half of the screen.
  late final ApiService _api;

  /// The scene being played, by id, or null for ordinary conversation.
  ///
  /// An id rather than the scene itself: a conversation restored before the
  /// catalog has loaded names a scene this page cannot describe yet, and it
  /// must still be played as that scene -- [_send] sends the id as it is --
  /// and drawn as it the moment the catalog arrives.
  String? _sceneId;

  /// Which opening and complication this conversation was dealt, chosen when
  /// the scene starts and sent on every turn. See [NfScene.openingFor].
  int? _sceneVariant;

  /// The scenes on offer: the catalog once it has loaded, the built-in ones
  /// until then.
  List<NfScene> _scenes = NfScene.all;

  /// The language [_scenes] were loaded in, so a change of app language
  /// reloads them.
  String? _scenesLanguage;

  NfScene? get _scene => _sceneById(_sceneId);

  set _scene(NfScene? scene) => _sceneId = scene?.id;

  NfScene? _sceneById(String? id) {
    if (id == null) {
      return null;
    }
    for (final NfScene scene in _scenes) {
      if (scene.id == id) {
        return scene;
      }
    }
    for (final NfScene scene in NfScene.all) {
      if (scene.id == id) {
        return scene;
      }
    }
    return null;
  }

  /// Who is talking, by name: the scene's character, or the tutor. On a
  /// device the caption under the button said "Amy is speaking..." over Luca
  /// the waiter's lines, in Luca's voice.
  String get _speakerName => _scene?.character ?? _voice.name;

  /// Who is speaking: the scene's character in its own voice, or the tutor.
  ///
  /// The header has said "Mark" at the check-in desk since the scenes began,
  /// in Amy's voice. The catalog gives each character one of the six Piper
  /// voices; free chat is still the tutor the learner picked.
  VoiceModel get _speakingVoice {
    final String? piper = _scene?.voice;
    if (piper == null) {
      return _voice;
    }
    for (final VoiceModel voice in VoiceModel.availableVoices) {
      if (voice.piperVoice == piper) {
        return voice;
      }
    }
    return _voice;
  }

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

  /// The latest reply's audio, when it came with the reply, keyed by turn.
  ///
  /// Played once and dropped; a replay asks the server, which answers from its
  /// cache. Only the latest is kept, so a long conversation does not hold every
  /// reply it ever heard.
  final Map<int, Uint8List> _prefetchedAudio = <int, Uint8List>{};

  /// What the server spoke only the opening of. Asked for while that opening
  /// plays, so the synthesis costs none of the wait -- see [_readAloud].
  final Map<int, String> _prefetchedRest = <int, String>{};

  /// True between pointer-down and pointer-up on the speak button. The recorder
  /// starts asynchronously (permission, temp file), so a quick press can be
  /// over before it is running; this is what tells the start path to bin it.
  bool _holding = false;

  String? _hint;
  Timer? _hintTimer;

  /// A transcript the server was not sure of, held in front of the learner
  /// instead of being sent. Non-null for exactly as long as the footer is
  /// asking them to confirm it; null is the ordinary, confident path.
  ///
  /// The controller is the state: it holds what will be sent, and it is what
  /// the learner edits. There is no separate copy of the original text,
  /// because there is nothing this screen would ever do with it — a transcript
  /// the learner has corrected is simply what they said.
  TextEditingController? _confirming;

  /// Whether what is waiting in [_confirming] was held back because it was
  /// heard as another language, rather than because the words were a guess.
  ///
  /// The two need different words. "We may have misheard that" is wrong for
  /// somebody who spoke their own language clearly: they have nothing to fix,
  /// and the sentence in the field is not a mishearing of what they said but
  /// English invented from audio that was never English. Measured on a device:
  /// "Merhaba, biraz su alabilir miyiz?" came back as "Hello, can you be able
  /// to do it?" and was offered to them to correct.
  bool _confirmingOtherLanguage = false;

  /// The pace measured from the clip that produced [_confirming].
  ///
  /// Kept across an edit. It is a fact about how fast they spoke, and fixing
  /// "angry" to "agree" does not change that; recomputing or dropping it would
  /// lose a real measurement to a spelling correction.
  NfSpokenPace? _confirmingPace;

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
    _api = widget.apiService ?? ApiService();
    _capture = NfSpeechCapture(
      chatbot: _chatbot,
      onMaxDurationReached: _handleHoldEnd,
    );
    _capture.addListener(_onCaptureChanged);
    unawaited(_bootstrap());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final String language = Localizations.localeOf(context).languageCode;
    if (language != _scenesLanguage) {
      _scenesLanguage = language;
      unawaited(_loadScenes(language));
    }
  }

  /// The catalog in [language]: the copy on the device at once, then the
  /// server's. Nothing waits on either -- the rail starts with the built-in
  /// scenes and grows when the catalog arrives, and a failure keeps what it had.
  Future<void> _loadScenes(String language) async {
    final List<NfScene>? cached = await NfSceneCatalog.cached(language);
    if (!mounted || language != _scenesLanguage) {
      return;
    }
    if (cached != null) {
      setState(() => _scenes = cached);
    }
    final List<NfScene>? fresh = await NfSceneCatalog.refresh(_api, language);
    if (!mounted || language != _scenesLanguage || fresh == null) {
      return;
    }
    setState(() => _scenes = fresh);
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _confirming?.dispose();
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
    // A sentence waiting to be checked belongs to the conversation it was
    // spoken into. Carrying it across would drop it, minutes later, into a
    // thread nobody said it in.
    _clearConfirming();
    _threadId = saved.id;
    _threadStartedAt = saved.startedAt;
    _sceneId = saved.sceneId;
    _sceneVariant = saved.sceneVariant;
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
    // Same reason as in [_adopt]: changing speaker or scene ends the
    // conversation the pending sentence was spoken into.
    _clearConfirming();
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
      sceneId: _sceneId,
      sceneVariant: _sceneVariant,
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

    final NfCaptureResult result = await _capture.stopAndTranscribe(
      locale: _speechLocale,
      // In a scene, what the learner is about to say is the scene's own
      // vocabulary -- the character's name, the dish, the twist. The server
      // turns the id into a spelling hint for the recogniser.
      scenario: _sceneId,
    );
    if (!mounted) {
      return;
    }
    _updateWakelock();

    switch (result.outcome) {
      case NfCaptureOutcome.transcribed:
        // The one fork on this path, and it stays a fork rather than a step
        // everybody takes. A confident transcript goes where it has always
        // gone, at the speed it has always gone there: the common case must
        // not pay for the uncommon one.
        if (result.needsChecking) {
          _askBeforeSending(result);
        } else {
          await _send(result.transcript, pace: result.pace);
        }
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

  // ---------------------------------------------------------------------------
  // Checking a transcript the server was not sure of
  // ---------------------------------------------------------------------------

  /// Hold the transcript in the footer instead of sending it.
  ///
  /// "I am agree with you" came back as "I am angry with you" and went straight
  /// to the tutor, which then corrected a sentence the learner had never said —
  /// the one feature that justifies this screen, lying to them in their own
  /// conversation. There is no way to tell from the text that it was a guess,
  /// so the only person who can settle it is the person who spoke.
  ///
  /// This is a state of the footer, not a dialog over it. The footer is already
  /// the place that says what is happening — holding, transcribing, thinking —
  /// and a modal would cover the conversation the sentence belongs to and
  /// interrupt a screen whose whole rhythm is press, speak, release.
  void _askBeforeSending(NfCaptureResult result) {
    _confirmingPace = result.pace;
    _confirmingOtherLanguage = result.otherLanguage;
    setState(() {
      _confirming = TextEditingController(text: result.transcript);
    });
  }

  /// Send what is in the field, edited or not.
  ///
  /// Deliberately reachable in one tap. Somebody who was heard correctly and
  /// merely tripped the threshold has done nothing wrong, and making them
  /// re-read and re-approve their own sentence every time would turn a safety
  /// net into a toll.
  Future<void> _acceptTranscript() async {
    final TextEditingController? confirming = _confirming;
    if (confirming == null) {
      return;
    }
    final String text = confirming.text.trim();
    final NfSpokenPace? pace = _confirmingPace;
    setState(_clearConfirming);

    if (text.isEmpty) {
      // Emptying the field and sending is a way of saying "forget it", and the
      // tutor has nothing to answer. Same hint as a clip with no speech in it,
      // because from here it is the same event.
      _showHint(context.tr('tutor.hint.noSpeech'));
      return;
    }
    await _send(text, pace: pace);
  }

  /// Abandon the turn. Nothing is sent, nothing is charged, nothing is drawn.
  ///
  /// The way out matters as much as the way through: a learner who was heard
  /// so badly that the sentence is not worth repairing needs to be able to say
  /// so, and without this the only exits are sending nonsense to the tutor or
  /// leaving the tab.
  void _discardTranscript() {
    setState(_clearConfirming);
  }

  /// Drops the pending transcript. The caller owns the rebuild, because two of
  /// the three callers are already inside a setState of their own.
  void _clearConfirming() {
    final TextEditingController? confirming = _confirming;
    if (confirming == null) {
      return;
    }
    _confirming = null;
    _confirmingPace = null;
    _confirmingOtherLanguage = false;
    // Disposed after the frame that takes the field out of the tree, not now.
    // A TextField still mounted this frame would be holding a dead controller
    // and throws on its next paint.
    WidgetsBinding.instance.addPostFrameCallback((_) => confirming.dispose());
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
            child:
                Text(MaterialLocalizations.of(dialogContext).cancelButtonLabel),
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

  Future<void> _send(String text, {NfSpokenPace? pace}) async {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }

    setState(() {
      _turns.add(_NfTurn(
          id: _nextTurnId++, text: trimmed, fromTutor: false, pace: pace));
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
      final String? sceneId = _sceneId;
      // Taken before the await, so a second message sent while the first is
      // still in flight cannot send the same recall twice.
      final String? recall = _pendingRecall;
      _pendingRecall = null;
      final TutorReply reply = await _chatbot.chatTurn(
        trimmed,
        scenario: sceneId,
        speakerName: sceneId == null ? _voice.name : null,
        recall: recall,
        // Asked for with the text, so the reply can be spoken the moment it
        // arrives -- see ApiService.chatbotChatTurn. In the character's own
        // voice when there is a scene.
        voice: _speakingVoice.piperVoice,
        // The same variant on every turn, so the complication the server
        // plays does not change halfway through the conversation.
        scenarioVariant: sceneId == null ? null : _sceneVariant,
      );
      if (!mounted) {
        return;
      }
      _NfTurn? answer;
      setState(() {
        _isReplying = false;
        // The correction hangs off what the LEARNER said, not off the reply.
        // It is about their sentence, and putting it under the tutor's answer
        // would leave them looking for which of their own lines it meant.
        final TutorCorrection? fix = reply.correction?.about(trimmed);
        // Checked against the sentence that was actually sent, not against
        // whatever turn happens to be last. The correction is drawn struck
        // through under "Say it like this", so an invented one shows the
        // learner words they never spoke and crosses them out -- worse than
        // showing no correction at all, which is the ordinary case anyway.
        // about() applies that same test to every change and to the whole sentence.
        final bool corrected = fix != null;
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
          final _NfTurn spoken = _NfTurn(
            id: _nextTurnId++,
            text: reply.text,
            fromTutor: true,
            hasAudio: true,
          );
          answer = spoken;
          _turns.add(spoken);
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
      // Answered out loud, as a person answers -- see [nfReadsReplyAloud] for
      // the seconds this took when it waited for a tap.
      final _NfTurn? spoken = answer;
      final Uint8List? audio = reply.audio;
      if (spoken != null && audio != null) {
        _prefetchedAudio
          ..clear()
          ..[spoken.id] = audio;
        _prefetchedRest.clear();
        final String? rest = reply.audioRest;
        if (rest != null) {
          _prefetchedRest[spoken.id] = rest;
        }
      }
      if (spoken != null &&
          nfReadsReplyAloud(
            // The tutor's own voice is here either way: Piper is up, or the
            // reply came already spoken in it.
            serverVoice:
                _ttsAvailable || _prefetchedAudio.containsKey(spoken.id),
            visible: widget.visible,
            recording: _capture.isRecording,
            lifecycle: WidgetsBinding.instance.lifecycleState,
          )) {
        unawaited(_speak(spoken));
      }
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
    // `source` is the ledger label, not UI copy. It used to be the Turkish
    // literal the old chat screen wrote, which put prose in a column seven
    // languages read from; both screens now write the same stable key, so the
    // activity stays one line in the history and can be named at display time.
    final int added = await context.read<AppStateProvider>().addXPForAction(
          XPActionTypes.speakingComplete,
          source: XpSources.speakingPractice,
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

  // ---------------------------------------------------------------------------
  // Words kept out of the conversation
  // ---------------------------------------------------------------------------

  /// Look a tapped word up, in the sentence it was said in.
  ///
  /// The first real feedback this app ever had asked for this in as many words,
  /// and the book reader already had all of it: the same sheet, the same
  /// dictionary call in the same sentence context, the same quota and paywall
  /// handling, the same push into the deck so the Words screen believes it. The
  /// one thing that differs is where the word came from.
  Future<void> _onWordTapped(String rawToken, String sentence) async {
    // The sheet is about to cover the bubble that is speaking. Leaving the
    // voice running under it means reading a definition over the top of it.
    _stopAudio();
    await showNfWordLookup(
      context,
      rawToken: rawToken,
      sentence: sentence,
      api: _api,
      origin: WordOrigins.tutor,
    );
  }

  /// A phrase reduced to what makes two copies of it the same phrase.
  ///
  /// Case and punctuation removed, because what the deck holds is what the
  /// model wrote and the model does not reproduce its own full stops. A literal
  /// comparison would offer to keep "I'm bored" a second time on the strength
  /// of a comma, and the deck would fill with the same correction over and over
  /// — which costs the learner a review every day for a word they know.
  static String _deckKey(String text) => text
      .toLowerCase()
      .split(_notPartOfAPhrase)
      .where((String part) => part.isNotEmpty)
      .join(' ');

  /// Whitespace and the punctuation a sentence ends or breaks on. Deliberately
  /// not "everything that is not a-z": the learning language is not always
  /// English here, and folding away every accented letter would make two
  /// different phrases look like one.
  static final RegExp _notPartOfAPhrase =
      RegExp(r'''[\s.,!?;:'"“”‘’()\[\]-]+''');

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

    // Dealt here, once, and kept for the whole conversation: which of the
    // scene's openings the learner sees and which complication the server
    // brings in. A new conversation in the same scene is dealt again.
    final int? variant = scene == null ? null : Random().nextInt(1 << 20);

    setState(() {
      _scene = scene;
      _sceneVariant = variant;
      _beginThread();
      _turns
        ..clear()
        ..add(scene == null
            ? _greeting(_voice)
            : _NfTurn(
                id: _nextTurnId++,
                fromTutor: true,
                hasAudio: true,
                text: scene.openingFor(variant),
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
      await _readAloud(turn, spoken, seq).timeout(_speechTimeout(spoken));
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
  Future<void> _readAloud(_NfTurn turn, String spoken, int seq) async {
    // Sent with the reply, and played from here once. A replay, or a reply
    // that came without it, asks the server as before.
    Uint8List? audio = _prefetchedAudio.remove(turn.id);
    // A long reply arrives with only its first sentence spoken. Asking for the
    // rest starts here, before a note of the first has played, so the four or
    // five seconds of the opening are the four or five seconds the synthesis
    // had -- and the learner waits for a sentence instead of a paragraph.
    final String? rest = _prefetchedRest.remove(turn.id);
    Future<Uint8List?>? restAudio;
    if (audio != null && rest != null && _ttsAvailable) {
      restAudio = _piper
          .synthesize(rest, voice: _speakingVoice.piperVoice)
          .catchError((Object e) {
        debugPrint('NfTutor rest synthesize error: $e');
        return null;
      });
    }
    if (audio == null && _ttsAvailable) {
      try {
        audio =
            await _piper.synthesize(spoken, voice: _speakingVoice.piperVoice);
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
      await _playBytes(audio, 'nf_tutor_reply.wav');
      // The second half, if there is one. `seq` is what a stop bumps, so an
      // interrupted reply does not come back to life halfway through; and a
      // remainder that failed to synthesise simply ends the turn early rather
      // than repeating the opening in the device voice.
      if (restAudio != null) {
        final Uint8List? more = await restAudio;
        if (more != null && mounted && _playbackSeq == seq) {
          await _playBytes(more, 'nf_tutor_reply_rest.wav');
        }
      }
      return;
    }

    final VoiceModel speaking = _speakingVoice;
    await _deviceTts.setLanguage(speaking.locale.replaceAll('_', '-'));
    await _deviceTts.setSpeechRate(0.5);
    await _deviceTts.setPitch(speaking.gender == 'female' ? 1.1 : 0.9);
    await _deviceTts.awaitSpeakCompletion(true);
    await _deviceTts.speak(spoken);
  }

  /// Plays one clip through and returns when it has finished or been stopped.
  ///
  /// Its own file per part: `just_audio` is told a path, and handing it the
  /// same one twice in a row is how a second clip becomes a replay of the
  /// first.
  Future<void> _playBytes(Uint8List audio, String name) async {
    final Directory dir = await getTemporaryDirectory();
    final File file = File('${dir.path}/$name');
    await file.writeAsBytes(audio);
    await _player.setFilePath(file.path);
    await _player.play();
    // `idle` as well as `completed`: stopping the player is how the learner
    // interrupts, and waiting only for `completed` would leave this future
    // hanging and the bubble stuck showing a stop button.
    await _player.playerStateStream.firstWhere((PlayerState state) =>
        state.processingState == ProcessingState.completed ||
        state.processingState == ProcessingState.idle);
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
            if (_scene?.goal case final String goal) _buildGoalBanner(t, goal),
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
              // Not in a scene: the character speaks in its own voice there, so
              // a tutor picked here would change nothing but the thread, and
              // "Amy" highlighted above Luca's lines reads as Amy playing him.
              for (final VoiceModel speaker in _scene == null
                  ? _speakers
                  : const <VoiceModel>[]) ...<Widget>[
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
          scenes: _scenes,
          currentId: _threadId,
          onNew: () {
            Navigator.of(context).pop();
            setState(() {
              _beginThread();
              _scene = null;
              _sceneVariant = null;
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

  /// Every scene, grouped by kind, in a sheet.
  void _openScenePicker() {
    if (_capture.isBusy || _isReplying) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: NfTokens.transparent,
      builder: (_) => NfThemeScope(
        child: _ScenePickerSheet(
          scenes: _scenes,
          currentId: _sceneId,
          onPick: (NfScene scene) {
            Navigator.of(context).pop();
            _selectScene(scene);
          },
        ),
      ),
    );
  }

  /// The scenes on the rail itself: the first few of the catalog, and the one
  /// being played if it is not among them. The rest are one tap away in the
  /// picker -- twenty-five chips in a row is a list nobody scrolls to the end
  /// of, and a chip that moved when tapped would be one nobody could find twice.
  List<NfScene> _railScenes() {
    final List<NfScene> rail = _scenes.take(5).toList();
    final NfScene? current = _scene;
    if (current != null && !rail.any((NfScene s) => s.id == current.id)) {
      rail.insert(0, current);
    }
    return rail;
  }

  /// What the learner is in this scene to do, kept in sight while they do it.
  ///
  /// Above the conversation rather than in it: a goal scrolled away after two
  /// turns stops being a goal, and the complication the server deals is only
  /// a complication to someone who remembers what they were trying to do.
  Widget _buildGoalBanner(NfTokens t, String goal) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: t.primarySoft,
        border: Border(bottom: t.side),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: NfSpace.s16,
        vertical: NfSpace.s8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.flag_outlined, size: 18, color: t.primary),
          const SizedBox(width: NfSpace.s8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(
                    text: '${context.tr('tutor.scene.goal')}: ',
                    style: NfTokens.body(
                      size: NfFont.s125,
                      weight: NfTokens.bodyEmphasisWeight,
                      color: t.primary,
                    ),
                  ),
                  TextSpan(
                    text: goal,
                    style: NfTokens.body(size: NfFont.s125, color: t.ink),
                  ),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
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
                  const SizedBox(width: NfSpace.s6),
                  NfChip(
                    label: context.tr('tutor.scene.all'),
                    dense: true,
                    variant: NfChipVariant.unselected,
                    onTap: _openScenePicker,
                  ),
                  for (final NfScene scene in _railScenes()) ...<Widget>[
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

    // Read once per frame rather than per turn. A conversation is a few dozen
    // bubbles and a deck can be a few hundred entries, and asking the list a
    // question per word per bubble is the kind of quiet quadratic that only
    // shows up on the phone of the learner who has been using the app longest.
    final List<Word> deck = context.watch<AppStateProvider>().allWords;
    final Set<String> savedWords = deck
        .map((Word w) => w.englishWord.trim().toLowerCase())
        .where((String w) => w.isNotEmpty)
        .toSet();
    final Set<String> keptPhrases =
        deck.map((Word w) => _deckKey(w.englishWord)).toSet();

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
        final TutorCorrection? fix = turn.correction;
        return Padding(
          padding: EdgeInsets.only(top: index == 0 ? 0 : NfSpace.s14),
          child: _TurnView(
            turn: turn,
            speaking: _speakingTurnId == turn.id,
            onPlay: () => unawaited(_speak(turn)),
            savedWords: savedWords,
            onWordTapped: (String token, String sentence) =>
                unawaited(_onWordTapped(token, sentence)),
            api: _api,
            correctionKept:
                fix != null && keptPhrases.contains(_deckKey(fix.better)),
            onCorrectionSaved: (Word saved) =>
                context.read<AppStateProvider>().adoptServerWord(saved),
          ),
        );
      },
    );
  }

  Widget _buildFooter(NfTokens t) {
    final TextEditingController? confirming = _confirming;
    final bool enabled = !_bootstrapping &&
        !_isReplying &&
        !_capture.isTranscribing &&
        confirming == null;

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
          // The button and the check take the same slot rather than stacking,
          // so the conversation above never gives up height for a state it is
          // not in — and so there is exactly one thing to do at a time.
          if (confirming != null)
            _ConfirmTranscript(
              controller: confirming,
              onSend: () => unawaited(_acceptTranscript()),
              onDiscard: _discardTranscript,
            )
          else
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
    // Ahead of the meter and the hints: while a sentence is waiting to be
    // checked it is the only thing happening, and this line is the only place
    // that says why the send button is where the microphone was. It carries no
    // timer for the same reason — a three-second hint that vanishes leaves an
    // unexplained text field.
    if (_confirming != null) {
      return Text(
        context.tr(nfConfirmHintKey(_confirmingOtherLanguage)),
        style: NfTokens.body(size: NfFont.s125, color: t.streakText),
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

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
    if (_confirming != null) {
      return context.tr(nfConfirmCaptionKey(_confirmingOtherLanguage));
    }
    if (_capture.isTranscribing) {
      return context.tr('tutor.caption.transcribing');
    }
    if (_capture.isRecording) {
      return context.tr('tutor.caption.release');
    }
    if (_isReplying) {
      return context
          .tr('tutor.caption.thinking')
          .replaceAll('{name}', _speakerName);
    }
    if (_speakingTurnId != null) {
      return context
          .tr('tutor.caption.speaking')
          .replaceAll('{name}', _speakerName);
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
    this.pace,
  });

  /// How fast this turn was spoken. Learner turns only, and only when the
  /// clip was long enough to measure — see [NfSpokenPace.from].
  final NfSpokenPace? pace;

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

  /// The same turn with a correction attached.
  ///
  /// Every field is carried over by hand, and [pace] was the one that was not:
  /// the words-per-minute line disappeared from precisely the turns that got
  /// corrected, which are the turns a learner looks back at. It read as the pace
  /// feature being unreliable rather than as a copy quietly dropping a field.
  _NfTurn withCorrection(TutorCorrection value) => _NfTurn(
        id: id,
        text: text,
        fromTutor: fromTutor,
        hasAudio: hasAudio,
        note: note,
        pace: pace,
        correction: value,
      );

  /// The same turn with an XP note attached. Loses nothing else — see
  /// [withCorrection] for what "nothing else" cost when it was not true.
  _NfTurn withNote(String value) => _NfTurn(
        id: id,
        text: text,
        fromTutor: fromTutor,
        hasAudio: hasAudio,
        note: value,
        pace: pace,
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
    required this.api,
    this.savedWords = const <String>{},
    this.onWordTapped,
    this.correctionKept = false,
    this.onCorrectionSaved,
  });

  final _NfTurn turn;
  final bool speaking;
  final VoidCallback onPlay;

  final ApiService api;

  /// The learner's deck, lowercased, so their own words are marked where they
  /// turn up in the conversation.
  final Set<String> savedWords;

  /// Called with the tapped token and the line it was tapped in.
  final void Function(String token, String sentence)? onWordTapped;

  /// Whether this turn's correction is already in the deck.
  final bool correctionKept;

  final void Function(Word word)? onCorrectionSaved;

  /// Whether the words in this bubble are worth looking up.
  ///
  /// Everything the tutor actually said and everything the learner said is;
  /// an app notice is not. Those are the connection and quota messages, written
  /// by this app in the interface language, and putting a Turkish word from one
  /// of them into an English dictionary returns confident nonsense. [hasAudio]
  /// already separates the two — it is false for exactly the lines nobody
  /// spoke.
  bool get _lookUpable => !turn.fromTutor || turn.hasAudio;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final bool fromTutor = turn.fromTutor;
    final double maxWidth = MediaQuery.sizeOf(context).width * 0.78;

    final TextStyle bubbleText = NfTokens.body(
      size: NfFont.s145,
      color: fromTutor ? t.ink : t.primaryInk,
      height: 1.4,
    );
    final void Function(String token, String sentence)? tap = onWordTapped;

    final Widget bubble = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: _Bubble(
        fromTutor: fromTutor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Both sides of the conversation, not just the tutor's. A learner
            // is at least as likely to want the word they reached for and were
            // not sure of as one they were just told.
            if (tap != null && _lookUpable)
              NfTappableText(
                text: turn.text,
                style: bubbleText,
                saved: savedWords,
                // On the learner's filled bubble the reader's primary underline
                // would be invisible against the primary fill.
                savedColor: fromTutor ? t.primary : t.primaryInk,
                onWordTapped: (String token) => tap(token, turn.text),
              )
            else
              Text(turn.text, style: bubbleText),
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
        if (turn.correction case final TutorCorrection fix) ...<Widget>[
          const SizedBox(height: NfSpace.s8),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: _CorrectionNote(
              correction: fix,
              saidInFull: turn.text,
              api: api,
              alreadySaved: correctionKept,
              onSaved: onCorrectionSaved,
            ),
          ),
        ],
        if (turn.note != null) ...<Widget>[
          const SizedBox(height: NfSpace.s8),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: _FeedbackNote(text: turn.note!),
          ),
        ],
        // Last, under the correction rather than above it. The correction is
        // the thing to act on and belongs against the sentence it is about;
        // this is an observation, and it reads as one from down here.
        if (turn.pace case final NfSpokenPace pace) ...<Widget>[
          const SizedBox(height: NfSpace.s6),
          _PaceLine(pace: pace),
        ],
      ],
    );
  }
}

/// How fast that turn was spoken, stated and not judged.
///
/// No colour, no threshold, no "too slow" — a rate and a count, in the
/// smallest type on the screen. The number is worth showing because a learner
/// watching it climb over a fortnight is watching the thing they actually came
/// here to change; it is not worth a verdict, because 62 words a minute is
/// only slow next to a native speaker, and nobody opens this app already
/// being one.
class _PaceLine extends StatelessWidget {
  const _PaceLine({required this.pace});

  final NfSpokenPace pace;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    final String rate = context
        .tr('tutor.pace.rate')
        .replaceAll('{n}', '${pace.wordsPerMinute}');
    // A turn with no long pause says nothing about pauses. "0 duraklama" is
    // the same information as silence, spent on a line of text.
    final String? pauses = switch (pace.longPauses) {
      0 => null,
      1 => context.tr('tutor.pace.pause.one'),
      final int n => context.tr('tutor.pace.pauses').replaceAll('{n}', '$n'),
    };

    return Text(
      pauses == null ? rate : '$rate · $pauses',
      style: NfTokens.body(size: NfFont.s12, color: t.inkFaint),
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
class _CorrectionNote extends StatefulWidget {
  const _CorrectionNote({
    required this.correction,
    required this.saidInFull,
    required this.api,
    this.alreadySaved = false,
    this.onSaved,
  });

  final TutorCorrection correction;

  /// The whole line the learner said, of which [correction] is a span.
  ///
  /// The card shows the smallest thing that changed, which is the right thing
  /// to show and the wrong thing to keep on its own: see
  /// [_CorrectionNoteState._correctedSentence].
  final String saidInFull;

  final ApiService api;

  /// Whether this corrected phrase is in the deck already, worked out by the
  /// page against the words it is watching. A card that offered to keep the
  /// same phrase every time it was scrolled past would fill the deck with
  /// copies of one sentence and charge the learner a review for each of them.
  final bool alreadySaved;

  /// Called with the word the server made, so the Words screen learns about it
  /// without waiting for a restart.
  final void Function(Word word)? onSaved;

  @override
  State<_CorrectionNote> createState() => _CorrectionNoteState();
}

class _CorrectionNoteState extends State<_CorrectionNote> {
  bool _saving = false;
  bool _saved = false;
  String? _error;

  /// What the deck should say this phrase means.
  ///
  /// The note, when there is one: it is already the explanation, already in the
  /// learner's own language, and it is the only sentence anywhere that says why
  /// the correction was needed. When the model sent none, their own version is
  /// the next most useful thing — named as the mistake it was, so a deck entry
  /// reading "Instead of: I am boring" teaches on sight. What it must never be
  /// is the wrong sentence on its own: a review card that asks a learner to
  /// produce their own error would teach the error.
  String _meaning(BuildContext context) {
    final String? why = widget.correction.note;
    if (why != null && why.trim().isNotEmpty) {
      return why;
    }
    return context
        .tr('tutor.correction.insteadOf')
        .replaceAll('{said}', widget.correction.said);
  }

  /// The learner's own sentence with the correction applied, or null when the
  /// phrase is all there is to keep.
  ///
  /// The card shows the smallest span that changed -- "I very like" out of "I
  /// very like this app." -- so what goes into the deck is a fragment whose
  /// meaning is a grammar note. Reviewed on its own that is a card with no
  /// context at all; the context is the sentence the learner just said, fixed,
  /// and it is sitting in the bubble above the card.
  ///
  /// Null in the two cases where there is no honest sentence to add: when the
  /// span is not in the line verbatim, because the model rewrote rather than
  /// replaced and guessing where the fix belongs would put a sentence the
  /// learner never said into their deck; and when the span IS the line, where
  /// attaching it would show the same words twice and call one an example.
  String? _correctedSentence() {
    // The model's own whole sentence when it sent one: it fixes everything in the line,
    // where the span applied below can only fix the one mistake it names.
    final String? whole = widget.correction.sentence;
    if (whole != null &&
        _NfTutorPageState._deckKey(whole) !=
            _NfTutorPageState._deckKey(widget.correction.better)) {
      return whole;
    }
    final String said = widget.correction.said.trim();
    final String better = widget.correction.better.trim();
    final String line = widget.saidInFull.trim();
    if (said.isEmpty || better.isEmpty || line.isEmpty) {
      return null;
    }

    // Case-insensitively, because a correction to the first word of a sentence
    // comes back capitalised as the learner said it and lowercase as the model
    // quotes it, and the two are the same span.
    final int at = line.toLowerCase().indexOf(said.toLowerCase());
    if (at < 0) {
      return null;
    }

    final String fixed = line.replaceRange(at, at + said.length, better);
    return _NfTutorPageState._deckKey(fixed) ==
            _NfTutorPageState._deckKey(better)
        ? null
        : fixed;
  }

  Future<void> _save() async {
    if (_saving || _saved || widget.alreadySaved) {
      return;
    }
    // Read before the first await. Reaching for a localisation across an async
    // gap is how a screen ends up asking a disposed context for a string.
    final String meaning = _meaning(context);
    final String? example = _correctedSentence();

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final Word word = await widget.api.createWord(
        english: widget.correction.better,
        turkish: meaning,
        addedDate: DateTime.now(),
        origin: WordOrigins.tutor,
      );
      if (example != null) {
        // Deliberately not fatal. The phrase is in the deck by this point, and
        // failing the whole save over the example would tell a learner their
        // correction was not kept while it sits in their words list. The
        // example is what makes the card teachable, not what makes it exist.
        try {
          await widget.api.addSentenceToWord(
            wordId: word.id,
            sentence: example,
            // Under the meaning, or it lands in the word detail's unassigned
            // pile and the one meaning there says it has no sentence.
            meaningId: word.meanings.isEmpty ? null : word.meanings.first.id,
          );
        } catch (_) {
          // Nothing to tell them and nothing for them to do about it.
        }
      }
      widget.onSaved?.call(word);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saved = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        // Named, not stringified, and left where the learner can try again.
        // The alternative this replaces everywhere else in the app is
        // `e.toString()`, which puts "Exception: Kelime kaydetme başarısız:
        // 500" in front of a learner reading French.
        _error = AiErrorMessageFormatter.forError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final TutorCorrection correction = widget.correction;

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
          if (correction.showsSentence) ...<Widget>[
            // The learner's whole message, fixed. First, and set the way the corrected
            // line always was, because it is now the thing to read: a tester at B2 had
            // five mistakes in one sentence and a card that showed one, which told him
            // the other four were fine.
            Text(
              correction.sentence!,
              style: NfTokens.body(
                size: NfFont.s135,
                weight: NfTokens.bodyEmphasisWeight,
                color: t.ink,
              ),
            ),
            for (final TutorCorrection change
                in correction.changes) ...<Widget>[
              const SizedBox(height: NfSpace.s8),
              _changeLine(t, change),
            ],
          ] else ...<Widget>[
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
            // Why it was wrong, in the learner's own language, when the model
            // sent one. Quieter and smaller than the line above it, because the
            // corrected sentence is the thing to take away and this is read
            // once. Unlabelled on purpose: it arrives already written in the
            // language the learner reads, so it is a sentence rather than a
            // field, and a heading over it would be a word to translate for no
            // gain. It wraps -- half a reason is not a shorter reason -- and
            // when there is none it adds nothing, not an empty Text and the gap
            // above it, which reads as a card that failed to finish drawing.
            if (correction.note case final String why) ...<Widget>[
              const SizedBox(height: NfSpace.s6),
              Text(
                why,
                style: NfTokens.body(
                  size: NfFont.s12,
                  color: t.inkMuted,
                ),
              ),
            ],
            for (final TutorCorrection change in correction.more) ...<Widget>[
              const SizedBox(height: NfSpace.s8),
              _changeLine(t, change),
            ],
          ],
          _buildKeep(t),
        ],
      ),
    );
  }

  /// One change on a card: what was said struck through, what replaces it, and why.
  ///
  /// On one line where the words allow, because on a card that leads with the whole
  /// sentence each change is a footnote to it rather than a heading of its own.
  Widget _changeLine(NfTokens t, TutorCorrection change) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(
                text: change.said,
                style: NfTokens.body(
                  size: NfFont.s125,
                  color: t.inkMuted,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
              TextSpan(
                text: '  \u2192  ',
                style: NfTokens.body(size: NfFont.s125, color: t.inkMuted),
              ),
              TextSpan(
                text: change.better,
                style: NfTokens.body(
                  size: NfFont.s125,
                  weight: NfTokens.bodyEmphasisWeight,
                  color: t.ink,
                ),
              ),
            ],
          ),
        ),
        if (change.note case final String why) ...<Widget>[
          const SizedBox(height: NfSpace.s4),
          Text(
            why,
            style: NfTokens.body(size: NfFont.s12, color: t.inkMuted),
          ),
        ],
      ],
    );
  }

  /// One tap that keeps the corrected phrase.
  ///
  /// Without it the card teaches and then throws the lesson away: a learner is
  /// shown the right way to say something, reads it once, and makes the same
  /// mistake two days later with nothing anywhere to review. The deck is the
  /// part of this app that remembers, and until now the one screen that
  /// produced something worth remembering had no way into it.
  ///
  /// Quiet, and inside the card rather than under it. This is an option on a
  /// correction, not the point of one — the corrected sentence is still the
  /// thing to read, and a full-width button beneath it would make keeping the
  /// phrase look like the task.
  Widget _buildKeep(NfTokens t) {
    final bool done = _saved || widget.alreadySaved;
    final String label = _saved
        ? context.tr('tutor.correction.kept')
        : widget.alreadySaved
            ? context.tr('tutor.correction.already')
            : context.tr('tutor.correction.keep');

    final Widget mark = _saving
        ? SizedBox(
            width: NfSpace.s16,
            height: NfSpace.s16,
            child: CircularProgressIndicator(
              strokeWidth: NfStroke.iconLight,
              valueColor: AlwaysStoppedAnimation<Color>(t.streakText),
            ),
          )
        : Icon(
            done ? Icons.bookmark_added_rounded : Icons.bookmark_add_outlined,
            size: NfFont.s16,
            color: done ? t.correct : t.streakText,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Semantics(
          button: true,
          enabled: !done && !_saving,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: done || _saving ? null : () => unawaited(_save()),
            child: Container(
              // A row of small text is a tap target well under the 44 a thumb
              // needs, and this one sits directly above the next bubble: too
              // small and the miss lands on the conversation.
              constraints: const BoxConstraints(minHeight: NfSize.minTap),
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  mark,
                  const SizedBox(width: NfSpace.s6),
                  Flexible(
                    child: Text(
                      label,
                      style: NfTokens.body(
                        size: NfFont.s125,
                        weight: NfTokens.bodyEmphasisWeight,
                        color: done ? t.correct : t.streakText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Said out loud rather than swallowed, and the row above stays live so
        // the next tap retries. A save that failed silently is the worst of the
        // three outcomes: the learner believes the phrase is in their deck and
        // finds out days later that it never was.
        if (_error case final String message) ...<Widget>[
          Text(
            message,
            style: NfTokens.body(size: NfFont.s12, color: t.wrong),
          ),
          const SizedBox(height: NfSpace.s4),
        ],
      ],
    );
  }
}

/// The correction card on its own, for widget tests.
///
/// Everything that draws it is private to a page that needs a microphone, a
/// network and a text-to-speech engine to reach, so the alternative to this is
/// not testing the one card in the tutor tab a learner is meant to read.
@visibleForTesting
Widget nfCorrectionCardForTest(
  TutorCorrection correction, {
  ApiService? api,
  bool alreadySaved = false,
  void Function(Word word)? onSaved,
  String? saidInFull,
}) =>
    _CorrectionNote(
      correction: correction,
      // Defaults to the span itself: the learner said exactly the thing that
      // was corrected and there is no wider sentence to keep, which is the
      // case the card has always drawn.
      saidInFull: saidInFull ?? correction.said,
      api: api ?? ApiService(),
      alreadySaved: alreadySaved,
      onSaved: onSaved,
    );

/// One turn as the conversation draws it, for widget tests.
///
/// Same reason as the card above: the words in a bubble became tappable and
/// nothing could reach a bubble without a microphone and a network behind it.
@visibleForTesting
Widget nfTurnForTest({
  required String text,
  required bool fromTutor,
  bool hasAudio = false,
  void Function(String token, String sentence)? onWordTapped,
  VoidCallback? onPlay,
  Set<String> savedWords = const <String>{},
  ApiService? api,
}) =>
    _TurnView(
      turn:
          _NfTurn(id: 0, text: text, fromTutor: fromTutor, hasAudio: hasAudio),
      speaking: false,
      onPlay: onPlay ?? () {},
      api: api ?? ApiService(),
      savedWords: savedWords,
      onWordTapped: onWordTapped,
    );

/// The footer as it looks while a doubtful transcript waits to be checked.
///
/// Reaching the real one needs a microphone, a permission grant and a server
/// that decided to doubt something, none of which exist in a test. What can be
/// pinned here is the whole contract a learner meets: the sentence is readable
/// and editable, one tap accepts it, an edit survives that tap, and there is a
/// way out that sends nothing.
@visibleForTesting
Widget nfConfirmTranscriptForTest({
  required TextEditingController controller,
  required VoidCallback onSend,
  required VoidCallback onDiscard,
}) =>
    _ConfirmTranscript(
      controller: controller,
      onSend: onSend,
      onDiscard: onDiscard,
    );

/// Whether a reply that has just arrived is read aloud without a tap.
///
/// Measured on the server, five spoken turns: Whisper about 0.2 s, the tutor
/// about 0.3 s, Piper about 0.55 s -- and then 2.5 to 12 seconds before the
/// phone asked for the audio, because nothing asked until the learner pressed
/// play. The twelve-second turns were the ones with a correction card: they
/// read the card first. A person answers when you finish speaking, and that
/// gap was most of why this did not feel like talking to one.
///
/// The opening line is still not spoken on its own -- a tab that talks the
/// moment you reach it is hostile -- but a reply is different: the learner has
/// just spoken and is waiting. Only in the tutor's own voice, since the device
/// fallback is the robotic one the persona exists to replace and a tap still
/// gets it; never from a tab they have left, over their own recording, or from
/// the background. An app that has not reported a lifecycle state yet is
/// taken to be in front, which is where it is when it is being talked to.
@visibleForTesting
/// What the held-back sentence is introduced with.
///
/// Two different situations wear the same footer, and they need different
/// words. A doubted transcript is a mishearing the learner can repair -- "I am
/// agree with you" for "I am angry with you" -- and asking them to check it is
/// exactly right. A sentence held back because it was heard as another language
/// is not a mishearing of anything: measured on a device, "Merhaba, biraz su
/// alabilir miyiz?" arrived as "Hello, can you be able to do it?", English
/// invented from Turkish audio because the recogniser is pinned to the language
/// being learned. Telling that learner "we may have misheard you" invites them
/// to correct a sentence they never said a word of.
///
/// Both keep the same two ways out. The verdict comes from a detector that has
/// been seen to be wrong once on clear English, and a learner who was speaking
/// the right language all along must still be one tap from sending.
String nfConfirmHintKey(bool otherLanguage) =>
    otherLanguage ? 'tutor.confirm.hint.language' : 'tutor.confirm.hint';

/// The line under the field. See [nfConfirmHintKey].
String nfConfirmCaptionKey(bool otherLanguage) =>
    otherLanguage ? 'tutor.confirm.caption.language' : 'tutor.confirm.caption';

bool nfReadsReplyAloud({
  required bool serverVoice,
  required bool visible,
  required bool recording,
  required AppLifecycleState? lifecycle,
}) =>
    serverVoice &&
    visible &&
    !recording &&
    (lifecycle == null || lifecycle == AppLifecycleState.resumed);

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
  static const List<double> _hues = <double>[
    0.10,
    0.18,
    0.26,
    0.34,
    0.42,
    0.50
  ];

  Color _tint(NfTokens t) {
    final int index = VoiceModel.availableVoices
        .indexWhere((VoiceModel v) => v.id == voice.id);
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
/// The footer while a transcript the server doubted waits to be checked.
///
/// Three things, in the order a learner needs them: a way out, the sentence
/// itself, and one tap to send it. It takes the microphone's slot rather than
/// appearing above it, so the conversation loses no height and there is exactly
/// one thing to do.
class _ConfirmTranscript extends StatelessWidget {
  const _ConfirmTranscript({
    required this.controller,
    required this.onSend,
    required this.onDiscard,
  });

  /// The drawn circle inside the 44dp target, the same way the play control on
  /// a bubble draws 32 inside one. Not a spec token — the design has no metric
  /// for a send button — so it lives next to the only thing that uses it.
  static const double _sendDiameter = 36;

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        IconButton(
          onPressed: onDiscard,
          iconSize: NfFont.s22,
          color: t.inkMuted,
          icon: const Icon(Icons.close_rounded),
          tooltip: context.tr('tutor.confirm.discard'),
        ),
        Expanded(
          child: TextField(
            controller: controller,
            // Never focused on arrival, and this is the whole reason accepting
            // costs one tap. Opening the keyboard would cover the conversation
            // and make the learner who was heard perfectly well dismiss it
            // before they could agree — a correction step that punishes the
            // common case is one people learn to dread.
            autofocus: false,
            minLines: 1,
            // Grows to three lines and scrolls past that. A minute of speech is
            // a paragraph, and a single line would hide most of the sentence
            // the learner is being asked to check.
            maxLines: 3,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend(),
            style: NfTokens.body(size: NfFont.s145, color: t.ink),
            decoration: InputDecoration(
              hintText: context.tr('tutor.confirm.field'),
              hintStyle: NfTokens.body(size: NfFont.s145, color: t.inkFaint),
              filled: true,
              fillColor: t.raised,
              border: OutlineInputBorder(
                borderRadius: NfRadius.controlAll,
                borderSide: t.side,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: NfRadius.controlAll,
                borderSide: t.side,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: NfRadius.controlAll,
                borderSide: t.sideOf(t.primary),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: NfSpace.s14,
                vertical: NfSpace.s12,
              ),
            ),
          ),
        ),
        const SizedBox(width: NfSpace.s8),
        Semantics(
          button: true,
          label: context.tr('tutor.confirm.send'),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onSend,
              child: SizedBox(
                width: NfSize.minTap,
                height: NfSize.minTap,
                child: Center(
                  child: Container(
                    width: _sendDiameter,
                    height: _sendDiameter,
                    decoration: BoxDecoration(
                      color: t.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.arrow_upward_rounded,
                      size: NfFont.s18,
                      color: t.primaryInk,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

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

/// The last few conversations, and the way to start another.
///
/// Both live here rather than in the header because they are the same
/// decision — which conversation am I in — and because the header had room for
/// one control, not two.
/// Every scene, by kind, with what the learner would be there to do.
///
/// The rail shows a handful; this is the whole catalog. The goal is on each
/// row because it is what a learner chooses by: "order a meal and ask for the
/// bill" says more about whether a scene is for them than "At a restaurant".
class _ScenePickerSheet extends StatelessWidget {
  const _ScenePickerSheet({
    required this.scenes,
    required this.currentId,
    required this.onPick,
  });

  final List<NfScene> scenes;
  final String? currentId;
  final void Function(NfScene) onPick;

  static const List<String> _kinds = <String>[
    'daily',
    'travel',
    'social',
    'work',
    'health',
    'problems',
  ];

  static String _kindName(BuildContext context, String kind) {
    final String key = 'tutor.scene.cat.$kind';
    final String name = context.tr(key);
    return name == key ? kind : name;
  }

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    // Known kinds in their order, then any a newer catalog has that this app
    // does not know yet -- listed under their own id rather than dropped.
    final List<String> kinds = <String>[
      ..._kinds.where((String k) => scenes.any((NfScene s) => s.category == k)),
      ...<String>{for (final NfScene s in scenes) s.category}
          .where((String k) => !_kinds.contains(k)),
    ];

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(NfSpace.s20)),
        ),
        padding: const EdgeInsets.fromLTRB(
            NfSpace.s16, NfSpace.s12, NfSpace.s16, NfSpace.s8),
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
              context.tr('tutor.scene.pick'),
              style: NfTokens.display(size: NfFont.s18, color: t.ink),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  for (final String kind in kinds) ...<Widget>[
                    Padding(
                      padding: const EdgeInsets.only(
                          top: NfSpace.s14, bottom: NfSpace.s4),
                      child: Text(
                        _kindName(context, kind),
                        style: NfTokens.body(
                          size: NfFont.s125,
                          weight: NfTokens.bodyEmphasisWeight,
                          color: t.inkMuted,
                        ),
                      ),
                    ),
                    for (final NfScene scene
                        in scenes.where((NfScene s) => s.category == kind))
                      _SceneRow(
                        scene: scene,
                        selected: scene.id == currentId,
                        onTap: () => onPick(scene),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One scene in the picker: what it is, what the learner does in it, and who
/// they will be talking to.
class _SceneRow extends StatelessWidget {
  const _SceneRow({
    required this.scene,
    required this.selected,
    required this.onTap,
  });

  final NfScene scene;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final String? goal = scene.goal;
    final String? level = scene.minLevel;
    final String who = level == null
        ? scene.character
        : '${scene.character} · '
            '${context.tr('tutor.scene.level').replaceAll('{level}', level)}';

    return InkWell(
      onTap: onTap,
      borderRadius: NfRadius.controlAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: NfSpace.s8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? t.primarySoft : t.ground,
                borderRadius: NfRadius.iconTileAll,
                border: Border.fromBorderSide(
                    t.sideOf(selected ? t.primary : t.border)),
              ),
              child: Icon(scene.icon,
                  size: 20, color: selected ? t.primary : t.inkMuted),
            ),
            const SizedBox(width: NfSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    scene.nameOf(context),
                    style: NfTokens.body(
                      size: NfFont.s14,
                      weight: NfTokens.bodyEmphasisWeight,
                      color: selected ? t.primary : t.ink,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (goal != null) ...<Widget>[
                    const SizedBox(height: NfSpace.s4),
                    Text(
                      goal,
                      style:
                          NfTokens.body(size: NfFont.s125, color: t.inkMuted),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: NfSpace.s4),
                  Text(
                    who,
                    style: NfTokens.body(size: NfFont.s12, color: t.inkFaint),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistorySheet extends StatelessWidget {
  const _HistorySheet({
    required this.sessions,
    required this.scenes,
    required this.currentId,
    required this.onNew,
    required this.onOpen,
    required this.onDelete,
  });

  final List<NfTutorSession> sessions;

  /// The catalog as the page has it, so a conversation in a scene the app
  /// never shipped with is listed under its name rather than as free chat.
  final List<NfScene> scenes;
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
                    final NfScene? scene = <NfScene>[...scenes, ...NfScene.all]
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
