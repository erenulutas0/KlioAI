import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/frontend_newest/widgets/nf_rating_card.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';

/// The card that asks "how was this?", and what it sends.
///
/// Every answer reaches the server exactly once. A low one asks what could have been better,
/// and its stars still count if the learner leaves before writing anything. The state lives
/// in the controller because the tutor draws this card inside a list, and a list throws away
/// the rows it scrolls off screen.
void main() {
  final List<(int, String?)> sent = <(int, String?)>[];
  late NfRatingController controller;

  setUp(() {
    sent.clear();
    controller = NfRatingController(onSubmit: (int stars, String? note) async {
      sent.add((stars, note));
    });
  });

  Widget card({VoidCallback? onDismiss, NfRatingController? using}) {
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
        body: SingleChildScrollView(
          child: NfRatingCard(
            controller: using ?? controller,
            title: 'How was this conversation with Luca?',
            onDismiss: onDismiss,
          ),
        ),
      ),
    );
  }

  // The strings load asynchronously, so a single frame draws an empty app.
  Future<void> show(WidgetTester tester, Widget widget) async {
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();
  }

  Future<void> tapStar(WidgetTester tester, int stars) async {
    await tester.tap(find.byKey(ValueKey<String>('rating-star-$stars')));
    await tester.pumpAndSettle();
  }

  testWidgets('five stars are sent at once, with no note asked for', (WidgetTester tester) async {
    await show(tester, card());

    await tapStar(tester, 5);

    expect(sent, <(int, String?)>[(5, null)]);
    expect(find.byKey(const ValueKey<String>('rating-note')), findsNothing);
    expect(find.text('Thank you for the rating.'), findsOneWidget);
  });

  testWidgets('low stars ask what could have been better, and the note goes with them',
      (WidgetTester tester) async {
    await show(tester, card());

    await tapStar(tester, 2);
    expect(sent, isEmpty, reason: 'sent before the learner had a chance to say why');
    expect(find.text('What could have been better?'), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey<String>('rating-note')), '  It misheard me twice  ');
    await tester.tap(find.byKey(const ValueKey<String>('rating-send')));
    await tester.pumpAndSettle();

    expect(sent, <(int, String?)>[(2, 'It misheard me twice')]);
  });

  testWidgets('skipping the note still sends the stars', (WidgetTester tester) async {
    await show(tester, card());

    await tapStar(tester, 3);
    await tester.tap(find.byKey(const ValueKey<String>('rating-skip')));
    await tester.pumpAndSettle();

    expect(sent, <(int, String?)>[(3, null)]);
  });

  testWidgets('a blank note is no note', (WidgetTester tester) async {
    await show(tester, card());

    await tapStar(tester, 1);
    await tester.enterText(find.byKey(const ValueKey<String>('rating-note')), '   ');
    await tester.tap(find.byKey(const ValueKey<String>('rating-send')));
    await tester.pumpAndSettle();

    expect(sent, <(int, String?)>[(1, null)]);
  });

  test('leaving before writing sends the stars that were chosen, once', () {
    controller.choose(2);
    controller.flush();
    controller.flush();

    expect(sent, <(int, String?)>[(2, null)]);
  });

  test('nothing chosen, nothing sent', () {
    controller.flush();
    controller.send();
    controller.skip();

    expect(sent, isEmpty);
  });

  test('answered is answered: nothing afterwards sends a second rating', () {
    controller.choose(5);
    controller.choose(1);
    controller.send();
    controller.skip();
    controller.flush();

    expect(sent, <(int, String?)>[(5, null)]);
    expect(controller.stars, 5);
  });

  test('a star that does not exist is not a rating', () {
    controller.choose(0);
    controller.choose(6);

    expect(controller.stage, NfRatingStage.asking);
    expect(sent, isEmpty);
  });

  testWidgets('a half-written note survives its row being thrown away',
      (WidgetTester tester) async {
    await show(tester, card());
    await tapStar(tester, 2);
    await tester.enterText(find.byKey(const ValueKey<String>('rating-note')), 'Too slow');

    // What a list does to a row scrolled out of view: the widget is gone, state and all.
    await tester.pumpWidget(const SizedBox());
    await show(tester, card());

    expect(find.text('Too slow'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('rating-send')));
    await tester.pumpAndSettle();
    expect(sent, <(int, String?)>[(2, 'Too slow')]);
  });

  testWidgets('closing it sends nothing', (WidgetTester tester) async {
    bool closed = false;
    await show(tester, card(onDismiss: () => closed = true));

    await tester.tap(find.byKey(const ValueKey<String>('rating-dismiss')));
    await tester.pump();

    expect(closed, isTrue);
    expect(sent, isEmpty);
  });

  testWidgets('the close button is only there when something listens to it',
      (WidgetTester tester) async {
    await show(tester, card());

    expect(find.byKey(const ValueKey<String>('rating-dismiss')), findsNothing);
  });

  testWidgets('a rating that cannot be sent still thanks the learner',
      (WidgetTester tester) async {
    final NfRatingController failing = NfRatingController(
      onSubmit: (int stars, String? note) async => throw Exception('offline'),
    );
    await show(tester, card(using: failing));

    await tapStar(tester, 4);

    expect(tester.takeException(), isNull);
    expect(failing.stage, NfRatingStage.thanks);
    expect(find.text('Thank you for the rating.'), findsOneWidget);
  });

  testWidgets('each star says which it is to a screen reader', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await show(tester, card());

    expect(find.bySemanticsLabel('1 of 5 stars'), findsOneWidget);
    expect(find.bySemanticsLabel('5 of 5 stars'), findsOneWidget);
    semantics.dispose();
  });
}
