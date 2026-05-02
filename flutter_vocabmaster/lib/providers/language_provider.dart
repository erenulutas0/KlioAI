import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../services/locale_text_service.dart';

class LanguageProvider extends ChangeNotifier {
  static const String _languageCodeKey = 'app_language_code';
  static const String _languageSelectedKey = 'app_language_selected';
  static const String _languagePromptSeenKey = 'app_language_prompt_seen';

  Locale _locale = AppLocalizations.fallbackLocale;
  bool _hasExplicitSelection = false;
  bool _initialized = false;

  Locale get locale => _locale;
  bool get hasExplicitSelection => _hasExplicitSelection;
  bool get initialized => _initialized;

  Locale get detectedLocale {
    final deviceLocale = WidgetsBinding.instance.platformDispatcher.locale;
    return AppLocalizations.normalize(deviceLocale);
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final savedCode = prefs.getString(_languageCodeKey);
    final selected = prefs.getBool(_languageSelectedKey) ?? false;
    final promptSeen = prefs.getBool(_languagePromptSeenKey) ?? false;

    if (savedCode != null && savedCode.isNotEmpty) {
      _locale = AppLocalizations.normalize(Locale(savedCode));
    } else {
      _locale = detectedLocale;
    }

    _hasExplicitSelection =
        selected && savedCode != null && savedCode.isNotEmpty && promptSeen;
    LocaleTextService.setAppLocale(_locale);
    _initialized = true;
    notifyListeners();
  }

  Future<void> selectLanguage(Locale locale) async {
    final normalized = AppLocalizations.normalize(locale);
    if (_locale == normalized && _hasExplicitSelection) {
      return;
    }
    _locale = normalized;
    LocaleTextService.setAppLocale(_locale);
    _hasExplicitSelection = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageCodeKey, normalized.languageCode);
    await prefs.setBool(_languageSelectedKey, true);
    await prefs.setBool(_languagePromptSeenKey, true);
  }
}
