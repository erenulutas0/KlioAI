import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/services/locale_text_service.dart';
import 'package:vocabmaster/widgets/ai_token_quota_card.dart';

void main() {
  setUp(() {
    LocaleTextService.setAppLocale(const Locale('en'));
  });

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

    expect(find.text('Daily AI Tokens'), findsOneWidget);
    expect(find.text('45000 / 50000'), findsOneWidget);
    expect(find.text('90.0% left'), findsOneWidget);
    expect(
      find.text('Used: 5000 (10.0%)  UTC: 2026-02-17'),
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

  testWidgets('AiTokenQuotaCard shows activity estimate hint when provided',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiTokenQuotaCard(
            isLoading: false,
            tokenLimit: 1500,
            tokensUsed: 300,
            tokensRemaining: 1200,
            remainingRatio: 0.8,
            quotaDateUtc: null,
            activityEstimates: {
              'conversations': 1,
              'translationChecks': 2,
              'sentenceSets': 1,
            },
            onRefresh: _noop,
          ),
        ),
      ),
    );

    // Singular for 1, plural for 2, and only conversation/check units surface.
    expect(
      find.text('≈ 1 conversation · 2 translation checks left'),
      findsOneWidget,
    );
  });

  testWidgets('AiTokenQuotaCard omits hint when estimates are zero',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiTokenQuotaCard(
            isLoading: false,
            tokenLimit: 1500,
            tokensUsed: 1500,
            tokensRemaining: 0,
            remainingRatio: 0.0,
            quotaDateUtc: null,
            activityEstimates: {
              'conversations': 0,
              'translationChecks': 0,
              'sentenceSets': 0,
            },
            onRefresh: _noop,
          ),
        ),
      ),
    );

    // The '≈' marker is unique to the activity hint (percentage text also
    // contains the word "left").
    expect(find.textContaining('≈'), findsNothing);
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

    expect(find.text('Token quota is not active.'), findsOneWidget);
  });

  testWidgets(
      'AiTokenQuotaCard shows retryable error instead of not-active when load failed',
      (tester) async {
    var refreshed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiTokenQuotaCard(
            isLoading: false,
            tokenLimit: 0,
            tokensUsed: 0,
            tokensRemaining: 0,
            remainingRatio: 1.0,
            quotaDateUtc: null,
            onRefresh: () {
              refreshed = true;
            },
            errorText: 'Could not load quota info.',
          ),
        ),
      ),
    );

    // A failed request must never be mislabeled as "quota is not active" -
    // a PRO user reads that as a broken subscription.
    expect(find.text('Token quota is not active.'), findsNothing);
    expect(find.text('Could not load quota info.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(refreshed, isTrue);
  });
}

void _noop() {}
