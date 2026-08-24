import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../providers/app_state_provider.dart';
import '../../services/ai_error_message_formatter.dart';
import '../../services/ai_paywall_handler.dart';
import '../../services/analytics_service.dart';
import '../../services/chatbot_service.dart';
import '../../services/piper_tts_service.dart';
import '../../services/pronunciation_report_service.dart';
import '../../services/xp_manager.dart';
import '../theme/nf_tokens.dart';
import '../widgets/nf_button.dart';
import '../widgets/nf_card.dart';
import '../widgets/nf_chip.dart';
import '../widgets/nf_progress.dart';

/// Pronunciation ("reading clarity") practice, rebuilt in the new design
/// language.
///
/// Behaviour is replicated from `lib/screens/pronunciation_practice_page.dart`,
/// which stays in the tree as the spec:
/// - target text priority: provided texts > placement text > focus-words text >
///   level samples, with AI texts loaded async when there are focus words;
/// - `ChatbotService.generatePronunciationTexts` honours the backend's
///   `fallback` flag by returning an empty list, and this screen keeps the
///   focus-words sentence in that case exactly like the legacy screen;
/// - recording uses the same `record` package configuration and 45s cap as the
///   legacy screen (the tutor's `NfSpeechCapture` is hold-to-speak with a
///   silence gate and no measured-duration passthrough, so it does not fit
///   read-aloud scoring — see the note on `_stopAndEvaluate`);
/// - scoring via `PronunciationReportService.evaluate` with Whisper's measured
///   duration when available, XP via `speakingComplete` / `speakingExcellent`,
///   analytics, paywall and quota handling all unchanged.
class NfPronunciationPage extends StatefulWidget {
  const NfPronunciationPage({
    super.key,
    this.level = 'B1',
    this.placementMode = false,
    this.focusWords = const <String>[],
    this.initialText,
    this.initialTextOptions = const <String>[],
    this.initialReport,
    this.wordPronunciationPlayer,
  });

  final String level;
  final bool placementMode;
  final List<String> focusWords;
  final String? initialText;
  final List<String> initialTextOptions;
  final PronunciationReport? initialReport;
  final Future<void> Function(String word)? wordPronunciationPlayer;

  @override
  State<NfPronunciationPage> createState() => _NfPronunciationPageState();
}

