import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class ModernCardContainer extends StatelessWidget {
  final Widget child;
  final String? title;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  const ModernCardContainer({
    super.key,
    required this.child,
    this.title,
    this.padding,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        // ⭐ ÇOK ÖNEMLİ: Solid color kullan, gradient değil!
        color: AppColors.cardBackgroundDark, // #0A1628
        
        // Border radius
        borderRadius: BorderRadius.circular(16),
        
        // Border (cyan, 0.4-0.5 opacity)
        border: Border.all(
          color: AppColors.cardBorderCyan.withOpacity(0.45),
          width: 1.5,
        ),
        
        // Shadow (daha koyu ve belirgin)
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowDark.withOpacity(0.6),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
          // İkinci shadow (depth için)
          BoxShadow(
            color: AppColors.cardBorderCyan.withOpacity(0.1),
            blurRadius: 12,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title varsa göster
          if (title != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Text(
                title!,
                style: const TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
          
          // Content
          Padding(
            padding: padding ?? const EdgeInsets.all(24),
            child: child,
          ),
        ],
      ),
    );
  }
}

