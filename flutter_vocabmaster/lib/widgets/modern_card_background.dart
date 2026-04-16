import 'package:flutter/material.dart';
import 'dart:ui'; // For ImageFilter

class ModernCardBackground extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin; // Added margin support
  final double borderRadius;
  final bool useBlur; // Blur kullanılsın mı?

  const ModernCardBackground({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 24.0, // Increased to 24 to match ModernCard
    this.useBlur = true, // Default true for premium look
  });

  @override
  Widget build(BuildContext context) {
    // Determine content with padding
    final contentWithPadding = Padding(
      padding: padding ?? const EdgeInsets.all(24),
      child: child,
    );

    // If using blur, we need a transparent container with ClipRRect -> BackdropFilter -> Decoration
    // But standard Glassmorphism usually places decoration with opacity + BackdropFilter.
    
    // Structure matching ModernCard more closely:
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
             color: Colors.black.withOpacity(0.3),
             blurRadius: 20,
             offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
             decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(borderRadius),
                border: Border.all(
                  color: const Color(0xFF06B6D4).withOpacity(0.2), // cyan-400/20
                  width: 1,
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF1E293B).withOpacity(0.6), // slate-800/60
                    const Color(0xFF0F1F3D).withOpacity(0.8), // slate-900/80
                  ],
                ),
             ),
             child: contentWithPadding,
          ),
        ),
      ),
    );
  }
}

