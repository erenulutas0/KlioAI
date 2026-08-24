import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/app_state_provider.dart';
import '../../services/ai_error_message_formatter.dart';
import '../../services/ai_paywall_handler.dart';
import '../../services/api_service.dart';
import '../../services/daily_practice_progress_service.dart';
import '../../services/groq_service.dart';
import '../../services/learning_language_service.dart';
import '../../services/xp_manager.dart';
import '../../widgets/feedback_prompt_sheet.dart';
import '../../widgets/report_content_button.dart';
import '../theme/nf_tokens.dart';
import '../widgets/nf_button.dart';
import '../widgets/nf_card.dart';
import '../widgets/nf_chip.dart';

/// Reading practice in the new frontend's paint.
///
/// Behaviour is the union of two legacy screens: the level picker that lived on
/// `PracticePage._buildReadingTab` (A1–C2 chips, one daily test per level,
/// completed checkmarks) and the test itself from `ReadingPracticePage`
/// (passage + comprehension questions graded by position letter, evidence
/// quote, daily completion, XP). Folding the picker into this screen means
/// switching level is one tap instead of a pop-and-repush, and the checkmarks
/// are visible while the learner reads.
///
/// The passage gets the reading-first treatment: it sits directly on the
/// ground with a generous line height and no card chrome — on a screen whose
/// whole job is reading, the text is the interface.
class NfReadingPracticePage extends StatefulWidget {
  const NfReadingPracticePage({super.key, this.initialLevel});

  /// Starting CEFR level. Defaults to the profile level, same as the legacy
  /// picker, so the selector does not reset to B1 every session.
  final String? initialLevel;

  @override
  State<NfReadingPracticePage> createState() => _NfReadingPracticePageState();
}

class _NfReadingPracticePageState extends State<NfReadingPracticePage> {
  static const List<String> _levels = DailyPracticeProgressService.cefrLevels;

  final DailyPracticeProgressService _progressService =
      DailyPracticeProgressService();

  late String _level = _resolveInitialLevel();

  bool _isLoading = true;
  String? _errorMessage;

  String _title = '';
  String _passage = '';
  List<NfReadingQuestion> _questions = <NfReadingQuestion>[];
  Map<int, String?> _selectedAnswers = <int, String?>{};
  Map<int, bool?> _checkedAnswers = <int, bool?>{};
  bool _showResults = false;
  int _score = 0;
  bool _hasCompletedToday = false;
  Map<String, bool> _completedLevels = <String, bool>{};