class _NfPronunciationPageState extends State<NfPronunciationPage> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final PiperTtsService _ttsService = PiperTtsService();
  final ChatbotService _chatbotService = ChatbotService();
  final PronunciationReportService _reportService =
      PronunciationReportService();

  late String _targetText;
  int _focusTextVariant = 0;
  int _providedTextVariant = 0;
  int _aiTextVariant = 0;

  /// Seed sent to the backend: it grows with every fresh AI-text request so the
  /// server produces a different theme variant even within the same day.
  /// (Behaviour carried over from the legacy screen.)
  int _aiRequestVariant = 0;
  bool _isPlayingModel = false;
  bool _isRecording = false;
  bool _isTranscribing = false;
  bool _isGeneratingText = false;
  String? _recordingPath;
  DateTime? _recordingStartedAt;
  Timer? _recordingTimer;
  PronunciationReport? _report;
  int _pronunciationAttemptSequence = 0;
  List<String> _aiTextOptions = const <String>[];

  bool get _isTurkish => Localizations.localeOf(context).languageCode == 'tr';

  /// Same TR/EN copy the legacy screen ships (the spec says legacy copy is the
  /// spec). No pronunciation keys exist in `app_localizations.dart` yet, so DE
  /// falls back to English exactly as it did on the legacy screen.
  // TODO(i18n): move this copy into app_localizations keys (EN/TR/DE).
  String _text(String tr, String en) => _isTurkish ? tr : en;

  @override
  void initState() {
    super.initState();
    final List<String> providedTexts = _providedTextOptions();
    _targetText = providedTexts.isNotEmpty
        ? providedTexts.first
        : widget.placementMode
            ? _placementText()
            : widget.focusWords.isNotEmpty
                ? _focusWordsText(widget.focusWords, _focusTextVariant)
                : _sampleTexts(widget.level).first;
    _report = widget.initialReport;
    _audioPlayer.playerStateStream.listen((PlayerState state) {
      if (!mounted) return;
      setState(() => _isPlayingModel = state.playing);
    });
    if (!widget.placementMode &&
        providedTexts.isEmpty &&
        widget.focusWords.isNotEmpty) {
      unawaited(_loadAiTextOptions());
    }
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _audioPlayer.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Target text selection — logic identical to the legacy screen.
  // ---------------------------------------------------------------------------

  List<String> _sampleTexts(String level) {
    final String normalized = level.toUpperCase();
    if (normalized == 'A1' || normalized == 'A2') {
      return const <String>[
        'I usually drink coffee before I start studying English.',
        'My friend and I walked to the station after lunch.',
        'Could you tell me where the nearest bus stop is?',
      ];
    }
    if (normalized == 'B2' || normalized == 'C1' || normalized == 'C2') {
      return const <String>[
        'Although the meeting was delayed, everyone stayed calm and focused.',
        'The article explains how small daily habits can improve long-term learning.',
        'If the weather improves tomorrow, we might record the interview outside.',
      ];
    }
    return const <String>[
      'I need to explain the problem clearly before we choose a solution.',
      'The speaker gave a short example to support her main idea.',
      'Learning a language becomes easier when practice feels useful.',
    ];
  }

  String _placementText() {
    return 'A useful habit is easier to keep when it fits naturally into your day.';
  }

  List<String> _providedTextOptions() {
    final Set<String> seen = <String>{};
    final List<String> result = <String>[];

    void addText(String? rawText) {
      final String text =
          (rawText ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
      if (text.isEmpty) return;
      final String key = text.toLowerCase();
      if (seen.add(key)) {
        result.add(text);
      }
    }

    addText(widget.initialText);
    for (final String option in widget.initialTextOptions) {
      addText(option);
    }
    return result;
  }

  String _focusWordsText(List<String> rawWords, int variant) {
    final List<String> words = _cleanFocusWords(rawWords);
    if (words.isEmpty) {
      return _sampleTexts(widget.level).first;
    }
    final String joined = _joinEnglishList(words);
    final String leadWord = words.first;
    final List<String> variants = <String>[
      'During today\'s practice, I used $joined in one clear explanation.',
      'The speaker repeated $joined slowly, then used $leadWord in a natural sentence.',
      'To improve my English, I practiced $joined until each word sounded clear.',
    ];
    return variants[variant % variants.length];
  }

  List<String> _cleanFocusWords(List<String> rawWords) {
    final Set<String> seen = <String>{};
    final List<String> result = <String>[];
    for (final String rawWord in rawWords) {
      final String word = rawWord.trim();
      if (word.isEmpty) continue;
      final String key = word.toLowerCase();
      if (seen.add(key)) {
        result.add(word);
      }
      if (result.length >= 4) break;
    }
    return result;
  }

  String _joinEnglishList(List<String> words) {
    if (words.length == 1) return words.first;
    if (words.length == 2) return '${words.first} and ${words.last}';
    return '${words.sublist(0, words.length - 1).join(', ')}, and ${words.last}';
  }

  Future<void> _loadAiTextOptions({bool fresh = false}) async {
    if (_isGeneratingText) return;
    if (fresh) _aiRequestVariant++;
    setState(() => _isGeneratingText = true);
    // `generatePronunciationTexts` already returns const [] when the backend
    // flags its payload as the canned fallback — keeping the focus-words
    // sentence the screen built is exactly the legacy behaviour.
    final List<String> texts = await _chatbotService.generatePronunciationTexts(
      level: widget.level,
      focusWords: _cleanFocusWords(widget.focusWords),
      variant: _aiRequestVariant,
    );
    if (!mounted) return;
    setState(() {
      _isGeneratingText = false;
      if (texts.isNotEmpty) {
        _aiTextOptions = texts;
        _aiTextVariant = 0;
        if (!_isRecording && !_isTranscribing && _report == null) {
          _targetText = texts.first;
        }
      } else if (fresh && _aiTextOptions.isNotEmpty) {
        // Fresh request failed — keep the set in hand and wrap to the start.
        _aiTextVariant = 0;
        _targetText = _aiTextOptions.first;
      } else {
        _aiTextOptions = texts;
        _aiTextVariant = 0;
      }
    });
  }

  void _pickAnotherText() {
    if (widget.placementMode) {
      setState(() => _report = null);
      return;
    }
    final List<String> providedTexts = _providedTextOptions();
    if (providedTexts.length > 1) {
      setState(() {
        _providedTextVariant++;
        _targetText =
            providedTexts[_providedTextVariant % providedTexts.length];
        _report = null;
      });
      return;
    }
    if (_aiTextOptions.length > 1) {
      final int next = _aiTextVariant + 1;
      if (next >= _aiTextOptions.length) {
        // Every AI text in hand has been seen — ask the server for a fresh set
        // with a new theme variant (on failure the current set keeps cycling).
        setState(() => _report = null);
        _loadAiTextOptions(fresh: true);
        return;
      }
      setState(() {
        _aiTextVariant = next;
        _targetText = _aiTextOptions[_aiTextVariant % _aiTextOptions.length];
        _report = null;
      });
      return;
    }
    if (widget.focusWords.isNotEmpty) {
      setState(() {
        _focusTextVariant++;
        _targetText = _focusWordsText(widget.focusWords, _focusTextVariant);
        _report = null;
      });
      return;
    }
    final List<String> options = _sampleTexts(widget.level);
    if (options.length <= 1) return;
    final int currentIndex = options.indexOf(_targetText);
    final int nextIndex = currentIndex < 0
        ? 0
        : (currentIndex + 1 + Random().nextInt(options.length - 1)) %
            options.length;
    setState(() {
      _targetText = options[nextIndex];
      _report = null;
    });
  }

  void _tryAgain() {
    setState(() => _report = null);
  }

  // ---------------------------------------------------------------------------
  // Audio: model voice, word playback, recording, evaluation.
  // ---------------------------------------------------------------------------

  Future<void> _playModelVoice() async {
    if (_isPlayingModel) {
      await _audioPlayer.stop();
      return;
    }

    await _playTtsText(
      _targetText,
      unavailableMessage: _text(
        'Model sesi su an uretilemedi.',
        'Model voice could not be generated right now.',
      ),
      failedMessage: _text(
        'Model sesi calinamadi.',
        'Model voice could not be played.',
      ),
    );
  }

  Future<void> _playWordPronunciation(String word) async {
    final String cleanWord = word.trim();
    if (cleanWord.isEmpty || _isRecording || _isTranscribing) return;
    final Future<void> Function(String word)? overridePlayer =
        widget.wordPronunciationPlayer;
    if (overridePlayer != null) {
      await overridePlayer(cleanWord);
      return;
    }

    await _playTtsText(
      cleanWord,
      unavailableMessage: _text(
        'Kelime sesi su an uretilemedi.',
        'Word pronunciation could not be generated right now.',
      ),
      failedMessage: _text(
        'Kelime sesi calinamadi.',
        'Word pronunciation could not be played.',
      ),
    );
  }

  Future<void> _playTtsText(
    String text, {
    required String unavailableMessage,
    required String failedMessage,
  }) async {
    try {
      // 'default' rather than a pinned voice: the server picks its best
      // installed build. (Same reasoning as the legacy screen — pinning 'amy'
      // locked this screen out of the high-quality models.)
      final audio = await _ttsService.synthesize(text, voice: 'default');
      if (audio == null || audio.isEmpty) {
        _showSnack(unavailableMessage);
        return;
      }
      final Directory dir = await getTemporaryDirectory();
      final File file = File(
        '${dir.path}/klioai_nf_pronunciation_tts_${DateTime.now().millisecondsSinceEpoch}.wav',
      );
      await file.writeAsBytes(audio, flush: true);
      await _audioPlayer.setFilePath(file.path);
      await _audioPlayer.play();
    } catch (e) {
      _showSnack(failedMessage);
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopAndEvaluate();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    if (_isTranscribing) return;
    final bool hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      _showSnack(_text(
        'Mikrofon izni gerekli.',
        'Microphone permission is required.',
      ));
      return;
    }

    final Directory dir = await getTemporaryDirectory();
    final String path =
        '${dir.path}/klioai_nf_pronunciation_${DateTime.now().millisecondsSinceEpoch}.m4a';
    try {
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _recordingPath = path;
        _recordingStartedAt = DateTime.now();
        _report = null;
      });
      _recordingTimer?.cancel();
      _recordingTimer = Timer(const Duration(seconds: 45), _stopAndEvaluate);
    } catch (e) {
      _showSnack(_text(
        'Kayit baslatilamadi.',
        'Recording could not be started.',
      ));
    }
  }

  /// Uses the recorder directly rather than `NfSpeechCapture`.
  ///
  /// The tutor's capture service is hold-to-speak: it screens out low
  /// dynamic-range clips before uploading and only returns a transcript. This
  /// screen needs tap-to-toggle with a 45s cap, and it needs Whisper's
  /// measured duration to score reading pace honestly (client wall-clock
  /// includes touch latency and made the WPM read "too slow"). Those are
  /// exactly the two things `NfSpeechCapture` does not expose, so this keeps
  /// the legacy recorder pattern instead.
  Future<void> _stopAndEvaluate() async {
    if (!_isRecording) return;

    final DateTime? startedAt = _recordingStartedAt;
    String? path = _recordingPath;
    _recordingTimer?.cancel();
    try {
      path = await _audioRecorder.stop() ?? path;
    } catch (_) {}

    final int durationMs = startedAt == null
        ? 0
        : DateTime.now().difference(startedAt).inMilliseconds;

    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _isTranscribing = true;
      _recordingPath = null;
      _recordingStartedAt = null;
    });

    if (path == null || path.trim().isEmpty) {
      if (mounted) setState(() => _isTranscribing = false);
      _showSnack(_text('Kayit alinamadi.', 'Recording could not be captured.'));
      return;
    }

    try {
      final SpeechTranscription transcription =
          await _chatbotService.transcribeSpeechDetailed(
        audioPath: path,
        durationMs: durationMs,
        locale: 'en_US',
      );
      final String transcript = transcription.text;
      if (!mounted) return;
      if (transcript.isEmpty) {
        setState(() => _isTranscribing = false);
        _showSnack(_text(
          'Konusma algilanamadi. Biraz daha net tekrar dene.',
          'No speech was detected. Try one clearer repetition.',
        ));
        return;
      }
      final int effectiveDurationMs =
          transcription.measuredDurationMs ?? durationMs;
      final PronunciationReport report = _reportService.evaluate(
        targetText: _targetText,
        transcript: transcript,
        durationMs: effectiveDurationMs,
      );
      setState(() {
        _report = report;
        _isTranscribing = false;
      });
      await _awardPronunciationXp(report);
      await AnalyticsService.logPronunciationReportCompleted(
        level: widget.level,
        score: report.overallScore,
        placementMode: widget.placementMode,
        wordCount: report.targetWordMarks.length,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isTranscribing = false);
      if (await AiPaywallHandler.handleIfUpgradeRequired(context, e)) {
        return;
      }
      _showSnack(AiErrorMessageFormatter.forError(
        e,
        fallback: _text(
          'Telaffuz raporu su an hazirlanamadi.',
          'The pronunciation report could not be prepared right now.',
        ),
      ));
    } finally {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  Future<void> _awardPronunciationXp(PronunciationReport report) async {
    if (!mounted || widget.placementMode) return;
    _pronunciationAttemptSequence++;
    final AppStateProvider appState = context.read<AppStateProvider>();
    final String txBase =
        'pronunciation_${_targetText.hashCode}_${_pronunciationAttemptSequence}_${DateTime.now().millisecondsSinceEpoch}';
    await appState.addXPForAction(
      XPActionTypes.speakingComplete,
      source: 'Telaffuz Pratiği',
      transactionId: '$txBase:complete',
    );
    if (report.overallScore >= 90) {
      await appState.addXPForAction(
        XPActionTypes.speakingExcellent,
        source: 'Mükemmel Telaffuz',
        transactionId: '$txBase:excellent',
      );
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ---------------------------------------------------------------------------
  // Presentation — new design language, everything through NfTokens.
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    return Scaffold(
      backgroundColor: t.ground,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            NfSpace.s16,
            NfSpace.s12,
            NfSpace.s16,
            NfSpace.s26 + MediaQuery.paddingOf(context).bottom,
          ),
          children: <Widget>[
            _buildHeader(t),
            const SizedBox(height: NfSpace.s18),
            _buildTargetCard(t),
            const SizedBox(height: NfSpace.s14),
            _buildControls(t),
            const SizedBox(height: NfSpace.s14),
            if (_isTranscribing) _buildLoadingCard(t),
            if (_report != null) _buildReportCard(t, _report!),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(NfTokens t) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _NfBackButton(onPressed: () => Navigator.of(context).maybePop()),
        const SizedBox(width: NfSpace.s10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                // "Clarity", not "pronunciation": the score is transcript
                // alignment + pace, and the title must not claim phoneme-level
                // diagnosis before it exists (same reasoning as the legacy
                // screen).
                widget.placementMode
                    ? _text('Seviye Olcumu', 'Level Check')
                    : _text('Okuma Netligi Raporu', 'Reading Clarity Report'),
                style: NfTokens.display(size: NfFont.s22, color: t.ink),
              ),
              const SizedBox(height: NfSpace.s4),
              Text(
                widget.placementMode
                    ? _text(
                        'Kisa metni oku, onerilen baslangic seviyeni gor',
                        'Read the short text and get a starting-level suggestion',
                      )
                    : _text(
                        'Oku, kaydet ve netlik raporunu al',
                        'Read aloud, record, and get a clarity report',
                      ),
                style: NfTokens.body(size: NfFont.s135, color: t.inkMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTargetCard(NfTokens t) {
    return NfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  widget.placementMode
                      ? _text('Seviye metni', 'Level check text')
                      : widget.focusWords.isNotEmpty
                          ? _text(
                              'Kelimelerinden metin', 'Text from your words')
                          : _text('Okunacak metin', 'Text to read'),
                  style: NfTokens.body(
                    size: NfFont.s125,
                    weight: NfTokens.bodyEmphasisWeight,
                    color: t.inkMuted,
                  ),
                ),
              ),
              if (!widget.placementMode)
                NfChip(
                  label: _text('Degistir', 'Change'),
                  icon: _isGeneratingText
                      ? Icons.hourglass_top_rounded
                      : Icons.refresh_rounded,
                  dense: true,
                  variant: NfChipVariant.selected,
                  onTap: _isRecording || _isTranscribing
                      ? null
                      : _pickAnotherText,
                ),
            ],
          ),
          const SizedBox(height: NfSpace.s12),
          Text(
            _targetText,
            style: NfTokens.body(
              size: NfFont.s18,
              weight: NfTokens.bodyEmphasisWeight,
              color: t.ink,
              height: 1.45,
            ),
          ),
          const SizedBox(height: NfSpace.s12),
          Text(
            widget.placementMode
                ? _text(
                    'Ipucu: Bu sonuc genel Ingilizce seviyen degil, okuma ve telaffuz baslangic oneridir.',
                    'Tip: This is not your full English level, only a reading and pronunciation starting suggestion.',
                  )
                : widget.focusWords.isNotEmpty
                    ? _text(
                        'Ipucu: Metin sectigin kelimeleri kullaniyor. Once model sesi dinle, sonra ayni metni oku.',
                        'Tip: This text uses your selected words. Listen to the model first, then read it aloud.',
                      )
                    : _text(
                        'Ipucu: Once model sesi dinle, sonra ayni metni dogal hizda oku.',
                        'Tip: Listen to the model first, then read the same text at a natural pace.',
                      ),
            style: NfTokens.body(
              size: NfFont.s13,
              color: t.inkMuted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(NfTokens t) {
    return Row(
      children: <Widget>[
        Expanded(
          child: NfSecondaryButton(
            label: _isPlayingModel
                ? _text('Durdur', 'Stop')
                : _text('Modeli dinle', 'Model voice'),
            icon: _isPlayingModel
                ? Icons.stop_rounded
                : Icons.volume_up_rounded,
            tone: NfButtonTone.primary,
            height: NfSize.buttonPrimary,
            onPressed:
                _isRecording || _isTranscribing ? null : _playModelVoice,
          ),
        ),
        const SizedBox(width: NfSpace.s12),
        Expanded(
          child: _isRecording
              ? NfSecondaryButton(
                  label: _text('Bitir', 'Finish'),
                  icon: Icons.stop_rounded,
                  tone: NfButtonTone.wrong,
                  height: NfSize.buttonPrimary,
                  onPressed: _toggleRecording,
                )
              : NfPrimaryButton(
                  label: _text('Kaydet', 'Record'),
                  icon: Icons.mic_rounded,
                  onPressed: _isTranscribing ? null : _toggleRecording,
                ),
        ),
      ],
    );
  }

  Widget _buildLoadingCard(NfTokens t) {
    return NfCard(
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: NfStroke.iconHeavy,
              valueColor: AlwaysStoppedAnimation<Color>(t.primary),
            ),
          ),
          const SizedBox(width: NfSpace.s14),
          Expanded(
            child: Text(
              _text(
                'Ses yazıya cevriliyor ve rapor hazirlaniyor...',
                'Transcribing speech and preparing the report...',
              ),
              style: NfTokens.body(size: NfFont.s14, color: t.ink),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportCard(NfTokens t, PronunciationReport report) {
    return NfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 58,
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _scoreSoftColor(t, report.overallScore),
                  border: Border.fromBorderSide(
                    t.sideOf(_scoreColor(t, report.overallScore)),
                  ),
                ),
                child: Text(
                  '${report.overallScore}',
                  style: NfTokens.display(
                    size: NfFont.s18,
                    color: _scoreColor(t, report.overallScore),
                  ),
                ),
              ),
              const SizedBox(width: NfSpace.s14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _localizedClarityLabel(report),
                      style: NfTokens.display(size: NfFont.s18, color: t.ink),
                    ),
                    const SizedBox(height: NfSpace.s4),
                    Text(
                      _localizedSummary(report),
                      style: NfTokens.body(
                        size: NfFont.s13,
                        color: t.inkMuted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: NfSpace.s18),
          _buildMetricRow(
            t,
            _text('Metin eslesmesi', 'Text match'),
            report.accuracyScore,
          ),
          _buildMetricRow(
            t,
            _text('Okuma hizi', 'Reading pace'),
            report.paceScore,
            detail: '${report.wordsPerMinute.round()} WPM',
          ),
          const SizedBox(height: NfSpace.s14),
          _buildNextStepCard(t, report),
          if (widget.placementMode) ...<Widget>[
            const SizedBox(height: NfSpace.s14),
            _buildPlacementCard(t, report),
          ],
          const SizedBox(height: NfSpace.s14),
          _buildTargetReview(t, report),
          const SizedBox(height: NfSpace.s14),
          _buildTranscriptBlock(t, report),
          const SizedBox(height: NfSpace.s14),
          _buildWordFeedback(t, report),
          const SizedBox(height: NfSpace.s16),
          _buildReportActions(t),
        ],
      ),
    );
  }

  /// Score → semantic colour: high is a correct result, low needs another go.
  /// The bands match the ones `_localizedClarityLabel` already speaks in.
  Color _scoreColor(NfTokens t, int score) {
    if (score >= 75) return t.correct;
    if (score >= 60) return t.streakText;
    return t.wrong;
  }

  Color _scoreSoftColor(NfTokens t, int score) {
    if (score >= 75) return t.correctSoft;
    if (score >= 60) return t.streakSoft;
    return t.wrongSoft;
  }

  Widget _buildMetricRow(
    NfTokens t,
    String label,
    int value, {
    String? detail,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: NfSpace.s10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: NfTokens.body(
                    size: NfFont.s135,
                    weight: NfTokens.bodyEmphasisWeight,
                    color: t.ink,
                  ),
                ),
              ),
              Text(
                detail ?? '$value%',
                style: NfTokens.body(size: NfFont.s125, color: t.inkMuted),
              ),
            ],
          ),
          const SizedBox(height: NfSpace.s6),
          NfProgressBar(
            value: value / 100,
            semanticsLabel: label,
          ),
        ],
      ),
    );
  }

  Widget _buildTranscriptBlock(NfTokens t, PronunciationReport report) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(NfSpace.s14),
      decoration: BoxDecoration(
        color: t.raised,
        borderRadius: NfRadius.tileAll,
        border: Border.fromBorderSide(t.side),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _text('Algilanan metin', 'Detected speech'),
            style: NfTokens.body(
              size: NfFont.s12,
              weight: NfTokens.bodyEmphasisWeight,
              color: t.inkMuted,
            ),
          ),
          const SizedBox(height: NfSpace.s8),
          Text(
            report.transcript,
            style: NfTokens.body(
              size: NfFont.s145,
              color: t.ink,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNextStepCard(NfTokens t, PronunciationReport report) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(NfSpace.s14),
      decoration: BoxDecoration(
        color: t.primarySoft,
        borderRadius: NfRadius.tileAll,
        border: Border.fromBorderSide(t.sideOf(t.primary)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.track_changes_rounded, color: t.primaryText, size: 20),
          const SizedBox(width: NfSpace.s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _text('Sonraki deneme', 'Next attempt'),
                  style: NfTokens.body(
                    size: NfFont.s135,
                    weight: NfTokens.bodyEmphasisWeight,
                    color: t.ink,
                  ),
                ),
                const SizedBox(height: NfSpace.s4),
                Text(
                  _localizedNextStep(report),
                  style: NfTokens.body(
                    size: NfFont.s13,
                    color: t.inkMuted,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: NfSpace.s4),
                Text(
                  _localizedPaceFeedback(report),
                  style: NfTokens.body(
                    size: NfFont.s12,
                    color: t.inkFaint,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlacementCard(NfTokens t, PronunciationReport report) {
    final String suggestedLevel = _suggestedPlacementLevel(report);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(NfSpace.s14),
      decoration: BoxDecoration(
        color: t.raised,
        borderRadius: NfRadius.tileAll,
        border: Border.fromBorderSide(t.side),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: NfSize.minTap,
            height: NfSize.minTap,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: t.primarySoft,
              border: Border.fromBorderSide(t.sideOf(t.primary)),
            ),
            child: Text(
              suggestedLevel,
              style: NfTokens.display(size: NfFont.s14, color: t.primaryText),
            ),
          ),
          const SizedBox(width: NfSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _text('Onerilen baslangic', 'Suggested start'),
                  style: NfTokens.body(
                    size: NfFont.s135,
                    weight: NfTokens.bodyEmphasisWeight,
                    color: t.ink,
                  ),
                ),
                const SizedBox(height: NfSpace.s4),
                Text(
                  _localizedPlacementCopy(report, suggestedLevel),
                  style: NfTokens.body(
                    size: NfFont.s13,
                    color: t.inkMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetReview(NfTokens t, PronunciationReport report) {
    if (report.targetWordMarks.isEmpty) {
      return const SizedBox.shrink();
    }
    final bool hasProblemWords = report.targetWordMarks.any(
      (PronunciationWordMark mark) =>
          mark.status != PronunciationWordStatus.matched,
    );
    if (!hasProblemWords) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: NfSpace.s14,
          vertical: NfSpace.s12,
        ),
        decoration: BoxDecoration(
          color: t.correctSoft,
          borderRadius: NfRadius.tileAll,
          border: Border.fromBorderSide(t.sideOf(t.correct)),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.check_circle_outline_rounded,
                color: t.correct, size: 20),
            const SizedBox(width: NfSpace.s10),
            Expanded(
              child: Text(
                _text(
                  'Tum kelimeler hedef metinle eslesti.',
                  'All words matched the target text.',
                ),
                style: NfTokens.body(
                  size: NfFont.s13,
                  weight: NfTokens.bodyEmphasisWeight,
                  color: t.correct,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          _text('Kelime kontrolu', 'Word review'),
          style: NfTokens.body(
            size: NfFont.s12,
            weight: NfTokens.bodyEmphasisWeight,
            color: t.inkMuted,
          ),
        ),
        const SizedBox(height: NfSpace.s4),
        Text(
          _text(
            'Vurgulanan kelimelere dokunup model telaffuzunu dinleyebilirsin.',
            'Tap highlighted words to hear the model pronunciation.',
          ),
          style: NfTokens.body(
            size: NfFont.s115,
            color: t.inkFaint,
            height: 1.3,
          ),
        ),
        const SizedBox(height: NfSpace.s8),
        Wrap(
          spacing: NfSpace.s6,
          runSpacing: NfSpace.s6,
          children:
              report.targetWordMarks.map((PronunciationWordMark mark) {
            final bool matched =
                mark.status == PronunciationWordStatus.matched;
            // "Unclear" alone teaches nothing: show what Whisper heard
            // ("ship → sheep") so the learner knows which sound to fix. The
            // alignment already computed it — same as the legacy screen.
            final bool showHeardAs =
                mark.status == PronunciationWordStatus.unclear &&
                    mark.heardAs != null &&
                    mark.heardAs != mark.word;
            final String label =
                showHeardAs ? '${mark.word} → ${mark.heardAs}' : mark.word;
            if (matched) {
              return NfChip(
                key: ValueKey<String>(
                    'pronunciation-target-word-${mark.word}'),
                label: label,
                dense: true,
                variant: NfChipVariant.correct,
              );
            }
            return NfChip(
              key: ValueKey<String>('pronunciation-target-word-${mark.word}'),
              label: label,
              dense: true,
              icon: Icons.volume_up_rounded,
              variant: NfChipVariant.wrong,
              onTap: () => _playWordPronunciation(mark.word),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildReportActions(NfTokens t) {
    return Row(
      children: <Widget>[
        Expanded(
          child: NfSecondaryButton(
            label: _text('Tekrar oku', 'Try again'),
            icon: Icons.replay_rounded,
            onPressed: _tryAgain,
          ),
        ),
        const SizedBox(width: NfSpace.s10),
        Expanded(
          child: NfSecondaryButton(
            label: widget.placementMode
                ? _text('Tekrar olc', 'Check again')
                : _text('Yeni metin', 'New text'),
            icon: Icons.refresh_rounded,
            tone: NfButtonTone.primary,
            onPressed: _pickAnotherText,
          ),
        ),
      ],
    );
  }

  Widget _buildWordFeedback(NfTokens t, PronunciationReport report) {
    final bool hasMissing = report.missingWords.isNotEmpty;
    final bool hasExtra = report.extraWords.isNotEmpty;
    if (!hasMissing && !hasExtra) {
      return Text(
        _text(
          'Belirgin eksik veya fazladan kelime yok.',
          'No obvious missing or extra words.',
        ),
        style: NfTokens.body(size: NfFont.s13, color: t.inkMuted),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (hasMissing)
          _buildChipGroup(
            t,
            _text('Eksik/yanlis algilanan', 'Missing or unclear'),
            report.missingWords,
          ),
        if (hasExtra) ...<Widget>[
          const SizedBox(height: NfSpace.s12),
          _buildChipGroup(
            t,
            _text('Fazladan algilanan', 'Extra detected'),
            report.extraWords,
          ),
        ],
      ],
    );
  }

  Widget _buildChipGroup(NfTokens t, String title, List<String> words) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: NfTokens.body(
            size: NfFont.s12,
            weight: NfTokens.bodyEmphasisWeight,
            color: t.inkMuted,
          ),
        ),
        const SizedBox(height: NfSpace.s4),
        Text(
          _text('Dinlemek icin kelimeye dokun.', 'Tap a word to hear it.'),
          style: NfTokens.body(size: NfFont.s115, color: t.inkFaint),
        ),
        const SizedBox(height: NfSpace.s8),
        Wrap(
          spacing: NfSpace.s8,
          runSpacing: NfSpace.s8,
          children: words.take(8).map((String word) {
            return NfChip(
              key: ValueKey<String>('pronunciation-feedback-word-$word'),
              label: word,
              dense: true,
              icon: Icons.volume_up_rounded,
              variant: NfChipVariant.selected,
              onTap: () => _playWordPronunciation(word),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Localised report copy — identical rules to the legacy screen.
  // ---------------------------------------------------------------------------

  String _localizedClarityLabel(PronunciationReport report) {
    if (!_isTurkish) return report.clarityLabel;
    if (report.overallScore >= 90) return 'Harika';
    if (report.overallScore >= 75) return 'Net';
    if (report.overallScore >= 60) return 'Biraz calisma gerek';
    return 'Tekrar dene';
  }

  String _localizedSummary(PronunciationReport report) {
    if (!_isTurkish) return report.summary;
    final StringBuffer buffer = StringBuffer();
    if (report.overallScore >= 85) {
      buffer.write('Güçlü bir okuma. Kelimelerin çoğu net algılandı.');
    } else if (report.overallScore >= 65) {
      buffer.write('İyi deneme. Özellikle işaretlenen kelimelere odaklan.');
    } else {
      buffer.write('Biraz daha yavaş ve kelimeleri ayırarak tekrar dene.');
    }

    if (report.wordsPerMinute > 0 && report.wordsPerMinute < 85) {
      buffer.write(' Hızın biraz yavaş.');
    } else if (report.wordsPerMinute > 165) {
      buffer.write(' Hızın biraz yüksek.');
    }

    if (report.missingWords.isEmpty && report.extraWords.isEmpty) {
      buffer.write(' Algılanan metin hedef metne çok yakın.');
    }
    return buffer.toString();
  }

  String _localizedNextStep(PronunciationReport report) {
    if (!_isTurkish) return report.nextStep;
    if (report.missingWords.isNotEmpty) {
      final String focus = report.missingWords.take(3).join(', ');
      return 'Bir kez daha oku ve şu kelimeleri daha net söyle: $focus.';
    }
    if (report.extraWords.isNotEmpty) {
      final String focus = report.extraWords.take(3).join(', ');
      return 'Bir kez daha oku ve fazladan algılanan şu kelimelerden kaçın: $focus.';
    }
    if (report.wordsPerMinute > 0 && report.wordsPerMinute < 85) {
      return 'Aynı metni daha akıcı ve daha az duraksayarak tekrar dene.';
    }
    if (report.wordsPerMinute > 165) {
      return 'Aynı metni biraz daha yavaş, özellikle virgüllerde nefes vererek oku.';
    }
    if (report.overallScore >= 90) {
      return 'Sonuç iyi. Metni değiştir veya daha zor bir seviyeye geç.';
    }
    return 'Bir kez daha oku; ritme ve kelime sonlarını net bitirmeye odaklan.';
  }

  String _localizedPaceFeedback(PronunciationReport report) {
    if (!_isTurkish) return report.paceFeedback;
    final double wordsPerMinute = report.wordsPerMinute;
    if (wordsPerMinute <= 0) {
      return 'Henüz tempo algılanmadı.';
    }
    if (wordsPerMinute < 85) {
      return 'Doğal okuma için yaklaşık hedef aralık: 95-155 WPM.';
    }
    if (wordsPerMinute > 165) {
      return 'Biraz yavaşla ve her kelimeye daha fazla alan bırak.';
    }
    return 'Okuma hızın doğal aralıkta.';
  }

  String _suggestedPlacementLevel(PronunciationReport report) {
    if (report.accuracyScore >= 96 && report.paceScore >= 90) return 'B2';
    if (report.accuracyScore >= 86 && report.paceScore >= 70) return 'B1';
    if (report.accuracyScore >= 70) return 'A2';
    return 'A1';
  }

  String _localizedPlacementCopy(
    PronunciationReport report,
    String suggestedLevel,
  ) {
    if (!_isTurkish) {
      return 'Based on this short reading, start pronunciation practice around $suggestedLevel. You can still choose any level manually.';
    }
    return 'Bu kisa okumaya gore telaffuz calismasina $suggestedLevel civarindan baslamak mantikli. Istersen seviyeyi yine manuel degistirebilirsin.';
  }
}

/// Back control in the new language: a bordered 44px tile, no ripple.
class _NfBackButton extends StatelessWidget {
  const _NfBackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    return Semantics(
      button: true,
      label: MaterialLocalizations.of(context).backButtonTooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: Container(
            width: NfSize.minTap,
            height: NfSize.minTap,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: NfRadius.iconTileAll,
              border: Border.fromBorderSide(t.side),
            ),
            child: Icon(Icons.arrow_back_rounded, color: t.ink, size: 22),
          ),
        ),
      ),
    );
  }
}
