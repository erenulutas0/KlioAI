import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/animated_background.dart';
import '../services/groq_service.dart';
import '../services/api_service.dart';
import '../services/ai_error_message_formatter.dart';
import '../providers/app_state_provider.dart';
import '../services/xp_manager.dart';

class ReadingPracticePage extends StatefulWidget {
  final String level;
  final String length;
  
  const ReadingPracticePage({
    Key? key,
    this.level = 'B1',
    this.length = 'medium',
  }) : super(key: key);

  @override
  State<ReadingPracticePage> createState() => _ReadingPracticePageState();
}

class _ReadingPracticePageState extends State<ReadingPracticePage> {
  bool _isLoading = true;
  String? _errorMessage;
  
  String _title = '';
  String _passage = '';
  List<Question> _questions = [];
  Map<int, String?> _selectedAnswers = {};
  Map<int, bool?> _checkedAnswers = {};
  bool _showResults = false;
  int _score = 0;

  @override
  void initState() {
    super.initState();
    _loadPassage();
  }

  Future<void> _loadPassage() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await GroqService.generateReadingPassage(widget.level);
      
      if (mounted) {
        setState(() {
          _title = result['title'] ?? 'Reading Passage';
          _passage = result['text'] ?? '';
          
          final questionsData = result['questions'] as List? ?? [];
          _questions = questionsData.map((q) => Question(
            question: q['question'] ?? '',
            options: List<String>.from(q['options'] ?? []),
            correctAnswer: q['correctAnswer'] ?? '',
            explanation: q['explanation'] ?? '',
            correctAnswerQuote: q['correctAnswerQuote'] ?? '',
          )).toList();
          
          _selectedAnswers = {};
          _checkedAnswers = {};
          _showResults = false;
          _score = 0;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        final msg = e is ApiQuotaExceededException
            ? AiErrorMessageFormatter.forQuota(e)
            : 'Pasaj yüklenemedi: $e';
        setState(() {
          _errorMessage = msg;
          _isLoading = false;
        });
      }
    }
  }

  void _selectAnswer(int questionIndex, String answer) {
    if (_showResults) return;
    setState(() {
      _selectedAnswers[questionIndex] = answer;
    });
  }

