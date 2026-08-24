import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/word.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/learning_language_provider.dart';
import '../../services/ai_error_message_formatter.dart';
import '../../services/ai_paywall_handler.dart';
import '../../services/analytics_service.dart';
import '../../services/api_service.dart';
import '../../services/chatbot_service.dart';
import '../../services/xp_manager.dart';
import '../../widgets/report_content_button.dart';
import '../theme/nf_tokens.dart';
import '../widgets/nf_button.dart';
import '../widgets/nf_card.dart';
import '../widgets/nf_chip.dart';

/// Which of [practiceWords] a generated sentence is actually drilling.
///
/// Same contract as `wordDrilledBySentence` in the legacy
/// `translation_practice_page.dart` (which stays untouched): match on the text
/// the learner actually read rather than trusting index alignment, allow an
/// inflected suffix ("recovered" for "recover"), require a leading word
/// boundary ("cat" must not match "concatenate"), and stay quiet when nothing
/// matches in a multi-word round — a wrong SRS grade is worse than no grade.
@visibleForTesting
Word? nfWordDrilledBySentence(String sentence, List<Word> practiceWords) {
  final String haystack = sentence.toLowerCase();
  for (final Word word in practiceWords) {
    final String target = word.englishWord.trim().toLowerCase();
    if (target.isEmpty) continue;
    if (RegExp('\\b${RegExp.escape(target)}\\w*').hasMatch(haystack)) {
      return word;
    }
  }
  // A single-word round is unambiguous even if the model dropped the target.
  return practiceWords.length == 1 ? practiceWords.first : null;
}

/// Translation practice in the new frontend's paint.
///
/// Behaviour is a replica of `lib/screens/translation_practice_page.dart`:
/// generation through [ChatbotService], per-sentence checking with a nullable
/// verdict (null = "could not check", never a silent pass), a conservative SRS
/// write on every graded result (4 for correct, 2 for a lapse), XP for a
/// completed / perfect set, the paywall and quota handling, and the
/// report-content affordance on every generated sentence.
///
/// Presentation differs in one deliberate way: the check's verdict lands in a
/// bottom banner in the semantic colour — a green or red band carrying the
/// feedback and, on a miss, the correct answer — instead of an inline result
/// card growing under every sentence.
class NfTranslationPracticePage extends StatefulWidget {
  const NfTranslationPracticePage({
    super.key,
    this.selectedWord,
    this.selectedLevels = const <String>['B1'],
    this.selectedLengths = const <String>['medium'],
    this.subMode = 'select',
    this.chatbotService,
    this.apiService,
  });

  /// Pre-picked word ('select' mode). Null in 'manual' mode, where the learner
  /// types one, and ignored in 'random' mode.
  final Word? selectedWord;

  final List<String> selectedLevels;
  final List<String> selectedLengths;

  /// 'select', 'manual' or 'random' — the same ids the legacy screen takes, so
  /// whatever setup step launches this can hand its value straight through.
  final String subMode;

  /// Injectable for tests.
  final ChatbotService? chatbotService;
  final ApiService? apiService;

  @override
  State<NfTranslationPracticePage> createState() =>
      _NfTranslationPracticePageState();
}

/// One sentence's round-trip. Field-for-field the legacy `TranslationResult`.
class _NfSentenceRound {
  _NfSentenceRound({
    required this.sentence,
    this.aiTranslation = '',
    this.isReverse = false,
  });

  final String sentence;
  final String aiTranslation;

  /// The learner translates *into* the target language for this sentence.
  final bool isReverse;

  String userTranslation = '';

  /// Null until checked — and null after a check whose response carried no
  /// verdict. A missing verdict is not a pass; see [checkFailed].
  bool? isCorrect;

  /// The check ran but came back without a verdict, so nothing was graded and
  /// nothing reached the scheduler. The legacy backend used to invent a
  /// verdict here and defaulted to "correct"; being visibly ungraded is the
  /// honest replacement.
  bool checkFailed = false;

