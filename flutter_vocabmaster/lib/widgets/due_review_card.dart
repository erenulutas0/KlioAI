import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/locale_text_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_catalog.dart';
import '../theme/theme_provider.dart';

/// Home card surfacing the backend SM-2 SRS "due today" count.
///
/// The SRS engine has computed due dates all along (`GET /api/srs/stats`),
/// but nothing in the UI ever showed them — this card is the daily-return
/// hook. Renders nothing when no reviews are due.
class DueReviewCard extends StatelessWidget {
  const DueReviewCard({
    super.key,
    required this.dueCount,
    required this.onTap,
  });

  final int dueCount;
  final VoidCallback onTap;

  AppThemeConfig _theme(BuildContext context) {
    try {
      return Provider.of<ThemeProvider?>(context)?.currentTheme ??
          VocabThemes.defaultTheme;
    } catch (_) {
      return VocabThemes.defaultTheme;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (dueCount <= 0) {
      return const SizedBox.shrink();
    }

    final isTurkish = LocaleTextService.isTurkish;
    final theme = _theme(context);
    final title = isTurkish
        ? '$dueCount kelime tekrar bekliyor'
        : dueCount == 1
            ? '1 word due for review'
            : '$dueCount words due for review';
    final subtitle = isTurkish
        ? 'Kisa bir tekrar hafizani taze tutar'
        : 'A quick review keeps your memory fresh';

    return InkWell(
      key: const ValueKey('home-due-review-card'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colors.accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colors.accent.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colors.accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.replay_rounded, color: theme.colors.accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }
}
