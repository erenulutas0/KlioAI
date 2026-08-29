import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';
import 'package:vocabmaster/providers/language_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('initialize uses normalized detected locale without explicit selection',
      () async {
    final provider = LanguageProvider();

    await provider.initialize();

    expect(provider.initialized, isTrue);
    expect(provider.locale.languageCode, isIn(['en', 'tr']));
    expect(provider.hasExplicitSelection, isFalse);
  });

  test('selectLanguage stores explicit normalized language', () async {
    final provider = LanguageProvider();
    await provider.initialize();

    await provider.selectLanguage(const Locale('tr', 'TR'));

    expect(provider.locale.languageCode, 'tr');
    expect(provider.hasExplicitSelection, isTrue);

    final reloadedProvider = LanguageProvider();
    await reloadedProvider.initialize();
    expect(reloadedProvider.locale.languageCode, 'tr');
    expect(reloadedProvider.hasExplicitSelection, isTrue);
  });

  test('unsupported language falls back to English', () async {
    // The code to reject is taken from the supported list rather than typed
    // in. This test used to pass 'es', and it went on passing for the wrong
    // reason the day Spanish shipped: the app now supported it, so the fall
    // back never happened and the failure read like a regression in the
    // provider. Adding a locale must not be able to quietly retarget a test.
    final unsupported = <String>['zz', 'xx', 'qq'].firstWhere((code) =>
        !AppLocalizations.supportedLocales
            .any((l) => l.languageCode == code));

    final provider = LanguageProvider();
    await provider.initialize();

    await provider.selectLanguage(Locale(unsupported));

    expect(provider.locale.languageCode, 'en');
    expect(provider.hasExplicitSelection, isTrue);
  });
}
