import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/language_provider.dart';
import '../screens/onboarding_screen.dart';
import '../theme/app_theme.dart';
import '../theme/theme_catalog.dart';
import '../theme/theme_provider.dart';
import '../widgets/animated_background.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  AppThemeConfig _currentTheme(BuildContext context, {required bool listen}) {
    try {
      return Provider.of<ThemeProvider?>(context, listen: listen)?.currentTheme ??
          VocabThemes.defaultTheme;
    } catch (_) {
      return VocabThemes.defaultTheme;
    }
  }

  String _languageLabel(BuildContext context, String code) {
    switch (code) {
      case 'tr':
        return context.tr('language.turkish');
      case 'de':
        return context.tr('language.german');
      case 'ar':
        return context.tr('language.arabic');
      case 'zh':
        return context.tr('language.chinese');
      default:
        return context.tr('language.english');
    }
  }

  Future<void> _showLanguageSheet(BuildContext context) async {
    final provider = context.read<LanguageProvider>();
    final current = provider.locale.languageCode;
    final selectedTheme = _currentTheme(context, listen: false);
    final l10n = context.l10n;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.t('settings.language.sheetTitle'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                ...AppLocalizations.supportedLocales.map((locale) {
                  final code = locale.languageCode;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      current == code
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: current == code ? selectedTheme.colors.accent : Colors.white70,
                    ),
                    title: Text(
                      _languageLabel(context, code),
                      style: const TextStyle(color: Colors.white),
                    ),
                    onTap: () async {
                      await provider.selectLanguage(locale);
                      if (!context.mounted || !sheetContext.mounted) {
                        return;
                      }
                      Navigator.of(sheetContext).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.t('language.changed'))),
                      );
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedTheme = _currentTheme(context, listen: true);
    final languageCode = context.watch<LanguageProvider>().locale.languageCode;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('settings.title')),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: AnimatedBackground(isDark: true)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.tr('settings.subtitle'),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.75),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selectedTheme.colors.glassBorder.withOpacity(0.65),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('settings.language.title'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        context.tr('settings.language.subtitle'),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${context.tr('settings.language.current')}: ${_languageLabel(context, languageCode)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => _showLanguageSheet(context),
                            icon: const Icon(Icons.language),
                            label: Text(context.tr('settings.language.sheetTitle')),
                            style: TextButton.styleFrom(
                              foregroundColor: selectedTheme.colors.accent,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selectedTheme.colors.glassBorder.withOpacity(0.55),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('settings.tour.title'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        context.tr('settings.tour.subtitle'),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.72),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const OnboardingScreen(fromSettings: true),
                              ),
                            );
                          },
                          icon: const Icon(Icons.play_circle_outline),
                          label: Text(context.tr('settings.tour.cta')),
                          style: TextButton.styleFrom(
                            foregroundColor: selectedTheme.colors.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selectedTheme.colors.glassBorder.withOpacity(0.55),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('settings.about.title'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        context.tr('settings.about.subtitle'),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.72),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
