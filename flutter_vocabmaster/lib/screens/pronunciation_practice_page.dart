import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../providers/app_state_provider.dart';
import '../services/ai_error_message_formatter.dart';
import '../services/ai_paywall_handler.dart';
import '../services/analytics_service.dart';
import '../services/chatbot_service.dart';
import '../services/piper_tts_service.dart';
import '../services/pronunciation_report_service.dart';
import '../services/xp_manager.dart';
import '../theme/app_theme.dart';
import '../theme/theme_catalog.dart';
import '../theme/theme_provider.dart';
import '../widgets/animated_background.dart';
import '../widgets/modern_background.dart';
import '../widgets/modern_card.dart';

class PronunciationPracticePage extends StatefulWidget {
  final String level;
  final bool placementMode;
  final List<String> focusWords;
  final String? initialText;
  final List<String> initialTextOptions;
  final PronunciationReport? initialReport;
  final Future<void> Function(String word)? wordPronunciationPlayer;

  const PronunciationPracticePage({
    super.key,
    this.level = 'B1',
    this.placementMode = false,
    this.focusWords = const [],
    this.initialText,
    this.initialTextOptions = const [],
    this.initialReport,
    this.wordPronunciationPlayer,
  });

  @override
  State<PronunciationPracticePage> createState() =>
      _PronunciationPracticePageState();
}

class _PronunciationPracticePageState extends State<PronunciationPracticePage> {
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
  bool _isPlayingModel = false;
  bool _isRecording = false;
  bool _isTranscribing = false;
  bool _isGeneratingText = false;
  String? _recordingPath;
  DateTime? _recordingStartedAt;
  Timer? _recordingTimer;
  PronunciationReport? _report;
  int _pronunciationAttemptSequence = 0;
  List<String> _aiTextOptions = const [];

  AppThemeConfig _theme({bool listen = true}) {
    try {
      return Provider.of<ThemeProvider?>(context, listen: listen)
              ?.currentTheme ??
          VocabThemes.defaultTheme;
    } catch (_) {
      return VocabThemes.defaultTheme;
    }
  }

  bool get _isTurkish => Localizations.localeOf(context).languageCode == 'tr';

  String _text(String tr, String en) => _isTurkish ? tr : en;

