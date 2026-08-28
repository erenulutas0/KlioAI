import 'dart:ui';

class LocaleTextService {
  const LocaleTextService._();

  static String? _appLanguageCode;

  static void setAppLocale(Locale locale) {
    _appLanguageCode = locale.languageCode.toLowerCase();
  }

  /// The language the interface is being read in, lowercased.
  ///
  /// Falls back to the device's, which is what the app itself does before a
  /// choice has been stored.
  static String get appLanguageCode =>
      _appLanguageCode ??
      PlatformDispatcher.instance.locale.languageCode.toLowerCase();

  static bool get isTurkish => appLanguageCode == 'tr';

  static String pick(String tr, String en) => isTurkish ? tr : en;
}
