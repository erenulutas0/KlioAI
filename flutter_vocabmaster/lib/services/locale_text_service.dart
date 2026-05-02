import 'dart:ui';

class LocaleTextService {
  const LocaleTextService._();

  static String? _appLanguageCode;

  static void setAppLocale(Locale locale) {
    _appLanguageCode = locale.languageCode.toLowerCase();
  }

  static bool get isTurkish =>
      (_appLanguageCode ??
          PlatformDispatcher.instance.locale.languageCode.toLowerCase()) ==
      'tr';

  static String pick(String tr, String en) => isTurkish ? tr : en;
}