  @override
  void initState() {
    super.initState();
    final providedTexts = _providedTextOptions();
    _targetText = providedTexts.isNotEmpty
        ? providedTexts.first
        : widget.placementMode
            ? _placementText()
            : widget.focusWords.isNotEmpty
                ? _focusWordsText(widget.focusWords, _focusTextVariant)
                : _sampleTexts(widget.level).first;
    _report = widget.initialReport;
    _audioPlayer.playerStateStream.listen((state) {
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

  List<String> _sampleTexts(String level) {
    final normalized = level.toUpperCase();
    if (normalized == 'A1' || normalized == 'A2') {
      return const [
        'I usually drink coffee before I start studying English.',
        'My friend and I walked to the station after lunch.',
        'Could you tell me where the nearest bus stop is?',
      ];
    }
    if (normalized == 'B2' || normalized == 'C1' || normalized == 'C2') {
      return const [
        'Although the meeting was delayed, everyone stayed calm and focused.',
        'The article explains how small daily habits can improve long-term learning.',
        'If the weather improves tomorrow, we might record the interview outside.',
      ];
    }
    return const [
      'I need to explain the problem clearly before we choose a solution.',
      'The speaker gave a short example to support her main idea.',
      'Learning a language becomes easier when practice feels useful.',
    ];
  }

  String _placementText() {
    return 'A useful habit is easier to keep when it fits naturally into your day.';
  }

  List<String> _providedTextOptions() {
    final seen = <String>{};
    final result = <String>[];

    void addText(String? rawText) {
      final text = (rawText ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
      if (text.isEmpty) return;
      final key = text.toLowerCase();
      if (seen.add(key)) {
        result.add(text);
      }
    }

    addText(widget.initialText);
    for (final option in widget.initialTextOptions) {
      addText(option);
    }
    return result;
  }

  String _focusWordsText(List<String> rawWords, int variant) {
    final words = _cleanFocusWords(rawWords);
    if (words.isEmpty) {
      return _sampleTexts(widget.level).first;
    }
    final joined = _joinEnglishList(words);
    final leadWord = words.first;
    final variants = [
      'During today\'s practice, I used $joined in one clear explanation.',
      'The speaker repeated $joined slowly, then used $leadWord in a natural sentence.',
      'To improve my English, I practiced $joined until each word sounded clear.',
    ];
    return variants[variant % variants.length];
  }

  List<String> _cleanFocusWords(List<String> rawWords) {
    final seen = <String>{};
    final result = <String>[];
    for (final rawWord in rawWords) {
      final word = rawWord.trim();
      if (word.isEmpty) continue;
      final key = word.toLowerCase();
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

  Future<void> _loadAiTextOptions() async {
    if (_isGeneratingText) return;
    setState(() => _isGeneratingText = true);
    final texts = await _chatbotService.generatePronunciationTexts(
      level: widget.level,
      focusWords: _cleanFocusWords(widget.focusWords),
    );
    if (!mounted) return;
    setState(() {
      _isGeneratingText = false;
      _aiTextOptions = texts;
      _aiTextVariant = 0;
      if (texts.isNotEmpty &&
          !_isRecording &&
          !_isTranscribing &&
          _report == null) {
        _targetText = texts.first;
      }
    });
  }

  void _pickAnotherText() {
    if (widget.placementMode) {
      setState(() => _report = null);
      return;
    }
    final providedTexts = _providedTextOptions();
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
      setState(() {
        _aiTextVariant++;
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
    final options = _sampleTexts(widget.level);
    if (options.length <= 1) return;
    final currentIndex = options.indexOf(_targetText);
    final nextIndex = currentIndex < 0
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
    final cleanWord = word.trim();
    if (cleanWord.isEmpty || _isRecording || _isTranscribing) return;
    final overridePlayer = widget.wordPronunciationPlayer;
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
      final audio = await _ttsService.synthesize(text, voice: 'amy');
      if (audio == null || audio.isEmpty) {
        _showSnack(unavailableMessage);
        return;
      }
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/klioai_pronunciation_tts_${DateTime.now().millisecondsSinceEpoch}.wav',
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
    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      _showSnack(_text(
        'Mikrofon izni gerekli.',
        'Microphone permission is required.',
      ));
      return;
    }

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/klioai_pronunciation_${DateTime.now().millisecondsSinceEpoch}.m4a';
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

  Future<void> _stopAndEvaluate() async {
    if (!_isRecording) return;

    final startedAt = _recordingStartedAt;
    var path = _recordingPath;
    _recordingTimer?.cancel();
    try {
      path = await _audioRecorder.stop() ?? path;
    } catch (_) {}

    final durationMs = startedAt == null
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
      final transcription = await _chatbotService.transcribeSpeechDetailed(
        audioPath: path,
        durationMs: durationMs,
        locale: 'en_US',
      );
      final transcript = transcription.text;
      if (!mounted) return;
      if (transcript.isEmpty) {
        setState(() => _isTranscribing = false);
        _showSnack(_text(
          'Konusma algilanamadi. Biraz daha net tekrar dene.',
          'No speech was detected. Try one clearer repetition.',
        ));
        return;
      }
      // Whisper'ın ölçtüğü süre varsa onu kullan: istemci duvar-saati dokunma
      // gecikmesini ve kayıt kuyruk süresini içerdiği için WPM'i düşük gösterip
      // haksız "çok yavaş" geri bildirimine yol açabiliyordu.
      final effectiveDurationMs =
          transcription.measuredDurationMs ?? durationMs;
      final report = _reportService.evaluate(
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
    final appState = context.read<AppStateProvider>();
    final txBase =
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

  @override
  Widget build(BuildContext context) {
    final selectedTheme = _theme();
    return Scaffold(
      body: Stack(
        children: [
          const AnimatedBackground(isDark: true),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                _buildHeader(selectedTheme),
                const SizedBox(height: 20),
                _buildTargetCard(selectedTheme),
                const SizedBox(height: 16),
                _buildControls(selectedTheme),
                const SizedBox(height: 16),
                if (_isTranscribing) _buildLoadingCard(selectedTheme),
                if (_report != null) _buildReportCard(selectedTheme, _report!),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(AppThemeConfig selectedTheme) {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                // "Reading clarity", not "pronunciation": the current scoring
                // is transcript-alignment + pace (see PRONUNCIATION_PRACTICE_MVP
                // doc); phoneme-level pronunciation scoring is roadmap, and the
                // title should not claim it before it exists.
                widget.placementMode
                    ? _text('Seviye Olcumu', 'Level Check')
                    : _text('Okuma Netligi Raporu', 'Reading Clarity Report'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _text(
                  widget.placementMode
                      ? 'Kisa metni oku, onerilen baslangic seviyeni gor'
                      : 'Oku, kaydet ve netlik raporunu al',
                  widget.placementMode
                      ? 'Read the short text and get a starting-level suggestion'
                      : 'Read aloud, record, and get a clarity report',
                ),
                style: TextStyle(
                  color: selectedTheme.colors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTargetCard(AppThemeConfig selectedTheme) {
    return ModernCard(
      showGlow: true,
      borderRadius: BorderRadius.circular(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.article_outlined, color: selectedTheme.colors.accent),
              const SizedBox(width: 10),
              Text(
                widget.placementMode
                    ? _text('Seviye metni', 'Level check text')
                    : widget.focusWords.isNotEmpty
                        ? _text('Kelimelerinden metin', 'Text from your words')
                        : _text('Okunacak metin', 'Text to read'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (!widget.placementMode)
                TextButton.icon(
                  onPressed:
                      _isRecording || _isTranscribing ? null : _pickAnotherText,
                  icon: Icon(
                    _isGeneratingText
                        ? Icons.hourglass_top_rounded
                        : Icons.refresh,
                    size: 16,
                  ),
                  label: Text(_text('Degistir', 'Change')),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _targetText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _text(
              widget.placementMode
                  ? 'Ipucu: Bu sonuc genel Ingilizce seviyen degil, okuma ve telaffuz baslangic oneridir.'
                  : widget.focusWords.isNotEmpty
                      ? 'Ipucu: Metin sectigin kelimeleri kullaniyor. Once model sesi dinle, sonra ayni metni oku.'
                      : 'Ipucu: Once model sesi dinle, sonra ayni metni dogal hizda oku.',
              widget.placementMode
                  ? 'Tip: This is not your full English level, only a reading and pronunciation starting suggestion.'
                  : widget.focusWords.isNotEmpty
                      ? 'Tip: This text uses your selected words. Listen to the model first, then read it aloud.'
                      : 'Tip: Listen to the model first, then read the same text at a natural pace.',
            ),
            style: TextStyle(
              color: selectedTheme.colors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(AppThemeConfig selectedTheme) {
    return Row(
      children: [
        Expanded(
          child: _buildActionButton(
            selectedTheme,
            icon: _isPlayingModel ? Icons.stop_rounded : Icons.volume_up,
            label: _isPlayingModel
                ? _text('Durdur', 'Stop')
                : _text('Modeli dinle', 'Model voice'),
            onTap: _isRecording || _isTranscribing ? null : _playModelVoice,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildActionButton(
            selectedTheme,
            icon: _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
            label: _isRecording
                ? _text('Bitir', 'Finish')
                : _text('Kaydet', 'Record'),
            emphasized: true,
            onTap: _isTranscribing ? null : _toggleRecording,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(
    AppThemeConfig selectedTheme, {
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool emphasized = false,
  }) {
    return ModernCard(
      variant:
          emphasized ? BackgroundVariant.accent : BackgroundVariant.primary,
      borderRadius: BorderRadius.circular(16),
      padding: EdgeInsets.zero,
      showGlow: emphasized && onTap != null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onTap == null
                        ? selectedTheme.colors.textSecondary
                        : Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingCard(AppThemeConfig selectedTheme) {
    return ModernCard(
      borderRadius: BorderRadius.circular(18),
      child: Row(
        children: [
          CircularProgressIndicator(color: selectedTheme.colors.accent),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              _text('Ses yazıya cevriliyor ve rapor hazirlaniyor...',
                  'Transcribing speech and preparing the report...'),
              style: const TextStyle(color: Colors.white, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportCard(
    AppThemeConfig selectedTheme,
    PronunciationReport report,
  ) {
    return ModernCard(
      showGlow: true,
      borderRadius: BorderRadius.circular(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selectedTheme.colors.accent.withValues(alpha: 0.14),
                  border: Border.all(color: selectedTheme.colors.accent),
                ),
                child: Center(
                  child: Text(
                    '${report.overallScore}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _localizedClarityLabel(report),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _localizedSummary(report),
                      style: TextStyle(
                        color: selectedTheme.colors.textSecondary,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _buildMetricRow(
            selectedTheme,
            _text('Metin eslesmesi', 'Text match'),
            report.accuracyScore,
          ),
          _buildMetricRow(
            selectedTheme,
            _text('Okuma hizi', 'Reading pace'),
            report.paceScore,
            detail: '${report.wordsPerMinute.round()} WPM',
          ),
          const SizedBox(height: 14),
          _buildNextStepCard(selectedTheme, report),
          const SizedBox(height: 14),
          if (widget.placementMode) ...[
            _buildPlacementCard(selectedTheme, report),
            const SizedBox(height: 14),
          ],
          _buildTargetReview(selectedTheme, report),
          const SizedBox(height: 14),
          _buildTranscriptBlock(selectedTheme, report),
          const SizedBox(height: 14),
          _buildWordFeedback(selectedTheme, report),
          const SizedBox(height: 16),
          _buildReportActions(selectedTheme),
        ],
      ),
    );
  }

  Widget _buildMetricRow(
    AppThemeConfig selectedTheme,
    String label,
    int value, {
    String? detail,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                detail ?? '$value%',
                style: TextStyle(color: selectedTheme.colors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: value / 100,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor:
                  AlwaysStoppedAnimation<Color>(selectedTheme.colors.accent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTranscriptBlock(
    AppThemeConfig selectedTheme,
    PronunciationReport report,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: selectedTheme.colors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _text('Algilanan metin', 'Detected speech'),
            style: TextStyle(
              color: selectedTheme.colors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            report.transcript,
            style: const TextStyle(
              color: Colors.white,
              height: 1.4,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNextStepCard(
    AppThemeConfig selectedTheme,
    PronunciationReport report,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: selectedTheme.colors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selectedTheme.colors.accent.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.track_changes_rounded,
            color: selectedTheme.colors.accent,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _text('Sonraki deneme', 'Next attempt'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _localizedNextStep(report),
                  style: TextStyle(
                    color: selectedTheme.colors.textSecondary,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _localizedPaceFeedback(report),
                  style: TextStyle(
                    color: selectedTheme.colors.textSecondary
                        .withValues(alpha: 0.82),
                    fontSize: 12,
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

  Widget _buildPlacementCard(
    AppThemeConfig selectedTheme,
    PronunciationReport report,
  ) {
    final suggestedLevel = _suggestedPlacementLevel(report);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: selectedTheme.colors.cardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selectedTheme.colors.accent.withValues(alpha: 0.12),
              border: Border.all(color: selectedTheme.colors.accent),
            ),
            child: Center(
              child: Text(
                suggestedLevel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _text('Onerilen baslangic', 'Suggested start'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _localizedPlacementCopy(report, suggestedLevel),
                  style: TextStyle(
                    color: selectedTheme.colors.textSecondary,
                    fontSize: 13,
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

  Widget _buildTargetReview(
    AppThemeConfig selectedTheme,
    PronunciationReport report,
  ) {
    if (report.targetWordMarks.isEmpty) {
      return const SizedBox.shrink();
    }
    final hasProblemWords = report.targetWordMarks.any(
      (mark) => mark.status != PronunciationWordStatus.matched,
    );
    if (!hasProblemWords) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selectedTheme.colors.accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selectedTheme.colors.accent.withValues(alpha: 0.28),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              color: selectedTheme.colors.accent,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _text(
                  'Tum kelimeler hedef metinle eslesti.',
                  'All words matched the target text.',
                ),
                style: TextStyle(
                  color: selectedTheme.colors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _text('Kelime kontrolu', 'Word review'),
          style: TextStyle(
            color: selectedTheme.colors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _text(
            'Vurgulanan kelimelere dokunup model telaffuzunu dinleyebilirsin.',
            'Tap highlighted words to hear the model pronunciation.',
          ),
          style: TextStyle(
            color: selectedTheme.colors.textSecondary.withValues(alpha: 0.78),
            fontSize: 11,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: report.targetWordMarks.map((mark) {
            final accent = _wordMarkColor(selectedTheme, mark.status);
            final backgroundAlpha =
                mark.status == PronunciationWordStatus.matched ? 0.08 : 0.16;
            // "Net değil" tek başına öğretici değil: Whisper'ın ne duyduğunu
            // da göster ("ship → sheep") ki kullanıcı hangi sesi düzelteceğini
            // bilsin. Bu çift hizalamada zaten hesaplanıyordu.
            final showHeardAs = mark.status ==
                    PronunciationWordStatus.unclear &&
                mark.heardAs != null &&
                mark.heardAs != mark.word;
            final chip = Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: backgroundAlpha),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: accent.withValues(alpha: 0.55)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    mark.word,
                    style: TextStyle(
                      color: mark.status == PronunciationWordStatus.matched
                          ? selectedTheme.colors.textSecondary
                          : Colors.white,
                      fontSize: 12,
                      fontWeight:
                          mark.status == PronunciationWordStatus.matched
                              ? FontWeight.w500
                              : FontWeight.bold,
                    ),
                  ),
                  if (showHeardAs) ...[
                    const SizedBox(width: 4),
                    Text(
                      '→ ${mark.heardAs}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            );
            if (mark.status == PronunciationWordStatus.matched) {
              return chip;
            }
            return InkWell(
              key: ValueKey('pronunciation-target-word-${mark.word}'),
              onTap: () => _playWordPronunciation(mark.word),
              borderRadius: BorderRadius.circular(999),
              child: chip,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildReportActions(AppThemeConfig selectedTheme) {
    return Row(
      children: [
        Expanded(
          child: _buildSmallReportAction(
            selectedTheme,
            icon: Icons.replay_rounded,
            label: _text('Tekrar oku', 'Try again'),
            onTap: _tryAgain,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildSmallReportAction(
            selectedTheme,
            icon: Icons.refresh_rounded,
            label: widget.placementMode
                ? _text('Tekrar olc', 'Check again')
                : _text('Yeni metin', 'New text'),
            onTap: _pickAnotherText,
            emphasized: true,
          ),
        ),
      ],
    );
  }

  Widget _buildSmallReportAction(
    AppThemeConfig selectedTheme, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool emphasized = false,
  }) {
    final borderColor = emphasized
        ? selectedTheme.colors.accent.withValues(alpha: 0.55)
        : selectedTheme.colors.cardBorder;
    final backgroundColor = emphasized
        ? selectedTheme.colors.accent.withValues(alpha: 0.12)
        : Colors.white.withValues(alpha: 0.04);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: emphasized ? selectedTheme.colors.accent : Colors.white,
              size: 18,
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _wordMarkColor(
    AppThemeConfig selectedTheme,
    PronunciationWordStatus status,
  ) {
    switch (status) {
      case PronunciationWordStatus.matched:
        return selectedTheme.colors.accent;
      case PronunciationWordStatus.missing:
        return Colors.orangeAccent;
      case PronunciationWordStatus.unclear:
        return Colors.pinkAccent;
    }
  }

  Widget _buildWordFeedback(
    AppThemeConfig selectedTheme,
    PronunciationReport report,
  ) {
    final hasMissing = report.missingWords.isNotEmpty;
    final hasExtra = report.extraWords.isNotEmpty;
    if (!hasMissing && !hasExtra) {
      return Text(
        _text(
          'Belirgin eksik veya fazladan kelime yok.',
          'No obvious missing or extra words.',
        ),
        style: TextStyle(color: selectedTheme.colors.textSecondary),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasMissing)
          _buildChipGroup(
            selectedTheme,
            _text('Eksik/yanlis algilanan', 'Missing or unclear'),
            report.missingWords,
          ),
        if (hasExtra) ...[
          const SizedBox(height: 12),
          _buildChipGroup(
            selectedTheme,
            _text('Fazladan algilanan', 'Extra detected'),
            report.extraWords,
          ),
        ],
      ],
    );
  }

  Widget _buildChipGroup(
    AppThemeConfig selectedTheme,
    String title,
    List<String> words,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: selectedTheme.colors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _text(
            'Dinlemek icin kelimeye dokun.',
            'Tap a word to hear it.',
          ),
          style: TextStyle(
            color: selectedTheme.colors.textSecondary.withValues(alpha: 0.78),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: words.take(8).map((word) {
            return InkWell(
              key: ValueKey('pronunciation-feedback-word-$word'),
              onTap: () => _playWordPronunciation(word),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: selectedTheme.colors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: selectedTheme.colors.accent.withValues(alpha: 0.45),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      word,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Icon(
                      Icons.volume_up_rounded,
                      color: Colors.white.withValues(alpha: 0.78),
                      size: 13,
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  String _localizedClarityLabel(PronunciationReport report) {
    if (!_isTurkish) return report.clarityLabel;
    if (report.overallScore >= 90) return 'Harika';
    if (report.overallScore >= 75) return 'Net';
    if (report.overallScore >= 60) return 'Biraz calisma gerek';
    return 'Tekrar dene';
  }

  String _localizedSummary(PronunciationReport report) {
    if (!_isTurkish) return report.summary;
    final buffer = StringBuffer();
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
      final focus = report.missingWords.take(3).join(', ');
      return 'Bir kez daha oku ve şu kelimeleri daha net söyle: $focus.';
    }
    if (report.extraWords.isNotEmpty) {
      final focus = report.extraWords.take(3).join(', ');
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
    final wordsPerMinute = report.wordsPerMinute;
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
