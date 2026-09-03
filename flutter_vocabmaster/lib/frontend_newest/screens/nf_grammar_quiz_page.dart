import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/grammar_data.dart';
import '../../l10n/app_localizations.dart';
import '../../models/word.dart';
import '../../providers/app_state_provider.dart';
import '../../services/ai_error_message_formatter.dart';
import '../../services/ai_paywall_handler.dart';
import '../../services/api_service.dart';
import '../../services/learning_language_service.dart';
import '../../services/xp_manager.dart';
import '../../widgets/report_content_button.dart';
import '../theme/nf_tokens.dart';
import '../widgets/nf_button.dart';
import '../widgets/nf_card.dart';

/// The AI practice quiz for one grammar topic, redrawn from `GrammarQuizPage`.
///
/// Questions are generated at the learner's profile CEFR level; every
/// "New Quiz" sends an increasing variant seed. Answers over the learner's own
/// vocabulary (questions carrying a `targetWord`) are also fed to the review
/// scheduler, exactly as the legacy screen did.
///
/// One deliberate fix over the legacy rendering: answers are tracked by option
/// *index*, not by option text. The model occasionally returns two options
/// with identical wording, and string-keyed selection lit both of them up when
/// either was tapped.
class NfGrammarQuizPage extends StatefulWidget {
  const NfGrammarQuizPage({super.key, required this.topic, this.subtopic});

  final GrammarTopic topic;

  /// The subtopic the learner had open when they tapped Practice, if any.
  ///
  /// Without it the request said "Tenses" — a topic with twelve subtopics —
  /// and the prompt's "testing ONLY this grammar topic" spanned all of them.
  /// Someone who had just read Past Perfect Continuous got five questions
  /// drawn from anywhere in the tense system, which from the learner's side
  /// reads as a quiz that has nothing to do with the lesson.
  final GrammarSubtopic? subtopic;

  /// The topic string the generator is asked for. Static and pure so a test
  /// can ask it directly rather than through a network call.
  @visibleForTesting
  static String requestedTopicFor(GrammarTopic topic, GrammarSubtopic? sub) =>
      sub == null ? topic.title : '${topic.title}: ${sub.title}';

  @override
  State<NfGrammarQuizPage> createState() => _NfGrammarQuizPageState();
}

class _NfGrammarQuizPageState extends State<NfGrammarQuizPage> {
  bool _isLoading = true;
  String? _errorMessage;
  List<_NfQuizQuestion> _questions = const <_NfQuizQuestion>[];

  /// Question index -> selected option index. Index-keyed on purpose; see the
  /// class comment.
  final Map<int, int> _selectedOptionIndexes = <int, int>{};

  bool _showResults = false;
  int _variant = 0;
  bool _xpAwarded = false;

  bool get _isTurkish =>
      Localizations.localeOf(context).languageCode == 'tr';

  /// What the generator is asked for.
  ///
  /// Both parts, because eighteen of the eighty-six subtopics do not name a
  /// grammar point on their own: "Ability", "Possibility", "Zero Article",
  /// "Other Inversions". Sent alone, "Ability" is a request for nothing in
  /// particular, which is a worse quiz than the broad one it replaced.
  String get _requestedTopic =>
      NfGrammarQuizPage.requestedTopicFor(widget.topic, widget.subtopic);

