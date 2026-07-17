import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/language_provider.dart';
import '../providers/learning_language_provider.dart';
import '../screens/onboarding_screen.dart';
import '../services/analytics_service.dart';
import '../services/learning_language_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_catalog.dart';
import '../theme/theme_provider.dart';
import '../widgets/animated_background.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  AppThemeConfig _currentTheme(BuildContext context, {required bool listen}) {
    try {
      return Provider.of<ThemeProvider?>(context, listen: listen)
              ?.currentTheme ??
          VocabThemes.defaultTheme;
    } catch (_) {
      return VocabThemes.defaultTheme;
    }
  }

  String _languageLabel(BuildContext context, String code) {
    switch (code) {
      case 'tr':
        return context.tr('language.turkish');
      default:
        return context.tr('language.english');
    }
  }

  String _learningLanguageLabel(BuildContext context, String language) {
    switch (language) {
      case 'Turkish':
        return context.tr('language.turkish');
      case 'Spanish':
        return context.tr('language.spanish');
      case 'Portuguese':
        return context.tr('language.portuguese');
      case 'Indonesian':
        return context.tr('language.indonesian');
      case 'German':
        return context.tr('language.german');
      case 'French':
        return context.tr('language.french');
      default:
        return context.tr('language.english');
    }
  }

  String _learningGoalLabel(BuildContext context, String goal) {
    switch (goal) {
      case 'Vocabulary':
        return context.tr('learning.goal.vocabulary');
      case 'Exam':
        return context.tr('learning.goal.exam');
      case 'Work':
        return context.tr('learning.goal.work');
      case 'Travel':
        return context.tr('learning.goal.travel');
      default:
        return context.tr('learning.goal.speaking');
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
                      color: current == code
                          ? selectedTheme.colors.accent
                          : Colors.white70,
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

  Future<void> _showSourceLanguageSheet(BuildContext context) async {
    final provider = context.read<LearningLanguageProvider>();
    final current = provider.sourceLanguage;
    final selectedTheme = _currentTheme(context, listen: false);
    final l10n = context.l10n;
    const languages = LearningLanguageService.supportedSourceLanguages;

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
                  l10n.t('settings.learning.sourceSheetTitle'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                ...languages.map((language) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      current == language
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: current == language
                          ? selectedTheme.colors.accent
                          : Colors.white70,
                    ),
                    title: Text(
                      _learningLanguageLabel(context, language),
                      style: const TextStyle(color: Colors.white),
                    ),
                    onTap: () async {
                      final navigator = Navigator.of(sheetContext);
                      final messenger = ScaffoldMessenger.of(context);
                      final message = l10n.t('settings.learning.sourceChanged');
                      await provider.selectSourceLanguage(language);
                      if (!navigator.mounted || !messenger.mounted) {
                        return;
                      }
                      navigator.pop();
                      messenger.showSnackBar(
                        SnackBar(content: Text(message)),
                      );
                      await AnalyticsService.logLearningProfileUpdated(
                        sourceLanguage: provider.sourceLanguage,
                        englishLevel: provider.englishLevel,
                        learningGoal: provider.learningGoal,
                        source: 'settings_source_language',
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

  Future<void> _showEnglishLevelSheet(BuildContext context) async {
    final provider = context.read<LearningLanguageProvider>();
    final current = provider.englishLevel;
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
                  l10n.t('settings.learning.levelSheetTitle'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                ...LearningLanguageService.supportedEnglishLevels.map((level) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      current == level
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: current == level
                          ? selectedTheme.colors.accent
                          : Colors.white70,
                    ),
                    title: Text(
                      level,
                      style: const TextStyle(color: Colors.white),
                    ),
                    onTap: () async {
                      final navigator = Navigator.of(sheetContext);
                      final messenger = ScaffoldMessenger.of(context);
                      final message = l10n.t('settings.learning.sourceChanged');
                      await provider.selectEnglishLevel(level);
                      if (!navigator.mounted || !messenger.mounted) {
                        return;
                      }
                      navigator.pop();
                      messenger.showSnackBar(
                        SnackBar(content: Text(message)),
                      );
                      await AnalyticsService.logLearningProfileUpdated(
                        sourceLanguage: provider.sourceLanguage,
                        englishLevel: provider.englishLevel,
                        learningGoal: provider.learningGoal,
                        source: 'settings_level',
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

  Future<void> _showLearningGoalSheet(BuildContext context) async {
    final provider = context.read<LearningLanguageProvider>();
    final current = provider.learningGoal;
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
                  l10n.t('settings.learning.goalSheetTitle'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                ...LearningLanguageService.supportedLearningGoals.map((goal) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      current == goal
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: current == goal
                          ? selectedTheme.colors.accent
                          : Colors.white70,
                    ),
                    title: Text(
                      _learningGoalLabel(context, goal),
                      style: const TextStyle(color: Colors.white),
                    ),
                    onTap: () async {
                      final navigator = Navigator.of(sheetContext);
                      final messenger = ScaffoldMessenger.of(context);
                      final message = l10n.t('settings.learning.sourceChanged');
                      await provider.selectLearningGoal(goal);
                      if (!navigator.mounted || !messenger.mounted) {
                        return;
                      }
                      navigator.pop();
                      messenger.showSnackBar(
                        SnackBar(content: Text(message)),
                      );
                      await AnalyticsService.logLearningProfileUpdated(
                        sourceLanguage: provider.sourceLanguage,
                        englishLevel: provider.englishLevel,
                        learningGoal: provider.learningGoal,
                        source: 'settings_goal',
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
    final learningProfile = context.watch<LearningLanguageProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('settings.title')),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: AnimatedBackground(isDark: true)),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.tr('settings.subtitle'),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selectedTheme.colors.glassBorder
                            .withValues(alpha: 0.65),
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
                            color: Colors.white.withValues(alpha: 0.7),
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
                              label: Text(
                                  context.tr('settings.language.sheetTitle')),
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
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selectedTheme.colors.glassBorder
                            .withValues(alpha: 0.55),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('settings.learning.title'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          context.tr('settings.learning.subtitle'),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.72),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${context.tr('settings.learning.source')}: ${_learningLanguageLabel(context, learningProfile.sourceLanguage)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () =>
                                  _showSourceLanguageSheet(context),
                              icon: const Icon(Icons.translate),
                              label: Text(
                                context
                                    .tr('settings.learning.sourceSheetTitle'),
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: selectedTheme.colors.accent,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${context.tr('settings.learning.target')}: ${_learningLanguageLabel(context, learningProfile.targetLanguage)}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _ProfilePillButton(
                              icon: Icons.school_outlined,
                              label:
                                  '${context.tr('settings.learning.level')}: ${learningProfile.englishLevel}',
                              color: selectedTheme.colors.accent,
                              onTap: () => _showEnglishLevelSheet(context),
                            ),
                            _ProfilePillButton(
                              icon: Icons.flag_outlined,
                              label:
                                  '${context.tr('settings.learning.goal')}: ${_learningGoalLabel(context, learningProfile.learningGoal)}',
                              color: selectedTheme.colors.accent,
                              onTap: () => _showLearningGoalSheet(context),
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
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selectedTheme.colors.glassBorder
                            .withValues(alpha: 0.55),
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
                            color: Colors.white.withValues(alpha: 0.72),
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
                                  builder: (_) => const OnboardingScreen(
                                      fromSettings: true),
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
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selectedTheme.colors.glassBorder
                            .withValues(alpha: 0.55),
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
                            color: Colors.white.withValues(alpha: 0.72),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
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

class _ProfilePillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ProfilePillButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.38)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
