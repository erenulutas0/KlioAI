import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/theme_catalog.dart';
import '../theme/theme_provider.dart';

class DailyWordCard extends StatefulWidget {
  final Map<String, dynamic> wordData;
  final VoidCallback onTap;
  final VoidCallback? onQuickAdd;
  final VoidCallback? onAddSentence;
  final bool isWordAdded;
  final bool isSentenceAdded;
  final int index;

  const DailyWordCard({
    super.key,
    required this.wordData,
    required this.onTap,
    required this.isWordAdded,
    required this.isSentenceAdded,
    required this.index,
    this.onQuickAdd,
    this.onAddSentence,
  });

  @override
  State<DailyWordCard> createState() => _DailyWordCardState();
}

class _DailyWordCardState extends State<DailyWordCard> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _rotationController;
  late AnimationController _tapController;
  Timer? _pulseStartTimer;

  @override
  void initState() {
    super.initState();
    // Pulse Animation (Word)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    
    // Stagger start based on index
    _pulseStartTimer = Timer(Duration(milliseconds: 200 * widget.index), () {
      if (mounted) _pulseController.repeat(reverse: true);
    });

    // Rotation Animation (Sparkle)
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    // Tap Animation
    _tapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.0,
      upperBound: 0.05,
    );
  }

  @override
  void dispose() {
    _pulseStartTimer?.cancel();
    _pulseController.dispose();
    _rotationController.dispose();
    _tapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedTheme = _currentTheme();
    // Determine colors based on difficulty
    final difficulty = (widget.wordData['difficulty'] as String? ?? 'Medium').toLowerCase();
    Color badgeColor;
    Color badgeBgColor;
    Color badgeBorderColor;

    switch (difficulty) {
      case 'easy':
        badgeColor = const Color(0xFF4ADE80); // Green-400
        badgeBgColor = const Color(0x3322C55E); // Green-500 alpha
        badgeBorderColor = const Color(0x4D4ADE80);
        break;
      case 'hard':
        badgeColor = const Color(0xFFF87171); // Red-400
        badgeBgColor = const Color(0x33EF4444); // Red-500 alpha
        badgeBorderColor = const Color(0x4DF87171);
        break;
      case 'medium':
      default:
        badgeColor = const Color(0xFFFACC15); // Yellow-400
        badgeBgColor = const Color(0x33EAB308); // Yellow-500 alpha
        badgeBorderColor = const Color(0x4DFACC15);
        break;
    }

    return AnimatedBuilder(
      animation: _tapController,
      builder: (context, child) {
        final fullyAdded = widget.isWordAdded && widget.isSentenceAdded;
        return Transform.scale(
          scale: 1.0 - _tapController.value,
          child: GestureDetector(
            onTapDown: (_) => _tapController.forward(),
            onTapUp: (_) {
               _tapController.reverse();
               widget.onTap();
            },
            onTapCancel: () => _tapController.reverse(),
            child: Container(
              width: 140,
              height: 180,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: fullyAdded
                      ? [
                          selectedTheme.colors.primary.withOpacity(0.18),
                          selectedTheme.colors.accent.withOpacity(0.18),
                        ]
                      : [
                          selectedTheme.colors.accent.withOpacity(0.20),
                          selectedTheme.colors.primary.withOpacity(0.20),
                        ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: selectedTheme.colors.glassBorder.withOpacity(0.9),
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: selectedTheme.colors.accentGlow.withOpacity(0.32),
                    blurRadius: 12,
                    spreadRadius: 2,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Stack(
                children: [
                   ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Difficulty Badge
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: badgeBgColor,
                                  border: Border.all(color: badgeBorderColor),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  difficulty.toUpperCase(),
                                  style: TextStyle(
                                    color: badgeColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            
                            // Word with Pulse Animation
                            AnimatedBuilder(
                              animation: _pulseController,
                              builder: (context, child) {
                                return Transform.scale(
                                  scale: 1.0 + (_pulseController.value * 0.1),
                                  child: child,
                                );
                              },
                              child: Text(
                                widget.wordData['word'] ?? '',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),

                            // Translation
                            Text(
                              widget.wordData['translation'] ?? '',
                              style: const TextStyle(
                                color: Color(0xB3FFFFFF),
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),

                            // Sparkles Icon with Rotation
                            RotationTransition(
                              turns: _rotationController,
                              child: Icon(
                                Icons.auto_awesome, 
                                color: selectedTheme.colors.accent, 
                                size: 16
                              ),
                            ),

                            if (widget.isWordAdded && !widget.isSentenceAdded)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: GestureDetector(
                                  onTap: widget.onAddSentence,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: selectedTheme.colors.primary.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: selectedTheme.colors.primary
                                            .withOpacity(0.5),
                                      ),
                                    ),
                                    child: Text(
                                      context.tr('home.card.addSentence'),
                                      style: TextStyle(
                                        color: selectedTheme.colors.primary,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                            if (widget.isWordAdded && widget.isSentenceAdded)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: selectedTheme.colors.primary.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: selectedTheme.colors.primary
                                          .withOpacity(0.4),
                                    ),
                                  ),
                                  child: Text(
                                    context.tr('home.card.wordSentenceAdded'),
                                    style: TextStyle(
                                      color: selectedTheme.colors.primary,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  
                  // Quick Add Button
                  if (!widget.isWordAdded)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: widget.onQuickAdd,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withOpacity(0.2)),
                          ),
                          child: const Icon(Icons.add, color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  AppThemeConfig _currentTheme() {
    try {
      return Provider.of<ThemeProvider?>(context, listen: true)?.currentTheme ??
          VocabThemes.defaultTheme;
    } catch (_) {
      return VocabThemes.defaultTheme;
    }
  }
}

