import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/services/ai_error_message_formatter.dart';
import 'package:vocabmaster/services/api_service.dart';
import 'package:vocabmaster/services/locale_text_service.dart';

void main() {
  setUp(() {
    LocaleTextService.setAppLocale(const Locale('en'));
  });

  test('formats daily token quota with usage and retry details', () {
    final message = AiErrorMessageFormatter.forQuota(
      ApiQuotaExceededException(
        message: 'raw quota message',
        reason: 'daily-token-quota',
        retryAfterSeconds: 75,
        tokensUsed: 1500,
        tokenLimit: 1500,
      ),
    );

    expect(message, contains('Your daily AI quota is exhausted.'));
    expect(message, contains('Retry after: 1 min 15 sec.'));
    expect(message, contains('Daily usage: 1500/1500 token.'));
  });

  test('formats abuse ban details in Turkish', () {
    LocaleTextService.setAppLocale(const Locale('tr'));

    final message = AiErrorMessageFormatter.forQuota(
      ApiQuotaExceededException(
        message: '',
        reason: 'abuse-ban',
        banLevel: 2,
        nextBanSeconds: 120,
      ),
    );

    expect(message, contains('Anormal AI kullanimi algilandi.'));
    expect(message, contains('Ban seviyesi: 2.'));
    expect(message, contains('Sonraki ihlalde bekleme: 2 dk.'));
  });

  test('formats upgrade-required and AI-service errors with fallback text', () {
    expect(
      AiErrorMessageFormatter.forUpgrade(
        ApiUpgradeRequiredException(
          message: '',
          reason: 'ai-access-disabled',
        ),
      ),
      'Your free AI period has ended. Upgrade to Premium to continue.',
    );

    expect(
      AiErrorMessageFormatter.forError(
        ApiAiServiceException(
          message: 'provider failed',
          statusCode: 500,
          feature: 'speaking-chat',
        ),
      ),
      'KlioAI could not generate a response right now. Please try again shortly.',
    );

    expect(
      AiErrorMessageFormatter.forError(Exception('network')),
      'The action could not be completed right now.',
    );
  });
}
