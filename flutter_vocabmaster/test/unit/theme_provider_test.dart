import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/theme/theme_catalog.dart';
import 'package:vocabmaster/theme/theme_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('initialize loads default theme and exposes unlocked catalog', () async {
    final provider = ThemeProvider();

    await provider.initialize(initialXP: 75, initialPremiumAccess: false);

    expect(provider.currentTheme.id, VocabThemes.defaultTheme.id);
    expect(provider.userXP, 75);
    expect(provider.hasPremiumAccess, isFalse);
    expect(provider.themes, isNotEmpty);
    expect(provider.canUnlockTheme(provider.themes.last), isTrue);
    expect(provider.remainingXPForTheme(provider.themes.last), 0);
    expect(provider.unlockProgress(provider.themes.last), 1.0);
  });

  test('setTheme persists the selected theme', () async {
    final provider = ThemeProvider();
    await provider.initialize();

    final nextTheme = provider.themes.firstWhere(
      (theme) => theme.id != provider.currentTheme.id,
    );

    final changed = await provider.setTheme(nextTheme.id);

    expect(changed, isTrue);
    expect(provider.currentTheme.id, nextTheme.id);
    expect(provider.isTransitioning, isFalse);

    final reloadedProvider = ThemeProvider();
    await reloadedProvider.initialize();
    expect(reloadedProvider.currentTheme.id, nextTheme.id);
  });

  test('xp and premium updates are clamped and notified', () async {
    final provider = ThemeProvider();
    var notifications = 0;
    provider.addListener(() => notifications++);
    await provider.initialize(initialXP: 10);

    provider.updateUserXP(-25);
    provider.updatePremiumAccess(true);

    expect(provider.userXP, 0);
    expect(provider.hasPremiumAccess, isTrue);
    expect(notifications, greaterThanOrEqualTo(3));
  });
}