  void _checkAnswers() async {
    int correct = 0;
    for (int i = 0; i < _questions.length; i++) {
      final selectedAnswer = _selectedAnswers[i];
      final isCorrect = selectedAnswer == _questions[i].correctAnswer;
      _checkedAnswers[i] = isCorrect;
      if (isCorrect) correct++;
    }
    
    setState(() {
      _score = correct;
      _showResults = true;
    });
    
    // XP ekle - seviyeye göre farklı XP
    if (mounted) {
      final appState = context.read<AppStateProvider>();
      XPActionType xpAction;
      
      if (widget.level == 'A1' || widget.level == 'A2') {
        xpAction = XPActionTypes.readingEasy;
      } else if (widget.level == 'B1' || widget.level == 'B2') {
        xpAction = XPActionTypes.readingMedium;
      } else {
        xpAction = XPActionTypes.readingHard;
      }
      
      await appState.addXPForAction(xpAction, source: 'Okuma Pratiği');
      
      // Mükemmel skor için bonus
      if (correct == _questions.length && _questions.isNotEmpty) {
        await appState.addXP(10, reason: 'Mükemmel Okuma Skoru');
      }
    }
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
                _buildHeader(),
                Expanded(
                  child: _buildContent(),
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Okuma Pratiği',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Seviye: ${widget.level}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          // Refresh Button
          IconButton(
            onPressed: _isLoading ? null : _loadPassage,
            icon: _isLoading 
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.refresh, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF0ea5e9)),
            SizedBox(height: 16),
            Text('Okuma parçası hazırlanıyor...', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(_errorMessage!, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadPassage,
                child: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [const Color(0xFF0ea5e9).withOpacity(0.2), const Color(0xFF3b82f6).withOpacity(0.2)],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF0ea5e9).withOpacity(0.3)),
            ),
            child: Column(
              children: [
                const Icon(Icons.menu_book, color: Color(0xFF0ea5e9), size: 32),
                const SizedBox(height: 12),
                Text(
                  _title,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Passage
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Text(
              _passage,
              style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.8),
            ),
          ),
          
          const SizedBox(height: 32),
          
          // Questions Header
          Row(
            children: [
              const Icon(Icons.quiz, color: Color(0xFF0ea5e9), size: 24),
              const SizedBox(width: 8),
              Text(
                'Sorular (${_questions.length})',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              if (_showResults) ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _score == _questions.length 
                        ? const Color(0xFF10b981).withOpacity(0.2)
                        : const Color(0xFFf59e0b).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Skor: $_score/${_questions.length}',
                    style: TextStyle(
                      color: _score == _questions.length ? const Color(0xFF10b981) : const Color(0xFFf59e0b),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Questions
          ..._questions.asMap().entries.map((entry) => _buildQuestionCard(entry.key, entry.value)),
          
          const SizedBox(height: 24),
          
          // Check Answers Button
          if (!_showResults && _questions.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF10b981), Color(0xFF059669)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: ElevatedButton(
                onPressed: _selectedAnswers.length == _questions.length ? _checkAnswers : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  disabledBackgroundColor: Colors.white.withOpacity(0.1),
                ),
                child: Text(
                  _selectedAnswers.length == _questions.length 
                      ? 'Cevapları Kontrol Et'
                      : 'Tüm soruları cevaplayın (${_selectedAnswers.length}/${_questions.length})',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          
          // New Passage Button
          if (_showResults)
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0ea5e9), Color(0xFF3b82f6)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: ElevatedButton(
                onPressed: _loadPassage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.refresh, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'Yeni Pasaj Getir',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(int index, Question question) {
    final selectedAnswer = _selectedAnswers[index];
    final isChecked = _checkedAnswers[index];
    
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isChecked == null 
              ? Colors.white.withOpacity(0.1)
              : (isChecked ? const Color(0xFF10b981) : const Color(0xFFef4444)).withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Question Number & Text
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF8b5cf6).withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(color: Color(0xFF8b5cf6), fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  question.question,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Options
          ...question.options.asMap().entries.map((optionEntry) {
            final optionIndex = optionEntry.key;
            final option = optionEntry.value;
            final optionLabel = String.fromCharCode(65 + optionIndex); // A, B, C, D
            final isSelected = selectedAnswer == optionLabel;
            final isCorrectOption = question.correctAnswer == optionLabel;
            
            Color borderColor = Colors.white.withOpacity(0.1);
            Color bgColor = Colors.transparent;
            
            if (_showResults) {
              if (isCorrectOption) {
                borderColor = const Color(0xFF10b981);
                bgColor = const Color(0xFF10b981).withOpacity(0.1);
              } else if (isSelected && !isCorrectOption) {
                borderColor = const Color(0xFFef4444);
                bgColor = const Color(0xFFef4444).withOpacity(0.1);
              }
            } else if (isSelected) {
              borderColor = const Color(0xFF0ea5e9);
              bgColor = const Color(0xFF0ea5e9).withOpacity(0.1);
            }
            
            return GestureDetector(
              onTap: () => _selectAnswer(index, optionLabel),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: isSelected 
                            ? const Color(0xFF0ea5e9)
                            : Colors.white.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        optionLabel,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        option,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ),
                    if (_showResults && isCorrectOption)
                      const Icon(Icons.check_circle, color: Color(0xFF10b981), size: 20),
                    if (_showResults && isSelected && !isCorrectOption)
                      const Icon(Icons.cancel, color: Color(0xFFef4444), size: 20),
                  ],
                ),
              ),
            );
          }),
          
          // Explanation (shown after checking)
          if (_showResults && question.explanation.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF8b5cf6).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF8b5cf6).withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.lightbulb, color: Color(0xFF8b5cf6), size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Açıklama',
                        style: TextStyle(color: Color(0xFF8b5cf6), fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    question.explanation,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  if (question.correctAnswerQuote.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '"${question.correctAnswerQuote}"',
                      style: const TextStyle(color: Colors.white54, fontSize: 12, fontStyle: FontStyle.italic),
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

class Question {
  final String question;
  final List<String> options;
  final String correctAnswer;
  final String explanation;
  final String correctAnswerQuote;

  Question({
    required this.question,
    required this.options,
    required this.correctAnswer,
    required this.explanation,
    required this.correctAnswerQuote,
  });
}
