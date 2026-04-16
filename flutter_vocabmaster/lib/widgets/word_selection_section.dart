import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../widgets/modern_card_container.dart';
import '../widgets/modern_card.dart';
import '../widgets/modern_background.dart';

class WordSelectionSection extends StatelessWidget {
  const WordSelectionSection({super.key});

  @override
  Widget build(BuildContext context) {
    return ModernCardContainer(
      title: 'Kelime Seçimi',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search Input
          _buildSearchInput(),
          
          const SizedBox(height: 16),
          
          // Word List Header
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Kelime Listesi:',
                style: TextStyle(
                  color: AppColors.textSlate200,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '0 seçili',
                style: TextStyle(
                  color: AppColors.cardBorderCyan,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Word List
          _buildWordList(context),
          
          const SizedBox(height: 16),
          
          // Başla Button
          _buildStartButton(),
        ],
      ),
    );
  }

  Widget _buildSearchInput() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackgroundMedium.withOpacity(0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.cardBorderBlue.withOpacity(0.3),
          width: 1.2,
        ),
      ),
      child: TextField(
        style: const TextStyle(
          color: AppColors.textWhite,
          fontSize: 14,
        ),
        decoration: InputDecoration(
          hintText: 'Kelime veya çeviriyi girin',
          hintStyle: TextStyle(
            color: AppColors.textSlate400.withOpacity(0.6),
            fontSize: 14,
          ),
          prefixIcon: Icon(
            Icons.search,
            color: AppColors.textSlate400.withOpacity(0.6),
            size: 20,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildWordList(BuildContext context) {
    final words = [
      {'word': 'Debunk', 'translation': 'Çürütmek', 'difficulty': 'HARD'},
      {'word': 'hello', 'translation': 'merhaba', 'difficulty': 'EASY'},
      {'word': 'Serendipity', 'translation': 'Şans eseri güzel rastlantı', 'difficulty': 'HARD'},
      {'word': 'deneme', 'translation': '', 'difficulty': 'EASY'},
    ];
    
    return Column(
      children: words.map((word) => _buildWordItem(context, word)).toList(),
    );
  }

  Widget _buildWordItem(BuildContext context, Map<String, String> word) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBackgroundMedium.withOpacity(0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.cardBorderBlue.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Radio button
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.textSlate400.withOpacity(0.6),
                width: 2,
              ),
            ),
          ),
          
          const SizedBox(width: 12),
          
          // Word info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (word['word'] == 'Debunk' || word['word'] == 'Serendipity')
                      const Icon(
                        Icons.star,
                        color: Colors.orange,
                        size: 14,
                      ),
                    if (word['word'] == 'Debunk' || word['word'] == 'Serendipity')
                      const SizedBox(width: 4),
                    Text(
                      word['word']!,
                      style: const TextStyle(
                        color: AppColors.textWhite,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (word['word'] == 'hello' || word['word'] == 'Serendipity' || word['word'] == 'deneme')
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.cardBorderCyan.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Word',
                          style: TextStyle(
                            color: AppColors.cardBorderCyan,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                if (word['translation']!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    word['translation']!,
                    style: TextStyle(
                      color: AppColors.textSlate400.withOpacity(0.8),
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          // Difficulty badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: word['difficulty'] == 'HARD' 
                  ? Colors.red.withOpacity(0.2)
                  : Colors.green.withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              word['difficulty']!,
              style: TextStyle(
                color: word['difficulty'] == 'HARD' 
                    ? Colors.red.shade300
                    : Colors.green.shade300,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          
          const SizedBox(width: 8),
          
          // Info button
          GestureDetector(
            onTap: () => _showWordDetailDialog(context, word),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.cardBorderCyan.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.info_outline,
                color: AppColors.cardBorderCyan,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStartButton() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xFF06B6D4), // cyan-500
            Color(0xFF22D3EE), // cyan-400
          ],
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: AppColors.cardBorderCyan.withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Başla',
            style: TextStyle(
              color: AppColors.textWhite,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(width: 8),
          Icon(
            Icons.arrow_forward,
            color: AppColors.textWhite,
            size: 18,
          ),
        ],
      ),
    );
  }

  void _showWordDetailDialog(BuildContext context, Map<String, String> word) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40),
        child: ModernCard(
          variant: BackgroundVariant.primary,
          borderRadius: BorderRadius.circular(20),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
               Row(
                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
                 children: [
                   Text(
                     word['word']!,
                     style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                   ),
                   IconButton(
                     icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                     onPressed: () => Navigator.pop(context),
                     padding: EdgeInsets.zero,
                     constraints: const BoxConstraints(),
                   )
                 ],
               ),
               const SizedBox(height: 8),
               Text(
                 word['translation']!,
                 style: const TextStyle(color: Color(0xFF22D3EE), fontSize: 18, fontWeight: FontWeight.w500),
               ),
               const SizedBox(height: 16),
               Container(
                 padding: const EdgeInsets.all(12),
                 decoration: BoxDecoration(
                   color: Colors.white.withOpacity(0.05),
                   borderRadius: BorderRadius.circular(12),
                 ),
                 child: Column(
                   children: [
                     Row(
                       mainAxisAlignment: MainAxisAlignment.spaceBetween,
                       children: [
                         const Text('Seviye', style: TextStyle(color: Colors.white70)),
                         Text(word['difficulty']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                       ],
                     ),
                     Divider(color: Colors.white.withOpacity(0.1), height: 16),
                     const Row(
                       mainAxisAlignment: MainAxisAlignment.spaceBetween,
                       children: [
                         Text('Eklendiği Tarih', style: TextStyle(color: Colors.white70, fontSize: 12)),
                         Text('2026-01-13', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                       ],
                     ),
                   ],
                 ),
               ),
               const SizedBox(height: 20),
               GestureDetector(
                onTap: () => Navigator.pop(context),
                child: ModernCard(
                  variant: BackgroundVariant.accent,
                  borderRadius: BorderRadius.circular(12),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  showGlow: true,
                  child: const Center(
                    child: Text('Kapat', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
               ),
            ],
          ),
        ),
      ),
    );
  }
}

