import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';
import 'package:vocabmaster/providers/learning_language_provider.dart';
import 'package:vocabmaster/screens/translation_practice_page.dart';

/// The screen localized its direction chips but left the rest of its copy
/// hardcoded Turkish, so an English session showed "Çevirme Pratiği",
/// "Çeviri Yönü" and "Cümle Üret" sitting next to an English "Mixed" chip.

Future<void> _pumpPage(
  WidgetTester tester, {
  required Locale locale,
  required String subMode,
}) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({
    'learning_source_language': 'Turkish',
    'learning_english_level': 'B1',
    'learning_goal': 'Exam',
  });

  final learningProvider = LearningLanguageProvider();
  await learningProvider.initialize();

  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: learningProvider,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: TranslationPracticePage(subMode: subMode),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an English session shows English copy', (tester) async {
    await _pumpPage(tester, locale: const Locale('en'), subMode: 'manual');

    expect(find.text('Translation Practice'), findsOneWidget);
    expect(find.text('Translation Direction'), findsOneWidget);
    expect(find.text('Generate Sentences'), findsOneWidget);

    expect(find.text('Çevirme Pratiği'), findsNothing);
    expect(find.text('Çeviri Yönü'), findsNothing);
    expect(find.text('Cümle Üret'), findsNothing);
  });

  testWidgets('the mixed-mode card is English too', (tester) async {
    await _pumpPage(tester, locale: const Locale('en'), subMode: 'random');

    expect(find.text('Mixed Mode'), findsOneWidget);
    expect(find.text('5 random words will be picked'), findsOneWidget);

    expect(find.text('Karışık Mod'), findsNothing);
    expect(find.text('Rastgele 5 kelime seçilecek'), findsNothing);
  });

  testWidgets('a Turkish session still shows Turkish copy', (tester) async {
    await _pumpPage(tester, locale: const Locale('tr'), subMode: 'random');

    expect(find.text('Çevirme Pratiği'), findsOneWidget);
    expect(find.text('Karışık Mod'), findsOneWidget);
    expect(find.text('Rastgele 5 kelime seçilecek'), findsOneWidget);
    expect(find.text('Cümle Üret'), findsOneWidget);
  });
}
