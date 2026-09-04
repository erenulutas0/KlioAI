import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';
import 'package:vocabmaster/services/ai_error_message_formatter.dart';
import 'package:vocabmaster/services/google_login_error_message_formatter.dart';
import 'package:vocabmaster/services/locale_text_service.dart';
import 'package:vocabmaster/services/network_failure.dart';

/// Caught on the phone, in airplane mode, on build 450.
///
/// Removing the stack trace from the paywall's failure line was right and it
/// was not enough. Every one of those templates reads "<label>: {error}", so
/// stripping an unrecognised placeholder left the restore button saying
/// exactly "Hata" -- a red bar with one word, no more use than the
/// SocketException it replaced. The formatter has to be able to name the
/// commonest failure of all.
void main() {
  setUp(() => LocaleTextService.setAppLocale(const Locale('en')));
  tearDown(() => LocaleTextService.setAppLocale(const Locale('en')));

  const Object offline = _Thrown(
    "SocketException: Failed host lookup: 'api.klioai.app' "
    '(OS Error: No address associated with hostname, errno = 7)',
  );

  test('an offline failure fills the template with a real sentence', () {
    LocaleTextService.setAppLocale(const Locale('tr'));
    final String filled = AiErrorMessageFormatter.intoTemplate(
      AppLocalizations(const Locale('tr')).t('subscription.err.restore'),
      offline,
    );

    expect(filled, startsWith('Geri yükleme hatası: '));
    expect(filled, contains('Çevrimdışısın'));
    expect(filled, isNot(contains('SocketException')));
    expect(filled, isNot(contains('errno')));
    // The regression this test exists for: a bare label and nothing else.
    expect(filled.length, greaterThan(30));
  });

  test('every locale says something, and something different', () {
    final Map<String, String> byLocale = <String, String>{};
    for (final Locale locale in AppLocalizations.supportedLocales) {
      LocaleTextService.setAppLocale(locale);
      byLocale[locale.languageCode] =
          AiErrorMessageFormatter.forError(offline);
    }
    expect(byLocale.values.toSet(), hasLength(7));
    for (final MapEntry<String, String> entry in byLocale.entries) {
      expect(entry.value.length, greaterThan(20),
          reason: '${entry.key} is too short to be a real sentence');
    }
  });

  test('a timeout is told apart from being offline', () {
    final String timedOut = AiErrorMessageFormatter.forError(
      TimeoutException('after 0:00:30.000000'),
    );
    final String off = AiErrorMessageFormatter.forError(offline);
    expect(timedOut, isNot(off));
    expect(timedOut, isNotEmpty);
  });

  test('an unknown failure still strips rather than leaking', () {
    // The fallback path has to survive: no placeholder, no exception text.
    final String filled = AiErrorMessageFormatter.intoTemplate(
      'Payment error: {error}',
      const _Thrown('some brand new thing'),
    );
    expect(filled, 'Payment error');
    expect(filled, isNot(contains('brand new')));
  });

  test('both formatters agree on what offline means', () {
    // They kept separate copies of these patterns until network_failure.dart.
    for (final Object error in <Object>[
      offline,
      const _Thrown('SocketException: Connection refused'),
      const _Thrown('OS Error: Network is unreachable, errno = 101'),
    ]) {
      expect(looksOffline(error), isTrue);
      expect(GoogleLoginErrorMessageFormatter.codeFor(error), 'offline');
      expect(AiErrorMessageFormatter.forError(error),
          AppLocalizations(const Locale('en')).t('common.err.offline'));
    }
  });

  test('a cancelled sign-in is not mistaken for a network failure', () {
    expect(looksOffline(const _Thrown('sign_in_canceled')), isFalse);
    expect(GoogleLoginErrorMessageFormatter.codeFor(
        const _Thrown('PlatformException(sign_in_canceled)')), 'cancelled');
  });
}

class _Thrown {
  const _Thrown(this.text);
  final String text;
  @override
  String toString() => text;
}
