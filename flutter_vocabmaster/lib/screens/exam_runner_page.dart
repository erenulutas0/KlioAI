import 'dart:async';
import 'package:flutter/material.dart';
import '../models/exam_models.dart';
import '../widgets/animated_background.dart';
import 'exam_result_page.dart';

class ExamRunnerPage extends StatefulWidget {
  final ExamBundle examBundle;

  const ExamRunnerPage({super.key, required this.examBundle});

  @override
  State<ExamRunnerPage> createState() => _ExamRunnerPageState();
}

class _ExamRunnerPageState extends State<ExamRunnerPage> {
  // Flattened list of all items for easier navigation
  late List<ExamItem> _allItems;
  // Map of QuestionID -> SelectedOption (A/B/C/D/E)
  final Map<String, String> _answers = {};
  
  int _currentIndex = 0;
  late Timer _timer;
  late int _remainingSeconds;

  @override
  void initState() {
    super.initState();
    _flattenItems();
    _remainingSeconds = widget.examBundle.meta.timeLimitMinutes * 60;
    _startTimer();
  }

  void _flattenItems() {
    _allItems = [];
    for (var section in widget.examBundle.sections) {
      _allItems.addAll(section.items);
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        _finishExam();
      }
    });
  }

  void _finishExam() {
    _timer.cancel();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ExamResultPage(
          examBundle: widget.examBundle,
          userAnswers: _answers,
          timeElapsedSeconds: (widget.examBundle.meta.timeLimitMinutes * 60) - _remainingSeconds,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String _formatTime(int totalSeconds) {
    int hours = totalSeconds ~/ 3600;
    int minutes = (totalSeconds % 3600) ~/ 60;
    int seconds = totalSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _showFinishConfirmation() {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Sınavı Bitir?', style: TextStyle(color: Colors.white)),
        content: const Text('Emin misiniz? Geri dönüşü yoktur.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('İptal')),
          TextButton(onPressed: () { Navigator.pop(c); _finishExam(); }, child: const Text('Bitir', style: TextStyle(color: Colors.red))),
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_allItems.isEmpty) {
      return const Scaffold(body: Center(child: Text("Hata: Soru bulunamadı.")));
    }

    final currentItem = _allItems[_currentIndex];
    final currentSection = widget.examBundle.sections.firstWhere(
      (s) => s.items.contains(currentItem),
      orElse: () => widget.examBundle.sections.first,
    );

    // Resolve active passage (sticky logic)
    String? activePassage = currentItem.passage;
    if (activePassage == null || activePassage.isEmpty) {
      // Look backwards in the same section
      for (int i = _currentIndex - 1; i >= 0; i--) {
        final prevItem = _allItems[i];
        // Check if prevItem is in the same section
        if (!currentSection.items.contains(prevItem)) break; 
        
        if (prevItem.passage != null && prevItem.passage!.isNotEmpty) {
          activePassage = prevItem.passage;
          break;
        }
      }
    }

    return Scaffold(
      body: Stack(
        children: [
          const AnimatedBackground(isDark: true),
          SafeArea(
            child: Column(
              children: [
                // TOP BAR
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: Colors.black26,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.timer, color: Colors.amber, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            _formatTime(_remainingSeconds),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${_currentIndex + 1} / ${_allItems.length}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      TextButton(
                        onPressed: _showFinishConfirmation,
                        child: const Text('Bitir', style: TextStyle(color: Colors.redAccent)),
                      )
                    ],
                  ),
                ),
                
                // PROGRESS BAR
                LinearProgressIndicator(
                  value: (_currentIndex + 1) / _allItems.length,
                  backgroundColor: Colors.white10,
                  valueColor: const AlwaysStoppedAnimation(Colors.blue),
                ),

                // CONTENT
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // SECTION HEADER
                        Text(
                          currentSection.name.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            letterSpacing: 2,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // PASSAGE (If exists)
                        if (activePassage != null && activePassage.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: Text(
                              activePassage,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                height: 1.6,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],

                        // QUESTION STEM
                        Text(
                          currentItem.stem,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 32),

                        // OPTIONS
                        ...['A', 'B', 'C', 'D', 'E'].map((optionLabel) {
                          final optionText = currentItem.options[optionLabel];
                          if (optionText == null || optionText.isEmpty) return const SizedBox.shrink();

                          final isSelected = _answers[currentItem.id] == optionLabel;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildOption(
                              label: optionLabel,
                              text: optionText,
                              isSelected: isSelected,
                              onTap: () {
                                setState(() {
                                  _answers[currentItem.id] = optionLabel;
                                });
                              },
                            ),
                          );
                        }),

                      ],
                    ),
                  ),
                ),

                // NAVIGATION BAR
                Container(
                  padding: const EdgeInsets.all(16),
                  color: const Color(0xFF0F172A),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ElevatedButton(
                        onPressed: _currentIndex > 0 
                            ? () => setState(() => _currentIndex--) 
                            : null,
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[800]),
                        child: const Icon(Icons.arrow_back),
                      ),
                      
                      // Quick Nav Grid (Optional, keep simple for now)
                      
                      ElevatedButton(
                        onPressed: _currentIndex < _allItems.length - 1
                            ? () => setState(() => _currentIndex++)
                            : _showFinishConfirmation,
                         style: ElevatedButton.styleFrom(
                           backgroundColor: _currentIndex == _allItems.length - 1 ? Colors.redAccent : const Color(0xFF0ea5e9),
                           padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                         ),
                        child: Text(
                          _currentIndex == _allItems.length - 1 ? 'Bitir' : 'Sonraki',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOption({
    required String label,
    required String text,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0ea5e9).withOpacity(0.2) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF0ea5e9) : Colors.white.withOpacity(0.1),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF0ea5e9) : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? Colors.transparent : Colors.white54,
                ),
              ),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white54,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