  /// "New passage" counter: 0 = the shared daily passage; each increment asks
  /// the backend for a different topic variant of the day's theme. Without it
  /// the page would show the same text all day, since the daily passage is
  /// served identically to every user.
  int _variant = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPassage());
    unawaited(_loadSavedProgress());
    unawaited(_loadCompletedLevels());
  }

  String _resolveInitialLevel() {
    final String candidate =
        widget.initialLevel ?? LearningLanguageService.englishLevel;
    return _levels.contains(candidate) ? candidate : 'B1';
  }

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  Future<void> _loadPassage() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      // Same split as the legacy screen: the first load goes through the daily
      // reading endpoint (shared, cached per level), fresh variants go through
      // the generator with a variant seed.
      final Map<String, dynamic> result =
          await GroqService.generateReadingPassage(_level);
      if (mounted) {
        _applyPassageResult(result);
      }
    } catch (e) {
      await _handleLoadError(e);
    }
  }

  Future<void> _loadFreshPassage() async {
    _variant += 1;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final Map<String, dynamic> result = await ApiService()
          .chatbotGenerateReadingPassage(level: _level, variant: _variant);
      if (mounted) {
        _applyPassageResult(result);
      }
    } catch (e) {
      await _handleLoadError(e);
    }
  }

  Future<void> _handleLoadError(Object e) async {
    if (!mounted) {
      return;
    }
    // Looked up before the paywall await: after it the context may have moved
    // on, and a message template is cheap to hold onto.
    final String loadFailed = context.tr('practice.reading.loadFailed');
    if (await AiPaywallHandler.handleIfUpgradeRequired(context, e)) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = AiErrorMessageFormatter.forError(e);
        _isLoading = false;
      });
      return;
    }
    final String msg = e is ApiQuotaExceededException
        ? AiErrorMessageFormatter.forQuota(e)
        : loadFailed.replaceAll('{error}', '$e');
    setState(() {
      _errorMessage = msg;
      _isLoading = false;
    });
  }

  void _applyPassageResult(Map<String, dynamic> result) {
    setState(() {
      // Fallback title only: a passage that arrives without one still needs a
      // heading, and the backend's own title is content, not chrome.
      _title = result['title'] ?? context.tr('practice.reading.fallbackTitle');
      _passage = result['text'] ?? '';
      final List<dynamic> questionsData = result['questions'] as List? ?? [];
      _questions = questionsData
          .map((q) => NfReadingQuestion(
                question: q['question'] ?? '',
                options: List<String>.from(q['options'] ?? []),
                correctAnswer: q['correctAnswer'] ?? '',
                explanation: q['explanation'] ?? '',
                correctAnswerQuote: q['correctAnswerQuote'] ?? '',
              ))
          .toList();
      _selectedAnswers = <int, String?>{};
      _checkedAnswers = <int, bool?>{};
      _showResults = false;
      _score = 0;
      _isLoading = false;
    });
  }

  Future<void> _loadSavedProgress() async {
    final bool completed =
        await _progressService.isCompleted(type: 'reading', level: _level);
    if (!mounted) {
      return;
    }
    setState(() => _hasCompletedToday = completed);
  }

  Future<void> _loadCompletedLevels() async {
    final Map<String, bool> completed =
        await _progressService.getCompletedLevels('reading');
    if (!mounted) {
      return;
    }
    setState(() => _completedLevels = completed);
  }

  Future<void> _restoreSavedAnswers() async {
    final ReadingReviewData? review =
        await _progressService.getReadingResult(_level);
    if (!mounted || review == null) {
      return;
    }
    setState(() {
      _selectedAnswers = Map<int, String?>.from(review.selectedAnswers);
      _checkedAnswers = Map<int, bool?>.from(review.checkedAnswers);
      _score = review.score;
      _showResults = true;
      _hasCompletedToday = true;
    });
  }

  // ---------------------------------------------------------------------------
  // Interaction
  // ---------------------------------------------------------------------------

  void _switchLevel(String level) {
    if (level == _level || _isLoading) {
      return;
    }
    setState(() {
      _level = level;
      _variant = 0;
      _hasCompletedToday = _completedLevels[level] == true;
    });
    unawaited(_loadPassage());
    unawaited(_loadSavedProgress());
  }

  void _selectAnswer(int questionIndex, String answerLetter) {
    if (_showResults) {
      return;
    }
    setState(() => _selectedAnswers[questionIndex] = answerLetter);
  }

  Future<void> _checkAnswers() async {
    int correct = 0;
    for (int i = 0; i < _questions.length; i++) {
      final String? selectedAnswer = _selectedAnswers[i];
      // Grading is by POSITION LETTER: correctAnswer is "A".."D" and so is the
      // stored selection. Comparing option text here would break as soon as
      // two options carry the same wording.
      final bool isCorrect = selectedAnswer == _questions[i].correctAnswer;
      _checkedAnswers[i] = isCorrect;
      if (isCorrect) {
        correct++;
      }
    }

    setState(() {
      _score = correct;
      _showResults = true;
      _hasCompletedToday = true;
      _completedLevels = <String, bool>{..._completedLevels, _level: true};
    });

    await _progressService.saveReadingResult(
      level: _level,
      score: correct,
      totalQuestions: _questions.length,
      selectedAnswers: _selectedAnswers,
      checkedAnswers: _checkedAnswers,
    );

    if (mounted) {
      final AppStateProvider appState = context.read<AppStateProvider>();
      // XP scales with level, same brackets as the legacy screen.
      final XPActionType xpAction;
      if (_level == 'A1' || _level == 'A2') {
        xpAction = XPActionTypes.readingEasy;
      } else if (_level == 'B1' || _level == 'B2') {
        xpAction = XPActionTypes.readingMedium;
      } else {
        xpAction = XPActionTypes.readingHard;
      }
      // The source strings are analytics data the backend already groups by;
      // changing them would split the reading totals across two buckets.
      await appState.addXPForAction(xpAction, source: 'Okuma Pratiği');
      if (correct == _questions.length && _questions.isNotEmpty) {
        await appState.addXP(10, reason: 'Mükemmel Okuma Skoru');
      }
    }

    if (mounted) {
      await FeedbackPromptSheet.maybeShow(context);
    }
  }

  void _retryCurrentPassage() {
    setState(() {
      _selectedAnswers = <int, String?>{};
      _checkedAnswers = <int, bool?>{};
      _showResults = false;
      _score = 0;
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  /// The palette comes from the `NfThemeScope` the caller wraps this route in.
  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    return Scaffold(
      backgroundColor: t.ground,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _buildHeader(t),
            _buildLevelRow(t),
            Expanded(child: _buildContent(t)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(NfTokens t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NfSpace.s12,
        NfSpace.s8,
        NfSpace.s16,
        NfSpace.s4,
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            iconSize: NfFont.s22,
            color: t.ink,
            // The default 48px IconButton already clears the tap floor.
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          ),
          const SizedBox(width: NfSpace.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  context.tr('practice.reading.title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NfTokens.display(size: NfFont.s20, color: t.ink),
                ),
                Text(
                  context.tr('practice.reading.dailyInfo1'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NfTokens.body(size: NfFont.s12, color: t.inkMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The A1–C2 picker. A completed level carries a check icon — the same
  /// promise as the legacy badge: one daily test per level, and you can see at
  /// a glance which are done.
  Widget _buildLevelRow(NfTokens t) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        NfSpace.s16,
        NfSpace.s4,
        NfSpace.s16,
        NfSpace.s8,
      ),
      child: Row(
        children: <Widget>[
          for (final String level in _levels) ...<Widget>[
            NfChip(
              label: level,
              icon: _completedLevels[level] == true
                  ? Icons.check_rounded
                  : null,
              variant: level == _level
                  ? NfChipVariant.selected
                  : NfChipVariant.unselected,
              onTap: () => _switchLevel(level),
            ),
            if (level != _levels.last) const SizedBox(width: NfSpace.s8),
          ],
        ],
      ),
    );
  }

  Widget _buildContent(NfTokens t) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: NfStroke.iconHeavy,
                valueColor: AlwaysStoppedAnimation<Color>(t.primary),
              ),
            ),
            const SizedBox(height: NfSpace.s16),
            Text(
              context.tr('practice.reading.preparing'),
              style: NfTokens.body(size: NfFont.s14, color: t.inkMuted),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(NfSpace.s26),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.error_outline_rounded, size: 44, color: t.wrong),
              const SizedBox(height: NfSpace.s14),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: NfTokens.body(size: NfFont.s14, color: t.inkMuted),
              ),
              const SizedBox(height: NfSpace.s20),
              NfSecondaryButton(
                label: context.tr('common.tryAgain'),
                icon: Icons.refresh_rounded,
                expand: false,
                onPressed: () => unawaited(_loadPassage()),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        NfSpace.s16,
        NfSpace.s8,
        NfSpace.s16,
        NfSpace.s26 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // The passage, without card chrome: a title, then the text itself at
          // a book-like measure. The reading experience *is* the screen.
          Text(
            _title,
            style: NfTokens.display(size: NfFont.s22, color: t.ink),
          ),
          const SizedBox(height: NfSpace.s6),
          Text(
            '${context.tr('common.level')}: $_level',
            style: NfTokens.body(
              size: NfFont.s12,
              weight: NfTokens.bodyEmphasisWeight,
              color: t.inkFaint,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: NfSpace.s14),
          Text(
            _passage,
            style: NfTokens.body(
              size: NfFont.s16,
              weight: FontWeight.w600,
              color: t.ink,
              height: 1.8,
            ),
          ),
          // Sits under the passage rather than over it — at the top it would
          // compete with the text. Passages have shipped empty or truncated
          // before, and a reader who hits one should be able to say so.
          Align(
            alignment: Alignment.centerRight,
            child: ReportContentButton(
              content: _passage,
              surface: 'reading_practice',
              contentKind: 'passage',
              extra: <String, dynamic>{
                'level': _level,
                'title': _title,
                'variant': _variant,
              },
            ),
          ),
          const SizedBox(height: NfSpace.s16),

          // Questions header.
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  context
                      .tr('practice.reading.questions')
                      .replaceAll('{n}', '${_questions.length}'),
                  style: NfTokens.display(size: NfFont.s18, color: t.ink),
                ),
              ),
              if (_showResults)
                NfChip(
                  label: context
                      .tr('practice.reading.score')
                      .replaceAll('{a}', '$_score')
                      .replaceAll('{b}', '${_questions.length}'),
                  dense: true,
                  variant: _score == _questions.length
                      ? NfChipVariant.correct
                      : NfChipVariant.streak,
                ),
            ],
          ),
          const SizedBox(height: NfSpace.s12),

          if (_hasCompletedToday && !_showResults) ...<Widget>[
            NfCard(
              backgroundColor: t.correctSoft,
              borderColor: t.correct,
              padding: const EdgeInsets.all(NfSpace.s12),
              child: Row(
                children: <Widget>[
                  Icon(Icons.check_circle_rounded, color: t.correct, size: 20),
                  const SizedBox(width: NfSpace.s10),
                  Expanded(
                    child: Text(
                      context.tr('practice.reading.doneToday'),
                      style: NfTokens.body(size: NfFont.s13, color: t.ink),
                    ),
                  ),
                  const SizedBox(width: NfSpace.s8),
                  NfSecondaryButton(
                    label: context.tr('practice.reading.showAnswers'),
                    tone: NfButtonTone.correct,
                    expand: false,
                    height: NfSize.minTap,
                    onPressed: () => unawaited(_restoreSavedAnswers()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: NfSpace.s14),
          ],

          ..._questions.asMap().entries.map(
                (MapEntry<int, NfReadingQuestion> entry) =>
                    _buildQuestionCard(t, entry.key, entry.value),
              ),

          const SizedBox(height: NfSpace.s8),

          if (!_showResults && _questions.isNotEmpty)
            NfPrimaryButton(
              label: _selectedAnswers.length == _questions.length
                  ? context.tr('practice.reading.checkAnswers')
                  : context
                      .tr('practice.reading.answerAll')
                      .replaceAll('{a}', '${_selectedAnswers.length}')
                      .replaceAll('{b}', '${_questions.length}'),
              onPressed: _selectedAnswers.length == _questions.length
                  ? () => unawaited(_checkAnswers())
                  : null,
            ),

          if (_showResults) ...<Widget>[
            NfSecondaryButton(
              label: context.tr('practice.reading.retake'),
              icon: Icons.refresh_rounded,
              onPressed: _retryCurrentPassage,
            ),
            const SizedBox(height: NfSpace.s10),
            NfPrimaryButton(
              key: const ValueKey('new-reading-passage'),
              label: context.tr('practice.reading.newPassage'),
              icon: Icons.auto_awesome_outlined,
              onPressed: () => unawaited(_loadFreshPassage()),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuestionCard(NfTokens t, int index, NfReadingQuestion question) {
    final String? selectedAnswer = _selectedAnswers[index];
    final bool? isChecked = _checkedAnswers[index];

    final Color? cardBorder = !_showResults || isChecked == null
        ? null
        : (isChecked ? t.correct : t.wrong);

    return Padding(
      padding: const EdgeInsets.only(bottom: NfSpace.s14),
      child: NfCard(
        borderColor: cardBorder,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: t.primarySoft,
                    borderRadius: NfRadius.iconTileAll,
                  ),
                  child: Text(
                    '${index + 1}',
                    style: NfTokens.display(
                      size: NfFont.s14,
                      color: t.primaryText,
                    ),
                  ),
                ),
                const SizedBox(width: NfSpace.s10),
                Expanded(
                  child: Text(
                    question.question,
                    style: NfTokens.body(
                      size: NfFont.s145,
                      weight: NfTokens.bodyEmphasisWeight,
                      color: t.ink,
                      height: 1.4,
                    ),
                  ),
                ),
                // Reported separately from the passage: a comprehension
                // question can be unanswerable from a passage that is itself
                // fine, and the two failures need different fixes.
                ReportContentButton(
                  content: question.question,
                  surface: 'reading_practice',
                  contentKind: 'comprehension_question',
                  extra: <String, dynamic>{
                    'level': _level,
                    'title': _title,
                    'options': question.options.join(' | '),
                    'correctAnswer': question.correctAnswer,
                  },
                ),
              ],
            ),
            const SizedBox(height: NfSpace.s12),
            ...question.options.asMap().entries.map(
              (MapEntry<int, String> optionEntry) {
                final int optionIndex = optionEntry.key;
                final String option = optionEntry.value;
                // A, B, C, D — the grading currency of this test.
                final String optionLabel =
                    String.fromCharCode(65 + optionIndex);
                final bool isSelected = selectedAnswer == optionLabel;
                final bool isCorrectOption =
                    question.correctAnswer == optionLabel;
                return _buildOptionRow(
                  t: t,
                  questionIndex: index,
                  optionLabel: optionLabel,
                  option: option,
                  isSelected: isSelected,
                  isCorrectOption: isCorrectOption,
                );
              },
            ),
            if (_showResults && question.explanation.isNotEmpty) ...<Widget>[
              const SizedBox(height: NfSpace.s6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(NfSpace.s12),
                decoration: BoxDecoration(
                  color: t.primarySoft,
                  borderRadius: NfRadius.tileAll,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.lightbulb_outline_rounded,
                          color: t.primaryText,
                          size: 16,
                        ),
                        const SizedBox(width: NfSpace.s6),
                        Text(
                          context.tr('practice.reading.explanation'),
                          style: NfTokens.body(
                            size: NfFont.s12,
                            weight: NfTokens.bodyEmphasisWeight,
                            color: t.primaryText,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: NfSpace.s6),
                    Text(
                      question.explanation,
                      style: NfTokens.body(
                        size: NfFont.s13,
                        color: t.ink,
                        height: 1.5,
                      ),
                    ),
                    if (question.correctAnswerQuote.isNotEmpty) ...<Widget>[
                      const SizedBox(height: NfSpace.s6),
                      // The evidence quote: the line in the passage the answer
                      // rests on.
                      Text(
                        '"${question.correctAnswerQuote}"',
                        style: NfTokens.body(
                          size: NfFont.s125,
                          weight: FontWeight.w600,
                          color: t.inkMuted,
                          height: 1.5,
                        ).copyWith(fontStyle: FontStyle.italic),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOptionRow({
    required NfTokens t,
    required int questionIndex,
    required String optionLabel,
    required String option,
    required bool isSelected,
    required bool isCorrectOption,
  }) {
    Color borderColor = t.border;
    Color fillColor = t.surface;
    Color badgeColor = t.raised;
    Color badgeInk = t.inkMuted;

    if (_showResults) {
      if (isCorrectOption) {
        borderColor = t.correct;
        fillColor = t.correctSoft;
        badgeColor = t.correct;
        badgeInk = t.primaryInk;
      } else if (isSelected) {
        borderColor = t.wrong;
        fillColor = t.wrongSoft;
        badgeColor = t.wrong;
        badgeInk = t.primaryInk;
      }
    } else if (isSelected) {
      borderColor = t.primary;
      fillColor = t.primarySoft;
      badgeColor = t.primary;
      badgeInk = t.primaryInk;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: NfSpace.s8),
      child: Semantics(
        button: true,
        selected: isSelected,
        child: MouseRegion(
          cursor: _showResults
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _showResults
                ? null
                : () => _selectAnswer(questionIndex, optionLabel),
            child: Container(
              constraints: const BoxConstraints(minHeight: NfSize.minTap),
              padding: const EdgeInsets.symmetric(
                horizontal: NfSpace.s12,
                vertical: NfSpace.s10,
              ),
              decoration: BoxDecoration(
                color: fillColor,
                borderRadius: NfRadius.tileAll,
                border: Border.fromBorderSide(t.sideOf(borderColor)),
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: NfRadius.pillAll,
                    ),
                    child: Text(
                      optionLabel,
                      style: NfTokens.display(
                        size: NfFont.s13,
                        color: badgeInk,
                        height: 1,
                      ),
                    ),
                  ),
                  const SizedBox(width: NfSpace.s10),
                  Expanded(
                    child: Text(
                      option,
                      style: NfTokens.body(
                        size: NfFont.s14,
                        color: t.ink,
                        height: 1.4,
                      ),
                    ),
                  ),
                  if (_showResults && isCorrectOption)
                    Icon(Icons.check_circle_rounded,
                        color: t.correct, size: 20),
                  if (_showResults && isSelected && !isCorrectOption)
                    Icon(Icons.cancel_rounded, color: t.wrong, size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One comprehension question. Public shape mirrors the legacy `Question`
/// model so the API payload maps straight across.
class NfReadingQuestion {
  const NfReadingQuestion({
    required this.question,
    required this.options,
    required this.correctAnswer,
    required this.explanation,
    required this.correctAnswerQuote,
  });

  final String question;
  final List<String> options;

  /// A position letter, "A".."D" — not the option text.
  final String correctAnswer;
  final String explanation;

  /// The sentence in the passage that proves the answer.
  final String correctAnswerQuote;
}
