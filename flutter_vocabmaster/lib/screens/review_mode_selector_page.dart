import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/word.dart';
import '../theme/app_theme.dart';
import '../theme/theme_catalog.dart';
import '../theme/theme_provider.dart';
import '../widgets/modern_background.dart';
import '../widgets/modern_card.dart';
import 'repeat_page.dart';
import 'word_galaxy_page.dart';

class ReviewModeSelectorPage extends StatelessWidget {
  const ReviewModeSelectorPage({
    super.key,
    this.focusedWord,
  });

  final Word? focusedWord;

  bool _isTurkish(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'tr';

  String _text(BuildContext context, String tr, String en) =>
      _isTurkish(context) ? tr : en;

  AppThemeConfig _theme(BuildContext context) {
    try {
      return Provider.of<ThemeProvider?>(context, listen: true)?.currentTheme ??
          VocabThemes.defaultTheme;
    } catch (_) {
      return VocabThemes.defaultTheme;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme(context);
    final accent = theme.colors.accent;
    final focusLabel = focusedWord?.englishWord;

    return Scaffold(
      body: Stack(
        children: [
          const ModernBackground(),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _text(context, 'Tekrar Sec', 'Choose Review'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    focusLabel == null
                        ? _text(
                            context,
                            'Klasik kart tekrarini veya neural kelime agini sec.',
                            'Choose the classic flashcard review or the neural word map.',
                          )
                        : _text(
                            context,
                            '$focusLabel icin hangi tekrar modunu acmak istiyorsun?',
                            'Choose which review mode to open for $focusLabel.',
                          ),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  if (focusLabel != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: accent.withOpacity(0.22)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.center_focus_strong_rounded,
                              color: accent, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              focusLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  _ReviewModeCard(
                    title: _text(context, 'Klasik Tekrar', 'Classic Review'),
                    subtitle: _text(
                      context,
                      'Kart kart ilerle, sesi dinle ve bildigini isaretle.',
                      'Move card by card, listen to audio, and mark words you know.',
                    ),
                    icon: Icons.style_rounded,
                    accentColor: const Color(0xFF67E8F9),
                    buttonLabel: _text(
                        context, 'Klasik Tekrari Ac', 'Open Classic Review'),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              RepeatPage(initialWordId: focusedWord?.id),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  _ReviewModeCard(
                    title: _text(context, 'Neural Tekrar', 'Neural Review'),
                    subtitle: _text(
                      context,
                      'Kelime aginda gez, cumleleri gor ve AI ile yeni ornekler uret.',
                      'Explore the word graph, see sentences, and generate new examples with AI.',
                    ),
                    icon: Icons.hub_rounded,
                    accentColor: const Color(0xFFF59E0B),
                    buttonLabel: _text(
                        context, 'Neural Tekrari Ac', 'Open Neural Review'),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              WordGalaxyPage(initialWordId: focusedWord?.id),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewModeCard extends StatelessWidget {
  const _ReviewModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.buttonLabel,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final String buttonLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ModernCard(
      borderRadius: BorderRadius.circular(8),
      padding: const EdgeInsets.all(18),
      variant: BackgroundVariant.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: accentColor),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.black,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(
                buttonLabel,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
