import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/theme_catalog.dart';
import '../theme/theme_provider.dart';

class NeonButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool isCyan; // true for cyan, false for blue
  final VoidCallback onTap;

  const NeonButton({
    super.key,
    required this.label,
    required this.icon,
    required this.isCyan,
    required this.onTap,
  });

  @override
  State<NeonButton> createState() => _NeonButtonState();
}

class _NeonButtonState extends State<NeonButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    ThemeProvider? themeProvider;
    try {
      themeProvider = Provider.of<ThemeProvider?>(context, listen: true);
    } catch (_) {
      themeProvider = null;
    }
    final selectedTheme =
        themeProvider?.currentTheme ?? VocabThemes.defaultTheme;

    final baseA = widget.isCyan
        ? selectedTheme.colors.primary
        : selectedTheme.colors.accent;
    final baseB = widget.isCyan
        ? selectedTheme.colors.accent
        : selectedTheme.colors.primary;

    final primaryColor = baseA.withOpacity(0.24);
    final secondaryColor = baseB.withOpacity(0.18);
    final borderColor = Color.lerp(baseA, Colors.white, 0.20) ?? baseA;
    final glowColor =
        Color.lerp(baseB, selectedTheme.colors.accentGlow, 0.55) ?? baseB;
    final textColor = Color.lerp(baseA, Colors.white, 0.36) ?? baseA;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        height: 44,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [primaryColor, secondaryColor],
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _isHovered ? borderColor : borderColor.withOpacity(0.5),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: _isHovered
                  ? glowColor.withOpacity(0.6)
                  : glowColor.withOpacity(0.3),
              blurRadius: _isHovered ? 25 : 15,
              spreadRadius: 0,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
            child: Stack(
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: widget.onTap,
                    splashColor: glowColor.withOpacity(0.2),
                    highlightColor: glowColor.withOpacity(0.1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            widget.icon,
                            size: 16,
                            color: _isHovered ? Colors.white : textColor,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            widget.label,
                            style: TextStyle(
                              color: _isHovered ? Colors.white : textColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Gradient sweep overlay
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 300),
                  opacity: _isHovered ? 1.0 : 0.0,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            glowColor.withOpacity(0.0),
                            glowColor.withOpacity(0.2),
                            glowColor.withOpacity(0.0),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

