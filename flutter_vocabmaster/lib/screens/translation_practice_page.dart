import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../widgets/animated_background.dart';
import '../widgets/modern_card.dart';
import '../widgets/report_content_button.dart';
import '../widgets/modern_background.dart';
import '../models/word.dart';
import '../providers/app_state_provider.dart';
import '../providers/learning_language_provider.dart';
import '../services/api_service.dart';
import '../services/ai_error_message_formatter.dart';
import '../services/chatbot_service.dart';
import '../services/ai_paywall_handler.dart';
import '../services/analytics_service.dart';
import '../services/xp_manager.dart';

/// Which of [practiceWords] a generated sentence is actually drilling.
///
/// In mixed mode the backend is asked to rotate one target word per sentence, so lining the
/// sentence index up with the word index would usually work — but "usually" is not a
/// property worth writing scheduling data on. If the model reorders, skips or merges a word,
/// index alignment silently credits the wrong word, and a wrong SRS grade is worse than no
/// grade: it moves a word the learner never saw.
///
/// Matching on the text is checkable against what the learner actually read. The suffix
/// allowance means an inflected form still counts ("recovered" for "recover"), and the
/// leading word boundary stops a short word matching inside a longer one ("cat" must not
/// match "concatenate").
///
/// Returns null when nothing matches and the round has more than one candidate — guessing
/// there would be worse than staying quiet.
@visibleForTesting
Word? wordDrilledBySentence(String sentence, List<Word> practiceWords) {
  final haystack = sentence.toLowerCase();
  for (final word in practiceWords) {
    final target = word.englishWord.trim().toLowerCase();
    if (target.isEmpty) continue;
    if (RegExp('\\b${RegExp.escape(target)}\\w*').hasMatch(haystack)) {
      return word;
    }
  }
  // A single-word round is unambiguous even if the model dropped the target entirely.
  return practiceWords.length == 1 ? practiceWords.first : null;
}

class TranslationPracticePage extends StatefulWidget {
  final Word? selectedWord;
  final List<String> selectedLevels;
  final List<String> selectedLengths;
  final String subMode; // 'select', 'manual', 'random'
  final ChatbotService? chatbotService;
  final ApiService? apiService;

  const TranslationPracticePage({
    super.key,
    this.selectedWord,
    this.selectedLevels = const ['B1'],
    this.selectedLengths = const ['medium'],
    this.subMode = 'select',
    this.chatbotService,
    this.apiService,
  });

  @override
  State<TranslationPracticePage> createState() =>
      _TranslationPracticePageState();
}

class _TranslationPracticePageState extends State<TranslationPracticePage> {
  late final ChatbotService _chatbotService;
  late final ApiService _apiService;
  final TextEditingController _wordController = TextEditingController();
  final Map<int, TextEditingController> _translationControllers = {};

  List<String> _generatedSentences = [];
  List<String> _aiTranslations = [];
  List<TranslationResult> _translationResults = [];
  bool _isGenerating = false;
  String _questionDirection = 'EN_TO_TR'; // EN_TO_TR, TR_TO_EN, MIXED
  String? _translationSetId;
  bool _translationCompleteXpAwarded = false;
  bool _translationPerfectXpAwarded = false;

  Word? _selectedWord;

  /// The vocabulary this round is drilling, with ids intact.
  ///
  /// Translating a sentence is production, not recognition — it is stronger evidence about
  /// memory than a flashcard grade. That evidence used to be spent entirely on XP and then
  /// discarded; the scheduler never heard about it. Holding the Word objects here is what
  /// lets each judgement reach the review log.
  List<Word> _practiceWords = [];

  Word? _wordForSentence(int index) {
    if (index < 0 || index >= _generatedSentences.length) return null;
    return wordDrilledBySentence(_generatedSentences[index], _practiceWords);
  }

  @override
  void initState() {
    super.initState();
    _chatbotService = widget.chatbotService ?? ChatbotService();
    _apiService = widget.apiService ?? ApiService();
    _selectedWord = widget.selectedWord;
    if (_selectedWord != null) {
      _wordController.text = _selectedWord!.englishWord;
    }
  }

