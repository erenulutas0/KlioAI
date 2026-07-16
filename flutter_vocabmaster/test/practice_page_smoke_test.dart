import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';
import 'package:vocabmaster/providers/app_state_provider.dart';
import 'package:vocabmaster/screens/practice_page.dart';

import 'test_helper.dart';

void main() {
  setUpAll(() {
    setupTestEnv();
  });

  testWidgets('PracticePage renders open modes and horizontal selector',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final appState = AppStateProvider();
    appState.setUser({
      'id': 7,
      'displayName': 'Practice Tester',
      'email': 'practice@test.local',
      'aiAccessEnabled': true,
      'planCode': 'FREE',
      'tokenLimit': 1500,
      'tokensRemaining': 1000,
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: PracticePage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Start Practice'), findsOneWidget);
    expect(find.text('Translation'), findsWidgets);
    expect(find.text('Reading'), findsWidgets);
    expect(find.text('Writing'), findsWidgets);

    final selector = find.byType(ListView).first;
    await tester.drag(selector, const Offset(-420, 0));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Speaking'), findsWidgets);
    expect(find.text('Pronunciation'), findsWidgets);
    expect(find.text('Word Galaxy'), findsWidgets);

    await tester.tap(find.text('Pronunciation').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Pronunciation'), findsWidgets);
    // Titled "Reading Clarity Report": scoring is transcript/pace based, so
    // the UI must not claim phoneme-level pronunciation accuracy.
    expect(find.text('Reading Clarity Report'), findsOneWidget);
    expect(find.text('Start pronunciation practice'), findsOneWidget);
  });
}
