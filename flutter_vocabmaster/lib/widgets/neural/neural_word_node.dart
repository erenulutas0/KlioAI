import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import '../../theme/theme_catalog.dart';
import '../../theme/theme_provider.dart';

class NeuralWordNode extends StatefulWidget {
  final String word;
  final String? subtitle;
  final Offset position;
  final int index;

  const NeuralWordNode({
    super.key,
    required this.word,
    this.subtitle,
    required this.position,
    required this.index,
  });

  @override
  State<NeuralWordNode> createState() => _NeuralWordNodeState();
}

class _NeuralWordNodeState extends State<NeuralWordNode>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );

    Future<void>.delayed(Duration(milliseconds: widget.index * 80), () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedTheme = _currentTheme(context);
    return Positioned(
      left: widget.position.dx - 64,
      top: widget.position.dy - 24,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          constraints: const BoxConstraints(minWidth: 110, maxWidth: 140),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                selectedTheme.colors.primary.withOpacity(0.35),
                selectedTheme.colors.accent.withOpacity(0.30),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selectedTheme.colors.accent.withOpacity(0.45),
            ),
            boxShadow: [
              BoxShadow(
                color: selectedTheme.colors.accentGlow.withOpacity(0.28),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.word.toUpperCase(),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
              if (widget.subtitle != null &&
                  widget.subtitle!.trim().isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  widget.subtitle!.toUpperCase(),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xB3FFFFFF),
                    fontWeight: FontWeight.w500,
                    fontSize: 10,
                  ),
                ),
              ],
            ],
          ),
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