  @override
  void initState() {
    super.initState();
    // After the first frame, not inside initState. _loadQuiz resolves its two
    // error strings from the localizations before its first await -- on
    // purpose, so no failure path reaches for a BuildContext across one -- and
    // reading an inherited widget while initState is still running is an
    // error. Release builds strip the assertion and carry on, so this only
    // ever surfaced when a widget test pumped the page.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_loadQuiz());
      }
    });
  }

  Future<void> _loadQuiz({bool fresh = false}) async {
    // Resolved before the request so no failure path has to reach for a
    // BuildContext across an await.
    final String emptyError = context.tr('grammar.quiz.errEmpty');
    final String loadErrorTemplate = context.tr('grammar.quiz.errLoad');
    if (fresh) {
      _variant += 1;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _selectedOptionIndexes.clear();
      _showResults = false;
      _xpAwarded = false;
    });
    try {
      final Map<String, dynamic> result =
          await ApiService().chatbotGenerateGrammarQuiz(
        topic: _requestedTopic,
        level: LearningLanguageService.englishLevel,
        variant: _variant,
      );
      final List<dynamic> rawQuestions = result['questions'] as List? ?? [];
      final List<_NfQuizQuestion> questions = rawQuestions
          .whereType<Map>()
          .map((Map q) => _NfQuizQuestion(
                question: (q['question'] ?? '').toString(),
                options: List<String>.from(
                    (q['options'] as List? ?? []).map((o) => o.toString())),
                correctAnswer: (q['correctAnswer'] ?? '').toString(),
                explanation: (q['explanation'] ?? '').toString(),
                targetWord: (q['targetWord'] ?? '').toString().trim(),
              ))
          .where((_NfQuizQuestion q) =>
              q.question.isNotEmpty &&
              q.options.length >= 2 &&
              q.options.contains(q.correctAnswer))
          .toList();
      if (!mounted) {
        return;
      }
      if (questions.isEmpty) {
        setState(() {
          _errorMessage = emptyError;
          _isLoading = false;
        });
        return;
      }
      setState(() {
        _questions = questions;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
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
      final String msg =
          AiErrorMessageFormatter.intoTemplate(loadErrorTemplate, e);
      setState(() {
        _errorMessage = msg;
        _isLoading = false;
      });
    }
  }

  bool _isAnswerCorrect(int questionIndex) {
    final int? selected = _selectedOptionIndexes[questionIndex];
    if (selected == null) {
      return false;
    }
    final _NfQuizQuestion question = _questions[questionIndex];
    return question.options[selected] == question.correctAnswer;
  }

  int get _score {
    int score = 0;
    for (int i = 0; i < _questions.length; i++) {
      if (_isAnswerCorrect(i)) {
        score++;
      }
    }
    return score;
  }

  Future<void> _finishQuiz() async {
    setState(() => _showResults = true);
    if (_xpAwarded) {
      return;
    }
    _xpAwarded = true;
    final AppStateProvider appState = context.read<AppStateProvider>();
    final DateTime today = DateTime.now();
    final String dayKey = '${today.year}-${today.month}-${today.day}';
    await appState.addXPForAction(
      XPActionTypes.grammarTopicView,
      // Analytics label the backend already groups by; kept verbatim.
      source: _isTurkish ? 'Gramer Quiz' : 'Grammar Quiz',
      transactionId: 'grammar_quiz_${widget.topic.id}_$dayKey',
    );
    await _recordAnswersAsReviews(appState);
  }

  /// Feeds the answers to the review scheduler, one per question that was
  /// built on a word the learner is studying.
  ///
  /// A grammar question over the learner's own vocabulary is evidence about
  /// two things at once: whether they know the rule, and whether they still
  /// know the word. Only questions carrying a `targetWord` count — when the
  /// model could not fit any of the learner's words to the grammar point it
  /// returns an empty one, and a question about a neutral word says nothing
  /// about this learner's vocabulary.
  Future<void> _recordAnswersAsReviews(AppStateProvider appState) async {
    final List<Word> words = appState.allWords;
    if (words.isEmpty) {
      return;
    }

    for (int i = 0; i < _questions.length; i++) {
      final String target = _questions[i].targetWord;
      if (target.isEmpty) {
        continue;
      }

      // The model was asked to inflect the word to fit the sentence, so match
      // on the stem rather than expecting the exact stored form back.
      final String normalized = target.toLowerCase();
      Word? match;
      for (final Word word in words) {
        final String stored = word.englishWord.trim().toLowerCase();
        if (stored.isEmpty) {
          continue;
        }
        if (stored == normalized ||
            normalized.startsWith(stored) ||
            stored.startsWith(normalized)) {
          match = word;
          break;
        }
      }
      if (match == null) {
        continue;
      }

      final bool wasCorrect = _isAnswerCorrect(i);
      try {
        await appState.submitWordReview(
          wordId: match.id,
          // Same scale as translation practice: a correct answer is solid but
          // untimed, so 4 rather than 5; a wrong one is a lapse without
          // erasing the word's history.
          quality: wasCorrect ? 4 : 2,
          source: 'grammar_practice',
        );
      } catch (e) {
        debugPrint('Grammar review not recorded for ${match.englishWord}: $e');
      }
    }
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
            Expanded(
              child: _isLoading
                  ? _buildLoading(t)
                  : _errorMessage != null
                      ? _buildError(t)
                      : _buildQuiz(t),
            ),
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
                  context.tr('grammar.quiz.title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NfTokens.display(size: NfFont.s20, color: t.ink),
                ),
                Text(
                  '${context.tr('common.level')}: '
                  '${LearningLanguageService.englishLevel}',
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

  Widget _buildLoading(NfTokens t) {
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
            context.tr('grammar.quiz.loading'),
            textAlign: TextAlign.center,
            style: NfTokens.body(size: NfFont.s14, color: t.inkMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildError(NfTokens t) {
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
              onPressed: () => unawaited(_loadQuiz()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuiz(NfTokens t) {
    final bool allAnswered =
        _selectedOptionIndexes.length == _questions.length;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        NfSpace.s16,
        NfSpace.s8,
        NfSpace.s16,
        NfSpace.s26 + MediaQuery.paddingOf(context).bottom,
      ),
      children: <Widget>[
        Text(
          _isTurkish ? widget.topic.titleTr : widget.topic.title,
          style: NfTokens.display(size: NfFont.s18, color: t.primaryText),
        ),
        // Named, so the learner can see the quiz is about the lesson they
        // just read rather than the whole topic.
        if (widget.subtopic != null)
          Padding(
            padding: const EdgeInsets.only(top: NfSpace.s4),
            child: Text(
              _isTurkish
                  ? widget.subtopic!.titleTr
                  : widget.subtopic!.title,
              style: NfTokens.body(size: NfFont.s135, color: t.primaryText),
            ),
          ),
        const SizedBox(height: NfSpace.s14),
        ...List<Widget>.generate(
          _questions.length,
          (int i) => _buildQuestionCard(t, i),
        ),
        const SizedBox(height: NfSpace.s8),
        if (!_showResults)
          NfPrimaryButton(
            label: allAnswered
                ? context.tr('grammar.quiz.check')
                : context
                    .tr('grammar.quiz.answerAll')
                    .replaceAll('{a}', '${_selectedOptionIndexes.length}')
                    .replaceAll('{b}', '${_questions.length}'),
            onPressed: allAnswered ? () => unawaited(_finishQuiz()) : null,
          )
        else ...<Widget>[
          NfCard(
            backgroundColor:
                _score == _questions.length ? t.correctSoft : t.primarySoft,
            borderColor: _score == _questions.length ? t.correct : t.primary,
            child: Center(
              child: Text(
                context
                    .tr('grammar.quiz.score')
                    .replaceAll('{a}', '$_score')
                    .replaceAll('{b}', '${_questions.length}'),
                style: NfTokens.display(size: NfFont.s18, color: t.ink),
              ),
            ),
          ),
          const SizedBox(height: NfSpace.s12),
          NfPrimaryButton(
            key: const ValueKey('new-grammar-quiz'),
            label: context.tr('grammar.quiz.new'),
            icon: Icons.auto_awesome_outlined,
            onPressed: () => unawaited(_loadQuiz(fresh: true)),
          ),
        ],
      ],
    );
  }

  Widget _buildQuestionCard(NfTokens t, int index) {
    final _NfQuizQuestion question = _questions[index];
    final int? selectedIndex = _selectedOptionIndexes[index];

    return Padding(
      padding: const EdgeInsets.only(bottom: NfSpace.s14),
      child: NfCard(
        borderColor: !_showResults
            ? null
            : (_isAnswerCorrect(index) ? t.correct : t.wrong),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${index + 1}. ${question.question}',
                    style: NfTokens.body(
                      size: NfFont.s145,
                      weight: NfTokens.bodyEmphasisWeight,
                      color: t.ink,
                      height: 1.5,
                    ),
                  ),
                ),
                // These questions are built around the learner's own
                // vocabulary; when the model cannot fit a word to a tense it
                // produces a grammatical-looking sentence that teaches the
                // wrong thing, and nothing in the response says so.
                ReportContentButton(
                  content: question.question,
                  surface: 'grammar_quiz',
                  contentKind: 'quiz_question',
                  extra: <String, dynamic>{
                    'topic': widget.topic.id,
                    'correctAnswer': question.correctAnswer,
                    'options': question.options.join(' | '),
                    if (question.targetWord.isNotEmpty)
                      'targetWord': question.targetWord,
                  },
                ),
              ],
            ),
            const SizedBox(height: NfSpace.s10),
            ...question.options.asMap().entries.map(
              (MapEntry<int, String> entry) {
                final int optionIndex = entry.key;
                final String option = entry.value;
                final bool isSelected = selectedIndex == optionIndex;
                final bool isCorrectText = option == question.correctAnswer;

                Color borderColor = t.border;
                Color fillColor = t.surface;
                if (_showResults) {
                  if (isCorrectText) {
                    borderColor = t.correct;
                    fillColor = t.correctSoft;
                  } else if (isSelected) {
                    borderColor = t.wrong;
                    fillColor = t.wrongSoft;
                  }
                } else if (isSelected) {
                  borderColor = t.primary;
                  fillColor = t.primarySoft;
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
                            : () => setState(() =>
                                _selectedOptionIndexes[index] = optionIndex),
                        child: Container(
                          width: double.infinity,
                          constraints:
                              const BoxConstraints(minHeight: NfSize.minTap),
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(
                            horizontal: NfSpace.s12,
                            vertical: NfSpace.s10,
                          ),
                          decoration: BoxDecoration(
                            color: fillColor,
                            borderRadius: NfRadius.tileAll,
                            border:
                                Border.fromBorderSide(t.sideOf(borderColor)),
                          ),
                          child: Row(
                            children: <Widget>[
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
                              if (_showResults && isCorrectText)
                                Icon(Icons.check_circle_rounded,
                                    color: t.correct, size: 18),
                              if (_showResults &&
                                  isSelected &&
                                  !isCorrectText)
                                Icon(Icons.cancel_rounded,
                                    color: t.wrong, size: 18),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            if (_showResults && question.explanation.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: NfSpace.s4),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(NfSpace.s12),
                  decoration: BoxDecoration(
                    color: t.primarySoft,
                    borderRadius: NfRadius.tileAll,
                  ),
                  child: Text(
                    question.explanation,
                    style: NfTokens.body(
                      size: NfFont.s13,
                      color: t.ink,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One quiz question, straight from the API payload.
class _NfQuizQuestion {
  const _NfQuizQuestion({
    required this.question,
    required this.options,
    required this.correctAnswer,
    required this.explanation,
    this.targetWord = '',
  });

  final String question;
  final List<String> options;

  /// The correct option's *text* (unlike reading practice, which grades by
  /// position letter). Selection is still stored by index so duplicate option
  /// texts render sanely.
  final String correctAnswer;
  final String explanation;

  /// The learner's own vocabulary word this question was built around, if any.
  /// Empty when the model could not fit one naturally — the correct outcome,
  /// since forcing one in produces a sentence that teaches a mistake.
  final String targetWord;
}
