import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';
import 'package:vocabmaster/widgets/daily_word_card.dart';

void main() {
  Map<String, dynamic> buildWordData() {
    return {
      'word': 'Focus',
      'translation': 'Odak',
      'difficulty': 'easy',
    };
  }

  Widget buildTestApp(Widget child) {
    return MaterialApp(
      locale: const Locale('tr'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );
  }

  String tr(String key) => AppLocalizations(const Locale('tr')).t(key);

  testWidgets('DailyWordCard shows quick add when word not added',
      (tester) async {
    await tester.pumpWidget(
      buildTestApp(
        DailyWordCard(
          wordData: buildWordData(),
          onTap: () {},
          isWordAdded: false,
          isSentenceAdded: false,
          index: 0,
          onQuickAdd: () {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.text(tr('home.card.addSentence')), findsNothing);
    expect(find.text(tr('home.card.wordSentenceAdded')), findsNothing);
  });

  testWidgets(
      'DailyWordCard shows add sentence when word added but sentence missing',
      (tester) async {
    await tester.pumpWidget(
      buildTestApp(
        DailyWordCard(
          wordData: buildWordData(),
          onTap: () {},
          isWordAdded: true,
          isSentenceAdded: false,
          index: 0,
          onAddSentence: () {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.text(tr('home.card.addSentence')), findsOneWidget);
    expect(find.text(tr('home.card.wordSentenceAdded')), findsNothing);
  });

  testWidgets('DailyWordCard shows added badge when word and sentence added',
      (tester) async {
    await tester.pumpWidget(
      buildTestApp(
        DailyWordCard(
          wordData: buildWordData(),
          onTap: () {},
          isWordAdded: true,
          isSentenceAdded: true,
          index: 0,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.text(tr('home.card.addSentence')), findsNothing);
    expect(find.text(tr('home.card.wordSentenceAdded')), findsOneWidget);
  });
}
