import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    final provider = LanguageProvider();
    await provider.initialize();

    await provider.selectLanguage(const Locale('es'));

    expect(provider.locale.languageCode, 'en');
    expect(provider.hasExplicitSelection, isTrue);
  });
}
