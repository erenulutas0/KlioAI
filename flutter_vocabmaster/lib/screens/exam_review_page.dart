import 'package:flutter/material.dart';
import '../models/exam_models.dart';
import '../widgets/animated_background.dart';

class ExamReviewPage extends StatefulWidget {
  final List<ExamItem> items;
  final Map<String, String> userAnswers;
  final String title;
  final List<int>? originalIndices;

  const ExamReviewPage({
    super.key,
    required this.items,
    required this.userAnswers,
    required this.title,
    this.originalIndices,
  });

  @override
  State<ExamReviewPage> createState() => _ExamReviewPageState();
}

class _ExamReviewPageState extends State<ExamReviewPage> {
  late PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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
                // AppBar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              widget.originalIndices != null
                                  ? 'Soru ${widget.originalIndices![_currentIndex] + 1} (Toplam: ${widget.items.length})'
                                  : 'Soru ${_currentIndex + 1} / ${widget.items.length}',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: widget.items.length,
                    onPageChanged: (index) {
                      setState(() {
                        _currentIndex = index;
                      });
                    },
                    itemBuilder: (context, index) {
                      return _buildReviewItem(widget.items[index]);
                    },
                  ),
                ),
                
                // Bottom Navigation
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.black26,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: _currentIndex > 0
                            ? () {
                                _pageController.previousPage(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                );
                              }
                            : null,
                        icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                      ),
                       IconButton(
                        onPressed: _currentIndex < widget.items.length - 1
                            ? () {
                                _pageController.nextPage(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                );
                              }
                            : null,
                        icon: const Icon(Icons.arrow_forward_ios, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewItem(ExamItem item) {
    final userAnswer = widget.userAnswers[item.id];
    
    // Resolve passage if necessary (though strictly we would need the full context logic here too, 
    // for simplicity we assume passage is on the item or we display just the question)
    // Ideally we pass 'activePassage' but let's see if item has passage
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.passage != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Text(
                item.passage!,
                style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5),
              ),
            ),
          ],
          
          Text(
            item.stem,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),
          
          ...['A', 'B', 'C', 'D', 'E'].map((optionLabel) {
            final optionText = item.options[optionLabel];
            if (optionText == null) return const SizedBox.shrink();

            Color borderColor = Colors.white10;
            Color bgColor = Colors.transparent;
            Color textColor = Colors.white70;

            if (optionLabel == item.correct) {
              borderColor = Colors.green;
              bgColor = Colors.green.withOpacity(0.2);
              textColor = Colors.white;
            } else if (optionLabel == userAnswer) {
              borderColor = Colors.red;
              bgColor = Colors.red.withOpacity(0.2);
              textColor = Colors.white;
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: 1.5),
              ),
              child: Row(
                children: [
                  Text(
                    '$optionLabel)',
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      optionText,
                      style: TextStyle(color: textColor),
                    ),
                  ),
                  if (optionLabel == item.correct)
                    const Icon(Icons.check_circle, color: Colors.green)
                  else if (optionLabel == userAnswer)
                    const Icon(Icons.cancel, color: Colors.red),
                ],
              ),
            );
          }),
          
          const SizedBox(height: 24),
          
          if (item.explanationTr != null || item.explanationEn != null) ...[
             Container(
               padding: const EdgeInsets.all(16),
               decoration: BoxDecoration(
                 color: const Color(0xFF0F172A),
                 borderRadius: BorderRadius.circular(12),
                 border: Border.all(color: Colors.amber.withOpacity(0.3)),
               ),
               child: Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                   const Row(
                     children: [
                       Icon(Icons.lightbulb, color: Colors.amber, size: 20),
                       SizedBox(width: 8),
                       Text('Açıklama', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                     ],
                   ),
                   const SizedBox(height: 8),
                   if (item.explanationTr != null)
                     Text(item.explanationTr!, style: const TextStyle(color: Colors.white70)),
                   if (item.explanationEn != null) ...[
                      const SizedBox(height: 8),
                      Text(item.explanationEn!, style: const TextStyle(color: Colors.white54, fontStyle: FontStyle.italic)),
                   ]
                 ],
               ),
             )
          ]
        ],
      ),
    );
  }
}