  String feedback = '';
  String correctTranslation = '';
  bool isChecking = false;
}

/// What the bottom banner is saying.
enum _NfBannerKind { correct, wrong, neutral }

class _NfBannerData {
  const _NfBannerData({
    required this.kind,
    required this.title,
    this.feedback = '',
    this.correctTranslation = '',
  });

  final _NfBannerKind kind;
  final String title;
  final String feedback;
  final String correctTranslation;
}

class _NfTranslationPracticePageState extends State<NfTranslationPracticePage> {
  late final ChatbotService _chatbotService;
  late final ApiService _apiService;
  final TextEditingController _wordController = TextEditingController();
  final Map<int, TextEditingController> _answerControllers =
      <int, TextEditingController>{};

  List<_NfSentenceRound> _rounds = <_NfSentenceRound>[];
  bool _isGenerating = false;
  String _questionDirection = 'EN_TO_TR'; // EN_TO_TR, TR_TO_EN, MIXED
  String? _translationSetId;
  bool _completeXpAwarded = false;
  bool _perfectXpAwarded = false;

  Word? _selectedWord;

  /// The vocabulary this round is drilling, ids intact, so each judgement can
  /// reach the review log. Same reasoning as the legacy screen: a translation
  /// is production evidence, stronger than a flashcard grade, and it must not
  /// be spent on XP alone.
  List<Word> _practiceWords = <Word>[];

