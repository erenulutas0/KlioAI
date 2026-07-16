import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';
import 'package:vocabmaster/theme/theme_provider.dart';
import 'package:vocabmaster/widgets/theme_side_tab.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('ThemeSideTab opens the theme picker and changes theme',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final provider = ThemeProvider();
    await provider.initialize(initialXP: 5000, initialPremiumAccess: true);
    final startingThemeId = provider.currentTheme.id;
    final nextTheme = provider.themes.firstWhere(
      (theme) => theme.id != startingThemeId,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          navigatorKey: appNavigatorKey,
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ThemeSideTab(
            child: Scaffold(
              body: Center(child: Text('Learning content')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Learning content'), findsOneWidget);

    await tester.tapAt(const Offset(3, 360));
    await tester.pumpAndSettle();

    expect(find.text('Choose Theme'), findsOneWidget);
    expect(find.text(nextTheme.name), findsOneWidget);

    await tester.tap(find.text(nextTheme.name));
    await tester.pumpAndSettle();

    expect(provider.currentTheme.id, nextTheme.id);
    expect(find.text('Choose Theme'), findsNothing);
  });
}
