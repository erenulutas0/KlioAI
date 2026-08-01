import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/grammar_data.dart';
import '../models/word.dart';
import '../providers/app_state_provider.dart';
import '../services/api_service.dart';
import '../services/ai_error_message_formatter.dart';
import '../services/ai_paywall_handler.dart';
import '../services/learning_language_service.dart';
import '../services/xp_manager.dart';
import '../widgets/report_content_button.dart';

/// Gramer konusu için AI üretimli 5 soruluk pratik quiz ekranı.
/// Sorular kullanıcının profil CEFR seviyesine göre üretilir; her "Yeni Quiz"
/// isteğinde backend'e artan bir variant tohumu gönderilir.
class GrammarQuizPage extends StatefulWidget {
  final GrammarTopic topic;

  const GrammarQuizPage({super.key, required this.topic});

  @override
  State<GrammarQuizPage> createState() => _GrammarQuizPageState();
}

class _GrammarQuizPageState extends State<GrammarQuizPage> {
  bool _isLoading = true;
  String? _errorMessage;
  List<_QuizQuestion> _questions = const [];
  final Map<int, String> _selectedAnswers = {};
  bool _showResults = false;
  int _variant = 0;
  bool _xpAwarded = false;

  bool get _isTurkish => Localizations.localeOf(context).languageCode == 'tr';

  String _text(String tr, String en) => _isTurkish ? tr : en;

  @override
  void initState() {
    super.initState();
    _loadQuiz();
  }

