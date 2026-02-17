import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/widgets/ai_token_quota_card.dart';

void main() {
  testWidgets('AiTokenQuotaCard shows quota values and progress', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiTokenQuotaCard(
            isLoading: false,
            tokenLimit: 50000,
            tokensUsed: 5000,
            tokensRemaining: 45000,
            remainingRatio: 0.9,
            quotaDateUtc: '2026-02-17',
            onRefresh: _noop,
          ),
        ),
      ),
    );

    expect(find.text('Günlük AI Token'), findsOneWidget);
    expect(find.text('45000 / 50000'), findsOneWidget);
    expect(find.text('%90.0 kaldi'), findsOneWidget);
    expect(
      find.text('Kullanilan: 5000 (%10.0)  UTC: 2026-02-17'),
      findsOneWidget,
    );

    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(indicator.value, 0.9);
  });

  testWidgets('AiTokenQuotaCard refresh icon triggers callback', (tester) async {
    var refreshed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiTokenQuotaCard(
            isLoading: false,
            tokenLimit: 50000,
            tokensUsed: 1000,
            tokensRemaining: 49000,
            remainingRatio: 0.98,
            quotaDateUtc: null,
            onRefresh: () {
              refreshed = true;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();

    expect(refreshed, isTrue);
  });

  testWidgets('AiTokenQuotaCard shows disabled state when limit is zero', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiTokenQuotaCard(
            isLoading: false,
            tokenLimit: 0,
            tokensUsed: 0,
            tokensRemaining: 0,
            remainingRatio: 1.0,
            quotaDateUtc: null,
            onRefresh: _noop,
          ),
        ),
      ),
    );

    expect(find.text('Token kotasi aktif degil.'), findsOneWidget);
  });
}

void _noop() {}

