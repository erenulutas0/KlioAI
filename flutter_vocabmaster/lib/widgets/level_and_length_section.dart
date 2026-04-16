import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'modern_card.dart';
import 'modern_background.dart';

class LevelAndLengthSection extends StatelessWidget {
  final String selectedLevel;
  final String selectedLength;
  final Function(String) onLevelChanged;
  final Function(String) onLengthChanged;

  const LevelAndLengthSection({
    super.key,
    required this.selectedLevel,
    required this.selectedLength,
    required this.onLevelChanged,
    required this.onLengthChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ModernCard(
      borderRadius: BorderRadius.circular(20),
      variant: BackgroundVariant.primary,
      showGlow: true,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('practice.translation.levelLengthTitle'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),

          Text(
            context.tr('practice.translation.levelLabel'),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Colors.white70,
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Level buttons grid
          SizedBox(
            height: 100,
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 2.0,
              ),
              itemCount: 6,
              itemBuilder: (context, index) {
                final levels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];
                final level = levels[index];
                final isSelected = selectedLevel == level;
                
                return GestureDetector(
                  onTap: () => onLevelChanged(level),
                  child: ModernCard(
                    borderRadius: BorderRadius.circular(16),
                    variant: isSelected ? BackgroundVariant.accent : BackgroundVariant.secondary,
                    showGlow: isSelected,
                    padding: EdgeInsets.zero,
                    child: Center(
                      child: Text(
                        level,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontSize: 16,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          
          const SizedBox(height: 20),
          
          Text(
            context.tr('practice.translation.lengthLabel'),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Colors.white70,
            ),
          ),
          
          const SizedBox(height: 12),
          
          _buildLengthOption(
            context: context,
            label: context.tr('practice.translation.length.short'),
            value: 'short',
          ),
          const SizedBox(height: 12),
          _buildLengthOption(
            context: context,
            label: context.tr('practice.translation.length.medium'),
            value: 'medium',
          ),
          const SizedBox(height: 12),
          _buildLengthOption(
            context: context,
            label: context.tr('practice.translation.length.long'),
            value: 'long',
          ),
        ],
      ),
    );
  }

  Widget _buildLengthOption({
    required BuildContext context,
    required String label,
    required String value,
  }) {
    final isSelected = selectedLength == value;
    return GestureDetector(
      onTap: () => onLengthChanged(value),
      child: ModernCard(
        width: double.infinity,
        borderRadius: BorderRadius.circular(16),
        variant: isSelected ? BackgroundVariant.accent : BackgroundVariant.secondary,
        showGlow: isSelected,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        child: Row(
          children: [
            if (isSelected) ...[
              const Icon(
                Icons.check_circle,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 15,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