  Future<void> _loadQuiz({bool fresh = false}) async {
    if (fresh) _variant += 1;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _selectedAnswers.clear();
      _showResults = false;
      _xpAwarded = false;
    });
    try {
      final result = await ApiService().chatbotGenerateGrammarQuiz(
        topic: widget.topic.title,
        level: LearningLanguageService.englishLevel,
        variant: _variant,
      );
      final rawQuestions = result['questions'] as List? ?? [];
      final questions = rawQuestions
          .whereType<Map>()
          .map((q) => _QuizQuestion(
                question: (q['question'] ?? '').toString(),
                options: List<String>.from(
                    (q['options'] as List? ?? []).map((o) => o.toString())),
                correctAnswer: (q['correctAnswer'] ?? '').toString(),
                explanation: (q['explanation'] ?? '').toString(),
                targetWord: (q['targetWord'] ?? '').toString().trim(),
              ))
          .where((q) =>
              q.question.isNotEmpty &&
              q.options.length >= 2 &&
              q.options.contains(q.correctAnswer))
          .toList();
      if (!mounted) return;
      if (questions.isEmpty) {
        setState(() {
          _errorMessage = _text(
            'Quiz üretilemedi, lütfen tekrar deneyin.',
            'Could not generate the quiz, please try again.',
          );
          _isLoading = false;
        });
        return;
      }
      setState(() {
        _questions = questions;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (await AiPaywallHandler.handleIfUpgradeRequired(context, e)) {
        setState(() {
          _errorMessage = AiErrorMessageFormatter.forError(e);
          _isLoading = false;
        });
        return;
      }
      final msg = e is ApiQuotaExceededException
          ? AiErrorMessageFormatter.forQuota(e)
          : _text('Quiz yüklenemedi: $e', 'Failed to load quiz: $e');
      setState(() {
        _errorMessage = msg;
        _isLoading = false;
      });
    }
  }

  int get _score {
    int score = 0;
    for (int i = 0; i < _questions.length; i++) {
      if (_selectedAnswers[i] == _questions[i].correctAnswer) score++;
    }
    return score;
  }

  Future<void> _finishQuiz() async {
    setState(() => _showResults = true);
    if (_xpAwarded) return;
    _xpAwarded = true;
    final appState = context.read<AppStateProvider>();
    final today = DateTime.now();
    final dayKey = '${today.year}-${today.month}-${today.day}';
    await appState.addXPForAction(
      XPActionTypes.grammarTopicView,
      source: _text('Gramer Quiz', 'Grammar Quiz'),
      transactionId: 'grammar_quiz_${widget.topic.id}_$dayKey',
    );
    await _recordAnswersAsReviews(appState);
  }

  /// Feeds the answers to the review scheduler, one per question that was built on a word
  /// the learner is studying.
  ///
  /// A grammar question over the learner's own vocabulary is evidence about two things at
  /// once: whether they know the rule, and whether they still know the word. The second was
  /// being thrown away — the quiz produced a score and nothing else. Now a tense drill on
  /// "recover" moves that word's schedule just as a flashcard would.
  ///
  /// Only questions carrying a targetWord count. When the model could not fit any of the
  /// learner's words to the grammar point it returns an empty one, and a question about a
  /// neutral word says nothing about this learner's vocabulary.
  Future<void> _recordAnswersAsReviews(AppStateProvider appState) async {
    final words = appState.allWords;
    if (words.isEmpty) return;

    for (var i = 0; i < _questions.length; i++) {
      final target = _questions[i].targetWord;
      if (target.isEmpty) continue;

      // The model was asked to inflect the word to fit the sentence, so match on the stem
      // rather than expecting the exact stored form back.
      final normalized = target.toLowerCase();
      Word? match;
      for (final word in words) {
        final stored = word.englishWord.trim().toLowerCase();
        if (stored.isEmpty) continue;
        if (stored == normalized ||
            normalized.startsWith(stored) ||
            stored.startsWith(normalized)) {
          match = word;
          break;
        }
      }
      if (match == null) continue;

      final wasCorrect = _selectedAnswers[i] == _questions[i].correctAnswer;
      try {
        await appState.submitWordReview(
          wordId: match.id,
          // Same scale as translation practice: a correct answer is solid but untimed, so
          // 4 rather than 5; a wrong one is a lapse without erasing the word's history.
          quality: wasCorrect ? 4 : 2,
          source: 'grammar_practice',
        );
      } catch (e) {
        debugPrint('Grammar review not recorded for ${match.englishWord}: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.topic.color;
    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          _text('Pratik Quiz', 'Practice Quiz'),
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF111827), Color(0xFF0f172a)],
          ),
        ),
        child: _isLoading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: accent),
                    const SizedBox(height: 16),
                    Text(
                      _text(
                        'Seviyene uygun sorular hazırlanıyor...',
                        'Preparing questions for your level...',
                      ),
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              )
            : _errorMessage != null
                ? _buildError()
                : _buildQuiz(accent),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 42),
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadQuiz,
              icon: const Icon(Icons.refresh),
              label: Text(_text('Tekrar Dene', 'Retry')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuiz(Color accent) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Text(
          _isTurkish ? widget.topic.titleTr : widget.topic.title,
          style: TextStyle(
            color: accent,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          '${_text('Seviye', 'Level')}: ${LearningLanguageService.englishLevel}',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 16),
        ...List.generate(
            _questions.length, (i) => _buildQuestionCard(i, accent)),
        const SizedBox(height: 8),
        if (!_showResults)
          ElevatedButton(
            onPressed:
                _selectedAnswers.length == _questions.length ? _finishQuiz : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              disabledBackgroundColor: Colors.white12,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: Text(
              _text('Cevapları Kontrol Et', 'Check Answers'),
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
          )
        else ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accent.withValues(alpha: 0.4)),
            ),
            child: Text(
              '${_text('Skor', 'Score')}: $_score / ${_questions.length}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            key: const ValueKey('new-grammar-quiz'),
            onPressed: () => _loadQuiz(fresh: true),
            icon: const Icon(Icons.auto_awesome, color: Colors.white),
            label: Text(
              _text('Yeni Quiz Üret', 'New Quiz'),
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildQuestionCard(int index, Color accent) {
    final question = _questions[index];
    final selected = _selectedAnswers[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '${index + 1}. ${question.question}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                  ),
                ),
              ),
              // These questions are now built around the learner's own vocabulary, which
              // means the model is being asked to fit a specific word into a specific tense.
              // When that does not work it produces a grammatical-looking sentence that
              // teaches the wrong thing, and nothing in the response says so.
              ReportContentButton(
                content: question.question,
                surface: 'grammar_quiz',
                contentKind: 'quiz_question',
                extra: {
                  'topic': widget.topic.id,
                  'correctAnswer': question.correctAnswer,
                  'options': question.options.join(' | '),
                  if (question.targetWord.isNotEmpty) 'targetWord': question.targetWord,
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...question.options.map((option) {
            final isSelected = selected == option;
            final isCorrect = option == question.correctAnswer;
            Color borderColor = Colors.white.withValues(alpha: 0.12);
            Color? fillColor;
            if (_showResults) {
              if (isCorrect) {
                borderColor = Colors.green;
                fillColor = Colors.green.withValues(alpha: 0.12);
              } else if (isSelected) {
                borderColor = Colors.redAccent;
                fillColor = Colors.red.withValues(alpha: 0.12);
              }
            } else if (isSelected) {
              borderColor = accent;
              fillColor = accent.withValues(alpha: 0.12);
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: _showResults
                    ? null
                    : () => setState(() => _selectedAnswers[index] = option),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: fillColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: borderColor),
                  ),
                  child: Text(
                    option,
                    style: const TextStyle(color: Colors.white, height: 1.4),
                  ),
                ),
              ),
            );
          }),
          if (_showResults && question.explanation.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                question.explanation,
                style: const TextStyle(
                  color: Color(0xFF22D3EE),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _QuizQuestion {
  final String question;
  final List<String> options;
  final String correctAnswer;
  final String explanation;

  /// The learner's own vocabulary word this question was built around, if any.
  ///
  /// This is what turns a grammar answer into evidence about a specific word. Empty when
  /// the model could not fit any of the learner's words to the grammar point naturally —
  /// which is the correct outcome, since forcing one in produces a sentence that teaches a
  /// mistake.
  final String targetWord;

  const _QuizQuestion({
    required this.question,
    required this.options,
    required this.correctAnswer,
    required this.explanation,
    this.targetWord = '',
  });
}