  _NfBannerData? _banner;

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
    for (final TextEditingController controller in _answerControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Copy. The legacy screen localizes TR/EN through the same two-string helper;
  // DE falls back to English there and therefore here too, so the two screens
  // read identically in every locale.
  // ---------------------------------------------------------------------------

  String _t(String tr, String en) =>
      context.l10n.locale.languageCode == 'tr' ? tr : en;

  Word? _wordForSentence(int index) {
    if (index < 0 || index >= _rounds.length) return null;
    return nfWordDrilledBySentence(_rounds[index].sentence, _practiceWords);
  }

  // ---------------------------------------------------------------------------
  // Generation
  // ---------------------------------------------------------------------------

  Future<void> _generateSentences() async {
    String wordToUse = '';

    if (widget.subMode == 'random') {
      final List<Word> words = await _apiService.getAllWords();
      if (!mounted) return;
      if (words.isEmpty) {
        _showError(
            _t('Henüz kelime listeniz boş.', 'Your word list is empty.'));
        return;
      }
      words.shuffle();
      final List<Word> selected = words.take(5).toList();
      // Keep the Word objects, not just their text — their ids are what let a
      // graded translation reach the review scheduler.
      _practiceWords = selected;
      wordToUse = selected.map((Word w) => w.englishWord).join(', ');
    } else {
      _practiceWords =
          _selectedWord == null ? const <Word>[] : <Word>[_selectedWord!];
      wordToUse = _selectedWord?.englishWord ?? _wordController.text.trim();
      if (wordToUse.isEmpty) {
        _showError(_t('Lütfen bir kelime seçin veya yazın',
            'Please pick or type a word'));
        return;
      }
    }

    setState(() {
      _isGenerating = true;
      _rounds = <_NfSentenceRound>[];
      _banner = null;
    });

    try {
      final Map<String, dynamic> result =
          await _chatbotService.generateSentences(
        word: wordToUse,
        levels: widget.selectedLevels,
        lengths: widget.selectedLengths,
        fresh: true,
        direction: _backendDirection(_questionDirection),
      );

      if (!mounted) return;

      final List<String> sentences =
          List<String>.from(result['sentences'] ?? <String>[]);
      final List<String> translations =
          List<String>.from(result['translations'] ?? <String>[]);
      if (sentences.isNotEmpty) {
        unawaited(AnalyticsService.logFirstAiSentenceGenerated(
          source: 'translation_practice',
          direction: _questionDirection,
          sentenceCount: sentences.length,
        ));
      }

      for (final TextEditingController controller
          in _answerControllers.values) {
        controller.dispose();
      }
      _answerControllers.clear();

      setState(() {
        _translationSetId =
            'translation_${DateTime.now().microsecondsSinceEpoch}_${wordToUse.hashCode}';
        _completeXpAwarded = false;
        _perfectXpAwarded = false;
        _rounds = List<_NfSentenceRound>.generate(sentences.length, (int i) {
          _answerControllers[i] = TextEditingController();

          bool isReverse = false;
          if (_questionDirection == 'TR_TO_EN') {
            isReverse = true;
          } else if (_questionDirection == 'MIXED') {
            isReverse = Random().nextBool();
          }

          return _NfSentenceRound(
            sentence: sentences[i],
            aiTranslation: i < translations.length ? translations[i] : '',
            isReverse: isReverse,
          );
        });
        _isGenerating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGenerating = false);
      if (await AiPaywallHandler.handleIfUpgradeRequired(context, e)) {
        return;
      }
      if (!mounted) return;
      final String msg = e is ApiQuotaExceededException
          ? AiErrorMessageFormatter.forQuota(e)
          : 'Hata: $e';
      _showError(msg);
    }
  }

  // ---------------------------------------------------------------------------
  // Checking
  // ---------------------------------------------------------------------------

  Future<void> _checkTranslation(int index) async {
    final String userTranslation =
        _answerControllers[index]?.text.trim() ?? '';
    if (userTranslation.isEmpty) return;

    setState(() {
      _rounds[index].isChecking = true;
      _rounds[index].userTranslation = userTranslation;
    });

    try {
      final _NfSentenceRound round = _rounds[index];
      final bool isReverse = round.isReverse;

      final Map<String, dynamic> resultData =
          await _chatbotService.checkTranslation(
        originalSentence: isReverse ? round.aiTranslation : round.sentence,
        userTranslation: userTranslation,
        direction: _backendDirection(isReverse ? 'TR_TO_EN' : 'EN_TO_TR'),
        referenceSentence: isReverse ? round.sentence : null,
      );

      if (mounted) {
        setState(() {
          round.isCorrect = resultData['isCorrect'] as bool?;
          // A response that carried no verdict is not a pass.
          round.checkFailed = resultData['isCorrect'] == null;
          round.feedback = (resultData['feedback'] ?? '') as String;
          round.correctTranslation =
              (resultData['correctTranslation'] ?? '') as String;
          round.isChecking = false;
          _banner = _bannerFor(round);
        });
        await _recordTranslationAsReview(index);
        await _maybeAwardTranslationXp();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _rounds[index].isChecking = false);
      if (await AiPaywallHandler.handleIfUpgradeRequired(context, e)) {
        return;
      }
      if (!mounted) return;
      final String msg = e is ApiQuotaExceededException
          ? AiErrorMessageFormatter.forQuota(e)
          : _t('Kontrol hatası: $e', 'Check failed: $e');
      _showError(msg);
    }
  }

  _NfBannerData _bannerFor(_NfSentenceRound round) {
    if (round.isCorrect == true) {
      return _NfBannerData(
        kind: _NfBannerKind.correct,
        title: _t('Doğru!', 'Correct!'),
        feedback: round.feedback,
      );
    }
    if (round.isCorrect == false) {
      return _NfBannerData(
        kind: _NfBannerKind.wrong,
        title: _t('Yanlış', 'Incorrect'),
        feedback: round.feedback,
        correctTranslation: round.correctTranslation,
      );
    }
    // The verdict could not be read: nothing is graded, nothing reaches the
    // scheduler, the learner's own answer stays in the field and they can ask
    // again. Neutral colour on purpose — this is not a result.
    return _NfBannerData(
      kind: _NfBannerKind.neutral,
      title: _t('Kontrol edilemedi. Tekrar dene.',
          'Could not check this one. Try again.'),
    );
  }

  /// Feeds a checked translation into the review scheduler.
  ///
  /// Grades are deliberately conservative, exactly as on the legacy screen:
  /// correct maps to 4 rather than 5 because nothing here measures hesitation,
  /// and incorrect maps to 2, which the backend counts as a lapse without
  /// resetting the word's history. An unmatched sentence writes nothing.
  Future<void> _recordTranslationAsReview(int index) async {
    final _NfSentenceRound round = _rounds[index];
    final bool? isCorrect = round.isCorrect;
    if (isCorrect == null) return;

    final Word? word = _wordForSentence(index);
    if (word == null) return;

    try {
      await context.read<AppStateProvider>().submitWordReview(
            wordId: word.id,
            quality: isCorrect ? 4 : 2,
            source: 'translation_practice',
          );
    } catch (e) {
      // The learner has already seen their result; a scheduler write failing
      // must not surface as an error on top of it.
      debugPrint('Translation review not recorded for word ${word.id}: $e');
    }
  }

  Future<void> _maybeAwardTranslationXp() async {
    if (!mounted ||
        _translationSetId == null ||
        _rounds.isEmpty ||
        _rounds.any((_NfSentenceRound round) => round.isCorrect == null)) {
      return;
    }

    final AppStateProvider appState = context.read<AppStateProvider>();
    if (!_completeXpAwarded) {
      _completeXpAwarded = true;
      await appState.addXPForAction(
        XPActionTypes.translationComplete,
        source: 'Çeviri Pratiği',
        transactionId: '$_translationSetId:complete',
      );
    }

    final bool isPerfect =
        _rounds.every((_NfSentenceRound round) => round.isCorrect == true);
    if (isPerfect && !_perfectXpAwarded) {
      _perfectXpAwarded = true;
      await appState.addXPForAction(
        XPActionTypes.translationPerfect,
        source: 'Mükemmel Çeviri',
        transactionId: '$_translationSetId:perfect',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Direction / language labels — identical mappings to the legacy screen.
  // ---------------------------------------------------------------------------

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

  String _languageLabel(String language) {
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

  String _directionLabel(String direction) {
    final LearningLanguageProvider profile =
        context.watch<LearningLanguageProvider>();
    final String targetCode = _languageCode(profile.targetLanguage);
    final String sourceCode = _languageCode(profile.sourceLanguage);
    return switch (direction) {
      'TR_TO_EN' || 'SOURCE_TO_TARGET' => '$sourceCode → $targetCode',
      'MIXED' => _t('Karışık', 'Mixed'),
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

  String _translationInputHint(bool isReverse) {
    final LearningLanguageProvider profile =
        context.watch<LearningLanguageProvider>();
    final String targetLabel = _languageLabel(profile.targetLanguage);
    final String sourceLabel = _languageLabel(profile.sourceLanguage);
    final String language = isReverse ? targetLabel : sourceLabel;
    if (context.l10n.locale.languageCode == 'tr') {
      return '$language çevirinizi yazın...';
    }
    return 'Write your $language translation...';
  }

  void _showError(String text) {
    final NfTokens t = NfTokens.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          text,
          style: NfTokens.body(size: NfFont.s135, color: t.primaryInk),
        ),
        backgroundColor: t.wrong,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    return Scaffold(
      backgroundColor: t.ground,
      body: SafeArea(
        // The banner draws its own bottom inset, so it can sit flush with the
        // screen edge like a band rather than floating above it.
        bottom: false,
        child: Column(
          children: <Widget>[
            _NfPageHeader(
              title: context.tr('practice.translation.title'),
              tokens: t,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  NfSpace.s16,
                  NfSpace.s8,
                  NfSpace.s16,
                  NfSpace.s26 +
                      (_banner == null
                          ? MediaQuery.paddingOf(context).bottom
                          : 0),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _buildWordSection(t),
                    const SizedBox(height: NfSpace.s14),
                    _buildDirectionSelector(t),
                    const SizedBox(height: NfSpace.s16),
                    NfPrimaryButton(
                      key: const ValueKey('translation-generate-button'),
                      label: _t('Cümle Üret', 'Generate Sentences'),
                      icon: Icons.auto_awesome,
                      busy: _isGenerating,
                      onPressed: _isGenerating ? null : _generateSentences,
                    ),
                    if (_isGenerating) ...<Widget>[
                      const SizedBox(height: NfSpace.s10),
                      Text(
                        _t('Owen cümle üretiyor...',
                            'Owen is writing sentences...'),
                        textAlign: TextAlign.center,
                        style: NfTokens.body(
                            size: NfFont.s125, color: t.inkMuted),
                      ),
                    ],
                    if (_rounds.isNotEmpty) ...<Widget>[
                      const SizedBox(height: NfSpace.s22),
                      Text(
                        _t('Cümleler (${_rounds.length})',
                            'Sentences (${_rounds.length})'),
                        style:
                            NfTokens.display(size: NfFont.s18, color: t.ink),
                      ),
                      const SizedBox(height: NfSpace.s12),
                      for (int i = 0; i < _rounds.length; i++) ...<Widget>[
                        _buildSentenceCard(t, i, _rounds[i]),
                        if (i < _rounds.length - 1)
                          const SizedBox(height: NfSpace.s12),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            _NfResultBanner(
              data: _banner,
              onDismiss: () => setState(() => _banner = null),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWordSection(NfTokens t) {
    if (widget.subMode == 'random') {
      return NfCard(
        child: Row(
          children: <Widget>[
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: t.primarySoft,
                borderRadius: NfRadius.iconTileAll,
              ),
              child: Icon(Icons.shuffle_rounded,
                  size: 23, color: t.primaryText),
            ),
            const SizedBox(width: NfSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _t('Karışık Mod', 'Mixed Mode'),
                    style: NfTokens.display(size: NfFont.s16, color: t.ink),
                  ),
                  const SizedBox(height: NfSpace.s4),
                  Text(
                    _t('Rastgele 5 kelime seçilecek',
                        '5 random words will be picked'),
                    style:
                        NfTokens.body(size: NfFont.s125, color: t.inkMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return NfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _t('Kelime', 'Word'),
            style: NfTokens.body(
              size: NfFont.s125,
              weight: NfTokens.bodyEmphasisWeight,
              color: t.inkMuted,
            ),
          ),
          const SizedBox(height: NfSpace.s8),
          if (_selectedWord != null)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: NfSpace.s8,
              runSpacing: NfSpace.s6,
              children: <Widget>[
                NfChip(
                  label: _selectedWord!.englishWord,
                  variant: NfChipVariant.selected,
                ),
                Text(
                  '→ ${_selectedWord!.sourceMeaning}',
                  style: NfTokens.body(size: NfFont.s135, color: t.inkMuted),
                ),
              ],
            )
          else
            _NfTextField(
              controller: _wordController,
              hint: _t('Kelime yazın...', 'Type a word...'),
              tokens: t,
            ),
        ],
      ),
    );
  }

  Widget _buildDirectionSelector(NfTokens t) {
    return NfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _t('Çeviri Yönü', 'Translation Direction'),
            style: NfTokens.body(
              size: NfFont.s125,
              weight: NfTokens.bodyEmphasisWeight,
              color: t.inkMuted,
            ),
          ),
          const SizedBox(height: NfSpace.s10),
          Row(
            children: <Widget>[
              _buildDirectionTile(t, 'EN_TO_TR', Icons.arrow_forward_rounded),
              const SizedBox(width: NfSpace.s8),
              _buildDirectionTile(t, 'TR_TO_EN', Icons.arrow_back_rounded),
              const SizedBox(width: NfSpace.s8),
              _buildDirectionTile(t, 'MIXED', Icons.shuffle_rounded),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDirectionTile(NfTokens t, String value, IconData icon) {
    final bool isSelected = _questionDirection == value;
    return Expanded(
      child: NfCard(
        padding: const EdgeInsets.symmetric(
            vertical: NfSpace.s12, horizontal: NfSpace.s4),
        borderRadius: NfRadius.tileAll,
        backgroundColor: isSelected ? t.primarySoft : t.raised,
        borderColor: isSelected ? t.primary : t.border,
        onTap: () => setState(() => _questionDirection = value),
        child: Column(
          children: <Widget>[
            Icon(icon,
                size: 20, color: isSelected ? t.primaryText : t.inkMuted),
            const SizedBox(height: NfSpace.s4),
            Text(
              _directionLabel(value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: NfTokens.body(
                size: NfFont.s115,
                weight: NfTokens.bodyEmphasisWeight,
                color: isSelected ? t.primaryText : t.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSentenceCard(NfTokens t, int index, _NfSentenceRound round) {
    final bool isReverse = round.isReverse;
    final String displaySentence =
        isReverse ? round.aiTranslation : round.sentence;
    final String direction =
        _directionLabel(isReverse ? 'TR_TO_EN' : 'EN_TO_TR');

    // The graded state stays visible on the card as a coloured border and a
    // dense chip, so the learner can see at a glance which sentences are done
    // while the details live in the bottom banner.
    Color? resultBorder;
    if (round.isCorrect == true) {
      resultBorder = t.correct;
    } else if (round.isCorrect == false) {
      resultBorder = t.wrong;
    }

    return NfCard(
      borderColor: resultBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.primarySoft,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${index + 1}',
                  style: NfTokens.display(
                      size: NfFont.s135, color: t.primaryText),
                ),
              ),
              const SizedBox(width: NfSpace.s8),
              NfChip(label: direction, dense: true),
              if (round.isCorrect != null) ...<Widget>[
                const SizedBox(width: NfSpace.s6),
                NfChip(
                  label: round.isCorrect!
                      ? _t('Doğru', 'Correct')
                      : _t('Yanlış', 'Wrong'),
                  dense: true,
                  icon: round.isCorrect!
                      ? Icons.check_rounded
                      : Icons.close_rounded,
                  variant: round.isCorrect!
                      ? NfChipVariant.correct
                      : NfChipVariant.wrong,
                ),
              ],
              const Spacer(),
              // Sits on the generated sentence itself — the surface where bad
              // model output reaches a learner as teaching material and where
              // the instrumentation is blindest (200 either way).
              ReportContentButton(
                content: round.sentence,
                surface: 'translation_practice',
                contentKind: 'practice_sentence',
                extra: <String, dynamic>{
                  'targetWord': _wordForSentence(index)?.englishWord ?? '',
                  'direction': direction,
                },
              ),
            ],
          ),
          const SizedBox(height: NfSpace.s12),
          Text(
            displaySentence,
            style: NfTokens.body(size: NfFont.s15, color: t.ink, height: 1.5),
          ),
          const SizedBox(height: NfSpace.s12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: _NfTextField(
                  key: ValueKey<String>('translation-input-$index'),
                  controller: _answerControllers[index],
                  hint: _translationInputHint(isReverse),
                  tokens: t,
                  onSubmitted: (_) => _checkTranslation(index),
                ),
              ),
              const SizedBox(width: NfSpace.s10),
              _NfCheckButton(
                key: ValueKey<String>('translation-check-$index'),
                tokens: t,
                busy: round.isChecking,
                semanticLabel: _t('Kontrol et', 'Check'),
                onPressed:
                    round.isChecking ? null : () => _checkTranslation(index),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Pieces
// -----------------------------------------------------------------------------

/// Back arrow + title, same shape as the header the other pushed nf pages use.
class _NfPageHeader extends StatelessWidget {
  const _NfPageHeader({
    required this.title,
    required this.tokens,
    required this.onBack,
  });

  final String title;
  final NfTokens tokens;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NfSpace.s12,
        NfSpace.s8,
        NfSpace.s16,
        NfSpace.s8,
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: onBack,
            iconSize: NfFont.s22,
            color: tokens.ink,
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          ),
          const SizedBox(width: NfSpace.s4),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NfTokens.display(size: NfFont.s20, color: tokens.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// The frontend's text field: raised fill, the signature 2px border, Nunito.
class _NfTextField extends StatelessWidget {
  const _NfTextField({
    super.key,
    required this.hint,
    required this.tokens,
    this.controller,
    this.onSubmitted,
  });

  final TextEditingController? controller;
  final String hint;
  final NfTokens tokens;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = tokens;
    final OutlineInputBorder border = OutlineInputBorder(
      borderRadius: NfRadius.tileAll,
      borderSide: t.side,
    );
    return TextField(
      controller: controller,
      onSubmitted: onSubmitted,
      style: NfTokens.body(size: NfFont.s145, color: t.ink),
      cursorColor: t.primary,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: NfTokens.body(size: NfFont.s145, color: t.inkFaint),
        filled: true,
        fillColor: t.raised,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: NfSpace.s14, vertical: NfSpace.s12),
        enabledBorder: border,
        border: border,
        focusedBorder: OutlineInputBorder(
          borderRadius: NfRadius.tileAll,
          borderSide: t.sideOf(t.primary),
        ),
      ),
    );
  }
}

/// Square 46px pushable check control next to the answer field.
class _NfCheckButton extends StatelessWidget {
  const _NfCheckButton({
    super.key,
    required this.tokens,
    required this.busy,
    required this.semanticLabel,
    this.onPressed,
  });

  final NfTokens tokens;
  final bool busy;
  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = tokens;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticLabel,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          width: NfSize.buttonSecondary,
          height: NfSize.buttonSecondary,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: t.primary,
            borderRadius: NfRadius.tileAll,
            boxShadow: NfTokens.solidShadow(t.primaryShadow),
          ),
          child: busy
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: NfStroke.iconHeavy,
                    valueColor: AlwaysStoppedAnimation<Color>(t.primaryInk),
                  ),
                )
              : Icon(Icons.check_rounded, color: t.primaryInk),
        ),
      ),
    );
  }
}

/// The bottom band a check's verdict lands in: green for correct, red for
/// wrong (with the correct answer), neutral when the check came back without a
/// verdict. Full-width and flush with the bottom edge, TrendSession-style,
/// instead of an inline card under every sentence.
class _NfResultBanner extends StatelessWidget {
  const _NfResultBanner({required this.data, required this.onDismiss});

  final _NfBannerData? data;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final _NfBannerData? banner = data;

    return AnimatedSize(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: banner == null
          ? const SizedBox(width: double.infinity)
          : _band(context, t, banner),
    );
  }

  Widget _band(BuildContext context, NfTokens t, _NfBannerData banner) {
    final (Color background, Color accent, IconData icon) = switch (
        banner.kind) {
      _NfBannerKind.correct => (
          t.correctSoft,
          t.correct,
          Icons.check_circle_rounded
        ),
      _NfBannerKind.wrong => (t.wrongSoft, t.wrong, Icons.cancel_rounded),
      _NfBannerKind.neutral => (t.raised, t.inkMuted, Icons.help_outline),
    };

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: background,
        border: Border(top: BorderSide(color: accent, width: NfStroke.border)),
      ),
      padding: EdgeInsets.fromLTRB(
        NfSpace.s16,
        NfSpace.s14,
        NfSpace.s10,
        NfSpace.s14 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: accent, size: 24),
          const SizedBox(width: NfSpace.s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  banner.title,
                  style: NfTokens.display(size: NfFont.s16, color: accent),
                ),
                if (banner.feedback.isNotEmpty) ...<Widget>[
                  const SizedBox(height: NfSpace.s4),
                  Text(
                    banner.feedback,
                    style: NfTokens.body(size: NfFont.s13, color: t.ink),
                  ),
                ],
                if (banner.correctTranslation.isNotEmpty &&
                    banner.kind == _NfBannerKind.wrong) ...<Widget>[
                  const SizedBox(height: NfSpace.s4),
                  Text(
                    banner.correctTranslation,
                    style: NfTokens.body(
                      size: NfFont.s13,
                      weight: NfTokens.bodyEmphasisWeight,
                      color: t.ink,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            color: accent,
            iconSize: 20,
            icon: const Icon(Icons.close_rounded),
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          ),
        ],
      ),
    );
  }
}
