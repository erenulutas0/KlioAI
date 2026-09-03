import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';
import 'package:vocabmaster/services/ai_error_message_formatter.dart';
import 'package:vocabmaster/services/api_service.dart';
import 'package:vocabmaster/services/locale_text_service.dart';

/// Two failures that shared one shape: the app is translated into seven
/// languages, and the moment something went wrong it stopped being.
///
/// The formatter chose between Turkish and English in sixteen places, so a
/// Spanish learner who hit their quota was told about it in English. And nine
/// screens built their failure line by interpolating the exception into a
/// translated template, so the sentence was localised and the thing inside it
/// was a stack trace -- on the paywall, offline, that read "Payment failed:
/// SocketException: Failed host lookup: 'api.klioai.app' (OS Error: No address
/// associated with hostname, errno = 7)".
void main() {
  setUp(() => LocaleTextService.setAppLocale(const Locale('en')));
  tearDown(() => LocaleTextService.setAppLocale(const Locale('en')));

  ApiQuotaExceededException quota() => ApiQuotaExceededException(
        message: '',
        reason: 'daily-token-quota',
      );

  test('the quota message follows the app language', () {
    final Map<String, String> byLocale = <String, String>{};
    for (final Locale locale in AppLocalizations.supportedLocales) {
      LocaleTextService.setAppLocale(locale);
      byLocale[locale.languageCode] =
          AiErrorMessageFormatter.forQuota(quota());
    }

    expect(byLocale, hasLength(7));
    expect(byLocale.values.toSet(), hasLength(7),
        reason: 'two locales produced the same sentence, so at least one is '
            'reading another language: $byLocale');
    // The one that used to be wrong, named.
    expect(byLocale['es'], isNot(byLocale['en']));
  });

  test('a template never carries the exception into the UI', () {
    const String template = 'Payment failed: {error}';
    final String filled = AiErrorMessageFormatter.intoTemplate(
      template,
      const SocketExceptionLike(
        "Failed host lookup: 'api.klioai.app' (OS Error: errno = 7)",
      ),
    );

    expect(filled, isNot(contains('errno')));
    expect(filled, isNot(contains('api.klioai.app')));
    expect(filled, isNot(contains('{error}')));
    // The separator goes with the placeholder rather than dangling.
    expect(filled, 'Payment failed');
  });

  test('a failure we can name is named, inside the template', () {
    final String filled = AiErrorMessageFormatter.intoTemplate(
      'Could not load the quiz: {error}',
      quota(),
    );
    expect(filled, startsWith('Could not load the quiz: '));
    expect(filled, contains('quota'));
    expect(filled, isNot(contains('{error}')));
  });

  test('a custom placeholder is honoured', () {
    expect(
      AiErrorMessageFormatter.intoTemplate(
        'Error: {e}',
        const SocketExceptionLike('boom'),
        placeholder: '{e}',
      ),
      'Error',
    );
  });

  test('forError falls back without ever returning the raw object', () {
    final String message =
        AiErrorMessageFormatter.forError(const SocketExceptionLike('boom'));
    expect(message, isNot(contains('boom')));
    expect(message, isNotEmpty);
  });

  test('every key the formatter reads exists in every language', () {
    const List<String> keys = <String>[
      'ai.err.abuseBan',
      'ai.err.dailyTokens',
      'ai.err.requestLimit',
      'ai.err.protectionMode',
      'ai.err.quotaGeneric',
      'ai.err.retryAfter',
      'ai.err.banLevel',
      'ai.err.nextWait',
      'ai.err.dailyUsage',
      'ai.err.generic',
      'ai.err.aiService',
      'ai.err.trialEnded',
      'ai.err.subscriptionRequired',
      'ai.err.seconds',
      'ai.err.minutes',
      'ai.err.minutesSeconds',
      'dict.noMeaning',
    ];

    final List<String> missing = <String>[];
    for (final Locale locale in AppLocalizations.supportedLocales) {
      for (final String key in keys) {
        if (AppLocalizations(locale).t(key) == key) {
          missing.add('  ${locale.languageCode}: $key');
        }
      }
    }
    expect(missing, isEmpty,
        reason: 'These would render as their own key name inside an error '
            'message:\n${missing.join('\n')}');
  });

  test('the duration placeholders are filled, not printed', () {
    for (final Locale locale in AppLocalizations.supportedLocales) {
      LocaleTextService.setAppLocale(locale);
      final String message = AiErrorMessageFormatter.forQuota(
        ApiQuotaExceededException(
          message: '',
          reason: 'daily-quota',
          retryAfterSeconds: 90,
        ),
      );
      expect(message, isNot(contains('{n}')),
          reason: '${locale.languageCode} printed a placeholder');
      expect(message, isNot(contains('{m}')));
      expect(message, isNot(contains('{s}')));
      expect(message, contains('1'), reason: 'the minute went missing');
    }
  });
}

/// Stands in for a SocketException without importing dart:io into a test that
/// only cares about the text.
class SocketExceptionLike {
  const SocketExceptionLike(this.detail);
  final String detail;

  @override
  String toString() => 'SocketException: $detail';
}
