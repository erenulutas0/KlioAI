import 'package:flutter/material.dart';
import '../models/exam_models.dart';
import '../widgets/animated_background.dart';
import 'exam_review_page.dart';

class ExamResultPage extends StatelessWidget {
  final ExamBundle examBundle;
  final Map<String, String> userAnswers;
  final int timeElapsedSeconds;

  const ExamResultPage({
    super.key,
    required this.examBundle,
    required this.userAnswers,
    required this.timeElapsedSeconds,
  });

  @override
  Widget build(BuildContext context) {
    // Calculate stats
    int totalQuestions = 0;
    int correctCount = 0;
    int blankCount = 0;
    
    // Group analysis by section
    Map<String, _SectionResult> sectionResults = {};

    for (var section in examBundle.sections) {
      int sectionCorrect = 0;
      int sectionTotal = section.items.length;
      
      for (var item in section.items) {
        totalQuestions++;
        final userAnswer = userAnswers[item.id];
        if (userAnswer == null) {
          blankCount++;
        } else if (userAnswer == item.correct) {
          correctCount++;
          sectionCorrect++;
        }
      }
      
      sectionResults[section.name] = _SectionResult(sectionCorrect, sectionTotal);
    }
    
    int incorrectCount = totalQuestions - correctCount - blankCount;
    // YDS score is typically Correct * 1.25 (since 80 questions = 100 points)
    // But for general purpose let's just do percentage or normalized score
    double rawScore = (correctCount / totalQuestions) * 100;

    return Scaffold(
      body: Stack(
        children: [
          const AnimatedBackground(isDark: true),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    'Sınav Sonucu',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // SCORE CARD
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                         const Color(0xFF0ea5e9).withOpacity(0.8),
                         const Color(0xFF3b82f6).withOpacity(0.8),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [
                         BoxShadow(
                           color: const Color(0xFF3b82f6).withOpacity(0.3),
                           blurRadius: 30,
                           offset: const Offset(0, 10),
                         ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'TOPLAM PUAN',
                          style: TextStyle(
                            color: Colors.white70,
                            letterSpacing: 2,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          rawScore.toStringAsFixed(1),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 64,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildStatItem('Doğru', correctCount.toString(), Colors.greenAccent),
                            _buildStatItem('Yanlış', incorrectCount.toString(), Colors.redAccent),
                            _buildStatItem('Boş', blankCount.toString(), Colors.white60),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // REVIEW BUTTONS
                  Padding(
                    padding: const EdgeInsets.only(bottom: 32),
                    child: Column(
                      children: [
                        // Yanlışlar
                        if (incorrectCount > 0)
                          _buildReviewBtn(
                            context, 
                            'Yanlışları İncele ($incorrectCount)', 
                            Colors.redAccent, 
                            Icons.cancel_outlined, 
                            (item, ans) => ans != null && ans != item.correct
                          ),

                        // Boşlar
                        if (blankCount > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: _buildReviewBtn(
                              context, 
                              'Boşları İncele ($blankCount)', 
                              Colors.amber.shade700, 
                              Icons.help_outline, 
                              (item, ans) => ans == null
                            ),
                          ),

                        // Doğrular
                        if (correctCount > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: _buildReviewBtn(
                              context, 
                              'Doğruları İncele ($correctCount)', 
                              Colors.green, 
                              Icons.check_circle_outline, 
                              (item, ans) => ans == item.correct
                            ),
                          ),
                      ],
                    ),
                  ),
                  
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Bölüm Analizi',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                   const Text(
                    'Detaylar için bölümlere tıkla',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  ...sectionResults.entries.map((entry) {
                    final sectionName = entry.key;
                    final stats = entry.value;
                    final percentage = (stats.correct / stats.total);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        onTap: () {
                           // Navigate to review this specific section
                            final section = examBundle.sections.firstWhere((s) => s.name == sectionName);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ExamReviewPage(
                                  items: section.items,
                                  userAnswers: userAnswers,
                                  title: sectionName,
                                ),
                              ),
                            );
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    sectionName.toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Text(
                                        '${stats.correct} / ${stats.total}',
                                        style: const TextStyle(color: Colors.white70),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.chevron_right, color: Colors.white54),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: percentage,
                                backgroundColor: Colors.white10,
                                valueColor: AlwaysStoppedAnimation(
                                  percentage > 0.7 ? Colors.green : (percentage > 0.4 ? Colors.amber : Colors.red),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                  
                  const SizedBox(height: 32),
                  
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context), 
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.white54),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Kapat', style: TextStyle(color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: color.withOpacity(0.7),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  // Helper for Review Buttons
  Widget _buildReviewBtn(
    BuildContext context, 
    String label, 
    Color color, 
    IconData icon, 
    bool Function(ExamItem, String?) filter
  ) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          final filteredItems = <ExamItem>[];
          final originalIndices = <int>[];
          
          int globalIndex = 0;
          for (var section in examBundle.sections) {
            for (var item in section.items) {
              final ans = userAnswers[item.id];
              if (filter(item, ans)) {
                filteredItems.add(item);
                originalIndices.add(globalIndex);
              }
              globalIndex++;
            }
          }
          
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ExamReviewPage(
                items: filteredItems,
                userAnswers: userAnswers,
                title: label,
                originalIndices: originalIndices,
              ),
            ),
          );
        },
        icon: Icon(icon, color: Colors.white),
        label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 16)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}

class _SectionResult {
  final int correct;
  final int total;
  _SectionResult(this.correct, this.total);
}

