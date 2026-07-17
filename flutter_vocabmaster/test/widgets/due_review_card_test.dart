import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/services/locale_text_service.dart';
import 'package:vocabmaster/widgets/due_review_card.dart';

void main() {
  setUp(() {
    LocaleTextService.setAppLocale(const Locale('en'));
  });

  testWidgets('shows due count and fires onTap', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DueReviewCard(
            dueCount: 7,
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('7 words due for review'), findsOneWidget);
    expect(
      find.text('A quick review keeps your memory fresh'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('home-due-review-card')));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('uses singular copy for one due word', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DueReviewCard(dueCount: 1, onTap: _noop),
        ),
      ),
    );

    expect(find.text('1 word due for review'), findsOneWidget);
  });

  testWidgets('renders nothing when no reviews are due', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DueReviewCard(dueCount: 0, onTap: _noop),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('home-due-review-card')), findsNothing);
    expect(find.textContaining('due for review'), findsNothing);
  });

  testWidgets('shows Turkish copy under Turkish locale', (tester) async {
    LocaleTextService.setAppLocale(const Locale('tr'));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DueReviewCard(dueCount: 3, onTap: _noop),
        ),
      ),
    );

    expect(find.text('3 kelime tekrar bekliyor'), findsOneWidget);
  });
}

void _noop() {}
