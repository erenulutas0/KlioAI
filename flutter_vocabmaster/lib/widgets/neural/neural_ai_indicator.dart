import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import '../../theme/theme_catalog.dart';
import '../../theme/theme_provider.dart';

class NeuralAiIndicator extends StatefulWidget {
  const NeuralAiIndicator({super.key});

  @override
  State<NeuralAiIndicator> createState() => _NeuralAiIndicatorState();
}

class _NeuralAiIndicatorState extends State<NeuralAiIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedTheme = _currentTheme(context);
    return FadeTransition(
      opacity: Tween<double>(begin: 0.55, end: 1.0).animate(_controller),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          color: selectedTheme.colors.accent.withOpacity(0.14),
          border: Border.all(
            color: selectedTheme.colors.accent.withOpacity(0.5),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.memory, color: selectedTheme.colors.accent, size: 14),
            const SizedBox(width: 6),
            const Text(
              'AI Assistant Active',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  AppThemeConfig _currentTheme(BuildContext context) {
    try {
      return Provider.of<ThemeProvider?>(context, listen: true)?.currentTheme ??
          VocabThemes.defaultTheme;
    } catch (_) {
      return VocabThemes.defaultTheme;
    }
  }
}
