import 'dart:ui';

import '../l10n/app_localizations.dart';
import 'api_service.dart';
import 'locale_text_service.dart';

/// What to tell a learner when an AI request fails.
///
/// Reads the same seven-language key table as the rest of the app. It used to
/// call `LocaleTextService.pick(tr, en)` in sixteen places, which meant every
/// screen in the app was translated into seven languages and the one moment
/// something went wrong switched to English — a Spanish learner hitting their
/// quota was told "Your daily AI quota is exhausted" in the middle of an
/// otherwise Spanish app. Failure is exactly when a person is least able to
/// read a second language.
///
/// Static, and without a BuildContext, because it is called from services and
/// from catch blocks that have none. [_t] resolves the locale the same way
/// LocaleTextService does, from the stored app language.
class AiErrorMessageFormatter {
  /// One localised string, in whatever language the app is currently set to.
  static String _t(String key) =>
      AppLocalizations(Locale(LocaleTextService.appLanguageCode)).t(key);

  static String forQuota(ApiQuotaExceededException e) {
    final reason = (e.reason ?? '').trim().toLowerCase();
    final buffer = StringBuffer();

    if (reason == 'abuse-ban' || (e.banLevel ?? 0) > 0) {
      buffer.write(_t('ai.err.abuseBan'));
    } else if (reason == 'daily-token-quota') {
      buffer.write(_t('ai.err.dailyTokens'));
    } else if (reason == 'daily-quota' ||
        reason == 'user-burst' ||
        reason == 'ip-burst') {
      buffer.write(_t('ai.err.requestLimit'));
    } else if (reason == 'redis-fail-closed') {
      // Not the learner's allowance at all: the server reports this case with
      // a message claiming the daily quota is finished, and saying so would be
      // blaming somebody for our own outage.
      buffer.write(_t('ai.err.protectionMode'));
    } else {
      buffer.write(
        e.message.isNotEmpty ? e.message : _t('ai.err.quotaGeneric'),
      );
    }

    if (e.retryAfterSeconds != null && e.retryAfterSeconds! > 0) {
      buffer.write(
        '\n${_t('ai.err.retryAfter')}: ${_formatDuration(e.retryAfterSeconds!)}.',
      );
    }

    if (e.banLevel != null && e.banLevel! > 0) {
      buffer.write('\n${_t('ai.err.banLevel')}: ${e.banLevel}.');
    }

    if (e.nextBanSeconds != null && e.nextBanSeconds! > 0) {
      buffer.write(
        '\n${_t('ai.err.nextWait')}: ${_formatDuration(e.nextBanSeconds!)}.',
      );
    }

    if (reason == 'daily-token-quota' &&
        e.tokensUsed != null &&
        e.tokenLimit != null) {
      buffer.write(
        '\n${_t('ai.err.dailyUsage')}: ${e.tokensUsed}/${e.tokenLimit} token.',
      );
    }

    return buffer.toString();
  }

  static String forError(Object e, {String? fallback}) =>
      _specificFor(e) ?? fallback ?? _t('ai.err.generic');

  /// Fills a `{error}`-style template without ever putting a stack trace in it.
  ///
  /// Nine screens built their failure line as `template.replaceAll('{error}',
  /// '$e')`, so the sentence around it was translated and the thing inside it
  /// was a Dart exception: offline, a learner opening the paywall read
  /// "Payment failed: SocketException: Failed host lookup: 'api.klioai.app'
  /// (OS Error: No address associated with hostname, errno = 7)".
  ///
  /// When the failure is one this class can name, the name goes in. When it is
  /// not, the placeholder and whatever separator introduced it are removed
  /// rather than filled with something worse -- "Could not load the quiz"
  /// says everything true that we know.
  static String intoTemplate(
    String template,
    Object e, {
    String placeholder = '{error}',
  }) {
    final String? specific = _specificFor(e);
    if (specific != null && specific.isNotEmpty) {
      return template.replaceAll(placeholder, specific);
    }
    return template
        .replaceAll(
          RegExp('[:\\-\u2013\u2014]?\\s*' + RegExp.escape(placeholder)),
          '',
        )
        .trim();
  }

  /// The message for a failure this class recognises, or null.
  static String? _specificFor(Object e) {
    if (e is ApiQuotaExceededException) return forQuota(e);
    if (e is ApiUpgradeRequiredException) return forUpgrade(e);
    if (e is ApiAiServiceException) return _t('ai.err.aiService');
    return null;
  }

  static String forUpgrade(ApiUpgradeRequiredException e) {
    final reason = (e.reason ?? '').trim().toLowerCase();
    if (reason == 'ai-access-disabled') {
      return _t('ai.err.trialEnded');
    }
    return e.message.isNotEmpty
        ? e.message
        : _t('ai.err.subscriptionRequired');
  }

  static String _formatDuration(int totalSeconds) {
    final safe = totalSeconds < 1 ? 1 : totalSeconds;
    final minutes = safe ~/ 60;
    final seconds = safe % 60;

    if (minutes == 0) {
      return _t('ai.err.seconds').replaceAll('{n}', '$seconds');
    }
    if (seconds == 0) {
      return _t('ai.err.minutes').replaceAll('{n}', '$minutes');
    }
    return _t('ai.err.minutesSeconds')
        .replaceAll('{m}', '$minutes')
        .replaceAll('{s}', '$seconds');
  }
}