  @override
  void dispose() {
    _wordController.dispose();
    for (var controller in _translationControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _generateSentences() async {
    String wordToUse = '';

    if (widget.subMode == 'random') {
      final words = await _apiService.getAllWords();
      if (!mounted) return;
      if (words.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(_t(context, 'Henüz kelime listeniz boş.',
                  'Your word list is empty.')),
              backgroundColor: Colors.red),
        );
        return;
      }
      words.shuffle();
      final selected = words.take(5).toList();
      // Keep the Word objects, not just their text. Their ids are what let a correct or
      // incorrect translation reach the review scheduler; joining them into a string here
      // is what previously threw that away.
      _practiceWords = selected;
      wordToUse = selected.map((w) => w.englishWord).join(', ');
    } else {
      _practiceWords = _selectedWord == null ? const [] : [_selectedWord!];
      wordToUse = _selectedWord?.englishWord ?? _wordController.text.trim();
      if (wordToUse.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(_t(context, 'Lütfen bir kelime seçin veya yazın',
                  'Please pick or type a word')),
              backgroundColor: Colors.red),
        );
        return;
      }
    }

    setState(() {
      _isGenerating = true;
      _generatedSentences = [];
      _aiTranslations = [];
      _translationResults = [];
    });

    try {
      final result = await _chatbotService.generateSentences(
        word: wordToUse,
        levels: widget.selectedLevels,
        lengths: widget.selectedLengths,
        fresh: true,
        direction: _backendDirection(_questionDirection),
      );

      if (!mounted) return;

      final sentences = List<String>.from(result['sentences'] ?? []);
      final translations = List<String>.from(result['translations'] ?? []);
      if (sentences.isNotEmpty) {
        unawaited(AnalyticsService.logFirstAiSentenceGenerated(
          source: 'translation_practice',
          direction: _questionDirection,
          sentenceCount: sentences.length,
        ));
      }

      // Dispose old controllers
      for (var controller in _translationControllers.values) {
        controller.dispose();
      }
      _translationControllers.clear();

      setState(() {
        _generatedSentences = sentences;
        _aiTranslations = translations;
        _translationSetId =
            'translation_${DateTime.now().microsecondsSinceEpoch}_${wordToUse.hashCode}';
        _translationCompleteXpAwarded = false;
        _translationPerfectXpAwarded = false;
        _translationResults = List.generate(
          sentences.length,
          (index) {
            final controller = TextEditingController();
            _translationControllers[index] = controller;

            // Determine direction for this sentence
            bool isReverse = false;
            if (_questionDirection == 'TR_TO_EN') {
              isReverse = true;
            } else if (_questionDirection == 'MIXED') {
              isReverse = Random().nextBool();
            }

            return TranslationResult(
              sentence: sentences[index],
              aiTranslation:
                  index < translations.length ? translations[index] : '',
              userTranslation: '',
              isCorrect: null,
              feedback: '',
              correctTranslation: '',
              isChecking: false,
              isReverse: isReverse,
            );
          },
        );
        _isGenerating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGenerating = false);
      if (await AiPaywallHandler.handleIfUpgradeRequired(context, e)) {
        return;
      }
      if (!mounted) return;
      final msg = e is ApiQuotaExceededException
          ? AiErrorMessageFormatter.forQuota(e)
          : 'Hata: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _checkTranslation(int index) async {
    final userTranslation = _translationControllers[index]?.text.trim() ?? '';
    if (userTranslation.isEmpty) return;

    setState(() {
      _translationResults[index].isChecking = true;
      _translationResults[index].userTranslation = userTranslation;
    });

    try {
      final result = _translationResults[index];
      final isReverse = result.isReverse;

      final resultData = await _chatbotService.checkTranslation(
        originalSentence:
            isReverse ? _aiTranslations[index] : _generatedSentences[index],
        userTranslation: userTranslation,
        direction: _backendDirection(isReverse ? 'TR_TO_EN' : 'EN_TO_TR'),
        referenceSentence: isReverse ? _generatedSentences[index] : null,
      );

      if (mounted) {
        setState(() {
          _translationResults[index].isCorrect =
              resultData['isCorrect'] as bool?;
          _translationResults[index].feedback = resultData['feedback'] ?? '';
          _translationResults[index].correctTranslation =
              resultData['correctTranslation'] ?? '';
          _translationResults[index].isChecking = false;
        });
        await _recordTranslationAsReview(index);
        await _maybeAwardTranslationXp();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _translationResults[index].isChecking = false);
      if (await AiPaywallHandler.handleIfUpgradeRequired(context, e)) {
        return;
      }
      if (!mounted) return;
      final msg = e is ApiQuotaExceededException
          ? AiErrorMessageFormatter.forQuota(e)
          : _t(context, 'Kontrol hatası: $e', 'Check failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    }
  }

  /// Feeds a checked translation into the review scheduler.
  ///
  /// The check already decides whether the learner produced the word correctly, which is a
  /// harder test than the flashcard screen sets: recognising a meaning is not the same as
  /// generating it in a sentence. Until now that decision only moved an XP counter, so a
  /// learner could translate a word correctly ten days running while the scheduler still
  /// believed it was due.
  ///
  /// Grades are deliberately conservative. Correct maps to 4 rather than 5 because nothing
  /// here measures hesitation, and 5 should mean effortless. Incorrect maps to 2, which the
  /// backend counts as a lapse (`quality < 3`) and which shortens the interval without
  /// resetting the word's whole history.
  Future<void> _recordTranslationAsReview(int index) async {
    final result = _translationResults[index];
    final isCorrect = result.isCorrect;
    if (isCorrect == null) return;

    // A word typed by hand that is not in the user's vocabulary has nothing to schedule.
    final word = _wordForSentence(index);
    if (word == null) return;

    try {
      await context.read<AppStateProvider>().submitWordReview(
            wordId: word.id,
            quality: isCorrect ? 4 : 2,
            source: 'translation_practice',
          );
    } catch (e) {
      // The learner has already seen their result; a scheduler write failing must not
      // surface as an error on top of it.
      debugPrint('Translation review not recorded for word ${word.id}: $e');
    }
  }

  Future<void> _maybeAwardTranslationXp() async {
    if (!mounted ||
        _translationSetId == null ||
        _translationResults.isEmpty ||
        _translationResults.any((result) => result.isCorrect == null)) {
      return;
    }

    final appState = context.read<AppStateProvider>();
    if (!_translationCompleteXpAwarded) {
      _translationCompleteXpAwarded = true;
      await appState.addXPForAction(
        XPActionTypes.translationComplete,
        source: 'Çeviri Pratiği',
        transactionId: '$_translationSetId:complete',
      );
    }

    final isPerfect =
        _translationResults.every((result) => result.isCorrect == true);
    if (isPerfect && !_translationPerfectXpAwarded) {
      _translationPerfectXpAwarded = true;
      await appState.addXPForAction(
        XPActionTypes.translationPerfect,
        source: 'Mükemmel Çeviri',
        transactionId: '$_translationSetId:perfect',
      );
    }
  }

  String _languageCode(String language) {
    return switch (language.trim().toLowerCase()) {
      'turkish' => 'TR',
      'spanish' => 'ES',
      'portuguese' => 'PT',
      'indonesian' => 'ID',
      'german' => 'DE',
      'french' => 'FR',
      'arabic' => 'AR',
      'english' => 'EN',
      _ => 'EN',
    };
  }

  String _languageLabel(BuildContext context, String language) {
    return switch (language) {
      'Turkish' => context.tr('language.turkish'),
      'English' => context.tr('language.english'),
      'Spanish' => context.tr('language.spanish'),
      'Portuguese' => context.tr('language.portuguese'),
      'Indonesian' => context.tr('language.indonesian'),
      'German' => context.tr('language.german'),
      'French' => context.tr('language.french'),
      _ => language,
    };
  }

  /// The screen already localized a couple of strings this way but left most
  /// of its copy hardcoded Turkish, so an English session read as a mix of the
  /// two ("Çeviri Yönü" sitting next to a "Mixed" chip).
  String _t(BuildContext context, String tr, String en) =>
      context.l10n.locale.languageCode == 'tr' ? tr : en;

  String _directionLabel(BuildContext context, String direction) {
    final profile = context.watch<LearningLanguageProvider>();
    final targetCode = _languageCode(profile.targetLanguage);
    final sourceCode = _languageCode(profile.sourceLanguage);
    return switch (direction) {
      'TR_TO_EN' || 'SOURCE_TO_TARGET' => '$sourceCode → $targetCode',
      'MIXED' => context.l10n.locale.languageCode == 'tr' ? 'Karışık' : 'Mixed',
      _ => '$targetCode → $sourceCode',
    };
  }

  String _backendDirection(String direction) {
    return switch (direction) {
      'TR_TO_EN' || 'SOURCE_TO_TARGET' => 'SOURCE_TO_TARGET',
      'MIXED' => 'MIXED',
      _ => 'TARGET_TO_SOURCE',
    };
  }

  String _translationInputHint(BuildContext context, bool isReverse) {
    final profile = context.watch<LearningLanguageProvider>();
    final targetLabel = _languageLabel(context, profile.targetLanguage);
    final sourceLabel = _languageLabel(context, profile.sourceLanguage);
    final language = isReverse ? targetLabel : sourceLabel;
    if (context.l10n.locale.languageCode == 'tr') {
      return '$language çevirinizi yazın...';
    }
    return 'Write your $language translation...';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const AnimatedBackground(isDark: true),
          SafeArea(
            child: Column(
              children: [
                // Header
                _buildHeader(),

                // Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Word Input or Display
                        _buildWordSection(),

                        const SizedBox(height: 20),

                        // Direction Selection
                        _buildDirectionSelector(),

                        const SizedBox(height: 20),

                        // Generate Button
                        _buildGenerateButton(),

                        const SizedBox(height: 24),

                        // Generated Sentences
                        if (_generatedSentences.isNotEmpty) ...[
                          _buildSentencesHeader(),
                          const SizedBox(height: 16),
                          ..._translationResults.asMap().entries.map(
                                (entry) =>
                                    _buildSentenceCard(entry.key, entry.value),
                              ),
                        ],

                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Text(
            _t(context, 'Çevirme Pratiği', 'Translation Practice'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWordSection() {
    if (widget.subMode == 'random') {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF8b5cf6).withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: const Color(0xFF8b5cf6).withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            const Icon(Icons.shuffle, color: Color(0xFF8b5cf6), size: 32),
            const SizedBox(height: 12),
            Text(
              _t(context, 'Karışık Mod', 'Mixed Mode'),
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              _t(context, 'Rastgele 5 kelime seçilecek',
                  '5 random words will be picked'),
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Kelime',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 8),
          if (_selectedWord != null)
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0ea5e9).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF0ea5e9)),
                  ),
                  child: Text(
                    _selectedWord!.englishWord,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '→ ${_selectedWord!.sourceMeaning}',
                  style: const TextStyle(color: Colors.white54),
                ),
              ],
            )
          else
            TextField(
              controller: _wordController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: _t(context, 'Kelime yazın...', 'Type a word...'),
                hintStyle:
                    TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.1),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDirectionSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(context, 'Çeviri Yönü', 'Translation Direction'),
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildDirectionChip(
                'EN_TO_TR',
                _directionLabel(context, 'EN_TO_TR'),
                Icons.arrow_forward,
              ),
              const SizedBox(width: 8),
              _buildDirectionChip(
                'TR_TO_EN',
                _directionLabel(context, 'TR_TO_EN'),
                Icons.arrow_back,
              ),
              const SizedBox(width: 8),
              _buildDirectionChip(
                'MIXED',
                _directionLabel(context, 'MIXED'),
                Icons.shuffle,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDirectionChip(String value, String label, IconData icon) {
    final isSelected = _questionDirection == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _questionDirection = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF0ea5e9).withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? const Color(0xFF0ea5e9) : Colors.transparent,
            ),
          ),
          child: Column(
            children: [
              Icon(icon,
                  color: isSelected ? const Color(0xFF0ea5e9) : Colors.white54,
                  size: 20),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white54,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGenerateButton() {
    return GestureDetector(
      key: const ValueKey('translation-generate-button'),
      onTap: _isGenerating ? null : _generateSentences,
      child: ModernCard(
        variant: BackgroundVariant.accent,
        borderRadius: BorderRadius.circular(16),
        showGlow: true,
        showBorder: false,
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: _isGenerating
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _t(context, 'Owen cümle üretiyor...',
                        'Owen is writing sentences...'),
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.auto_awesome, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    _t(context, 'Cümle Üret', 'Generate Sentences'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSentencesHeader() {
    return Row(
      children: [
        const Icon(Icons.format_list_numbered, color: Colors.white70, size: 20),
        const SizedBox(width: 8),
        Text(
          _t(context, 'Cümleler (${_generatedSentences.length})',
              'Sentences (${_generatedSentences.length})'),
          style: const TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildSentenceCard(int index, TranslationResult result) {
    final isReverse = result.isReverse;
    final displaySentence = isReverse ? result.aiTranslation : result.sentence;
    final direction =
        _directionLabel(context, isReverse ? 'TR_TO_EN' : 'EN_TO_TR');

    Color? resultColor;
    if (result.isCorrect == true) {
      resultColor = const Color(0xFF10b981);
    } else if (result.isCorrect == false) {
      resultColor = const Color(0xFFef4444);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: resultColor?.withValues(alpha: 0.5) ??
              Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFF8b5cf6).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                      color: Color(0xFF8b5cf6), fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF0ea5e9).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  direction,
                  style:
                      const TextStyle(color: Color(0xFF0ea5e9), fontSize: 11),
                ),
              ),
              const Spacer(),
              // Sits on the generated sentence itself. This is the surface where bad output
              // reaches a learner as if it were teaching material, and where the
              // instrumentation is blindest: the request returns 200 whether the sentence is
              // good English or not.
              ReportContentButton(
                content: _generatedSentences[index],
                surface: 'translation_practice',
                contentKind: 'practice_sentence',
                extra: {
                  'targetWord': _wordForSentence(index)?.englishWord ?? '',
                  'direction': direction,
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Sentence
          Text(
            displaySentence,
            style:
                const TextStyle(color: Colors.white, fontSize: 15, height: 1.5),
          ),
          const SizedBox(height: 16),

          // Translation Input
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: ValueKey('translation-input-$index'),
                  controller: _translationControllers[index],
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: _translationInputHint(context, isReverse),
                    hintStyle:
                        TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.1),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                  onSubmitted: (_) => _checkTranslation(index),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0ea5e9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  key: ValueKey('translation-check-$index'),
                  onPressed:
                      result.isChecking ? null : () => _checkTranslation(index),
                  icon: result.isChecking
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check, color: Colors.white),
                ),
              ),
            ],
          ),

          // Result
          if (result.isCorrect != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: resultColor!.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: resultColor.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        result.isCorrect! ? Icons.check_circle : Icons.cancel,
                        color: resultColor,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        result.isCorrect!
                            ? _t(context, 'Doğru!', 'Correct!')
                            : _t(context, 'Yanlış', 'Incorrect'),
                        style: TextStyle(
                          color: resultColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  if (result.feedback.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      result.feedback,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                  if (result.correctTranslation.isNotEmpty &&
                      !result.isCorrect!) ...[
                    const SizedBox(height: 8),
                    Text(
                      _t(context,
                          'Doğru çeviri: ${result.correctTranslation}',
                          'Correct translation: ${result.correctTranslation}'),
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class TranslationResult {
  String sentence;
  String aiTranslation;
  String userTranslation;
  bool? isCorrect;
  String feedback;
  String correctTranslation;
  bool isChecking;
  bool isReverse;

  TranslationResult({
    required this.sentence,
    this.aiTranslation = '',
    required this.userTranslation,
    this.isCorrect,
    required this.feedback,
    required this.correctTranslation,
    required this.isChecking,
    this.isReverse = false,
  });
}
