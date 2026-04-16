import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/language_provider.dart';
import 'splash_screen.dart';
import '../widgets/animated_background.dart';

class LanguageSelectionPage extends StatefulWidget {
  const LanguageSelectionPage({super.key});

  @override
  State<LanguageSelectionPage> createState() => _LanguageSelectionPageState();
}

class _LanguageSelectionPageState extends State<LanguageSelectionPage> {
  Locale? _selectedLocale;
  bool _isSaving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _selectedLocale ??= context.read<LanguageProvider>().detectedLocale;
  }

  Future<void> _continue() async {
    final locale = _selectedLocale;
    if (locale == null || _isSaving) {
      return;
    }
    setState(() {
      _isSaving = true;
    });
    await context.read<LanguageProvider>().selectLanguage(locale);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const SplashScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detectedLocale = context.watch<LanguageProvider>().detectedLocale;
    final currentSelection = _selectedLocale ?? detectedLocale;
    const locales = AppLocalizations.supportedLocales;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(24, 8, 24, 16),
        child: SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: _isSaving ? null : _continue,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyan,
              foregroundColor: Colors.black,
              disabledBackgroundColor: Colors.cyan.withOpacity(0.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _isSaving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    context.tr('common.continue'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
          ),
        ),
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: AnimatedBackground(isDark: true),
          ),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
              children: [
                Text(
                  context.tr('language.setup.title'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  context.tr('language.setup.subtitle'),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.78),
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.14)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.language, color: Colors.cyanAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${context.tr('language.setup.detected')}: ${AppLocalizations.languageName(detectedLocale.languageCode)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Text(
                        context.tr('common.recommended'),
                        style: const TextStyle(
                          color: Colors.cyanAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  context.tr('language.setup.select'),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.86),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                ...locales.map((locale) {
                  final code = locale.languageCode;
                  final isSelected = currentSelection.languageCode == code;
                  final isDetected = detectedLocale.languageCode == code;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _selectedLocale = locale;
                        });
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.cyan.withOpacity(0.2)
                              : Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? Colors.cyanAccent
                                : Colors.white.withOpacity(0.16),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSelected
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                              color: isSelected
                                  ? Colors.cyanAccent
                                  : Colors.white70,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _languageLabel(code, context),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (isDetected)
                              Text(
                                context.tr('common.recommended'),
                                style: const TextStyle(
                                  color: Colors.cyanAccent,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 12),
                Text(
                  context.tr('language.setup.help'),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.62),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _languageLabel(String code, BuildContext context) {
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
}
