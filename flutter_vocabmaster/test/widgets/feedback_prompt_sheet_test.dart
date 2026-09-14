import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';
import 'package:vocabmaster/services/rating_prompt_service.dart';
import 'package:vocabmaster/widgets/feedback_prompt_sheet.dart';

/// The sheet after reading, writing and a daily session, and the clock it shares with the
/// tutor.
///
/// Its own schedule -- three finished practices -- is pinned in feedback_prompt_gating_test.
/// What is pinned here is that it answers to the shared one as well: a learner the tutor
/// asked tonight is not asked again by the reading screen an hour later.
void main() {
  Widget host() {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () =>
                unawaited(FeedbackPromptSheet.maybeShow(context, feature: 'READING')),
            child: const Text('finish'),
          ),
        ),
      ),
    );
  }

  Future<void> finishReading(WidgetTester tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.text('finish'));
    await tester.pumpAndSettle();
  }

  const String completions = 'in_app_review:practice_completion_count';

  testWidgets('a learner due a question is asked, and the asking is remembered',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{completions: 3});

    await finishReading(tester);

    expect(find.text('How was this practice?'), findsOneWidget);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(RatingPromptService.lastFeatureKey('READING')), isNotNull);
    expect(prefs.getString(RatingPromptService.lastAnyKey), isNotNull);
  });

  testWidgets('the evening the tutor already asked, the sheet stays away',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      completions: 3,
      RatingPromptService.lastAnyKey:
          DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
      RatingPromptService.lastFeatureKey('TUTOR'):
          DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
    });

    await finishReading(tester);

    expect(find.byKey(const ValueKey<String>('rating-card')), findsNothing);
  });

  testWidgets('asking it to stop closes it, and the tutor stops asking too',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{completions: 3});

    await finishReading(tester);
    await tester.tap(find.byKey(const ValueKey<String>('rating-dont-ask')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('rating-card')), findsNothing);
    expect(await RatingPromptService().shouldAsk('TUTOR'), isFalse);
  });
}
