import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';
import 'package:vocabmaster/widgets/navigation_menu_panel.dart';

void main() {
  testWidgets('NavigationMenuPanel renders routes and dispatches callbacks',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? selectedTab;
    String? selectedRoute;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: NavigationMenuPanel(
            activeTab: 'home',
            currentPage: 'home',
            onTabChange: (tab) => selectedTab = tab,
            onNavigate: (route) => selectedRoute = route,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(seconds: 4));

    expect(find.text('Home'), findsWidgets);
    expect(find.text('Words'), findsOneWidget);
    expect(find.text('Practice'), findsOneWidget);

    await tester.tap(find.text('Words'));
    await tester.pump();
    expect(selectedTab, 'words');
    expect(selectedRoute, isNull);

    await tester.tap(find.text('Stats'));
    await tester.pump();
    expect(selectedRoute, 'stats');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
