import 'api_service.dart';
import 'locale_text_service.dart';

class AiErrorMessageFormatter {
  static String forQuota(ApiQuotaExceededException e) {
    final reason = (e.reason ?? '').trim().toLowerCase();
    final buffer = StringBuffer();

    if (reason == 'abuse-ban' || (e.banLevel ?? 0) > 0) {
      buffer.write(LocaleTextService.pick(
        'Anormal AI kullanimi algilandi. Gecici erisim kisitlandi.',
        'Abnormal AI usage was detected. Access is temporarily limited.',
      ));
    } else if (reason == 'daily-token-quota') {
      buffer.write(LocaleTextService.pick(
        'Gunluk AI hakkin doldu.',
        'Your daily AI quota is exhausted.',
      ));
    } else if (reason == 'daily-quota' ||
        reason == 'user-burst' ||
        reason == 'ip-burst') {
      buffer.write(LocaleTextService.pick(
        'AI istek limitine ulasildi.',
        'The AI request limit has been reached.',
      ));
    } else if (reason == 'redis-fail-closed') {
      buffer.write(LocaleTextService.pick(
        'AI servisi su an koruma modunda. Lutfen biraz sonra tekrar dene.',
        'The AI service is currently in protection mode. Please try again shortly.',
      ));
    } else {
      buffer.write(
        e.message.isNotEmpty
            ? e.message
            : LocaleTextService.pick(
                'AI istegi su an tamamlanamadi.',
                'The AI request could not be completed right now.',
              ),
      );
    }

    if (e.retryAfterSeconds != null && e.retryAfterSeconds! > 0) {
      buffer.write(
        '\n${LocaleTextService.pick('Tekrar deneme', 'Retry after')}: ${_formatDuration(e.retryAfterSeconds!)}.',
      );
    }

    if (e.banLevel != null && e.banLevel! > 0) {
      buffer.write(
        '\n${LocaleTextService.pick('Ban seviyesi', 'Ban level')}: ${e.banLevel}.',
      );
    }

    if (e.nextBanSeconds != null && e.nextBanSeconds! > 0) {
      buffer.write(
        '\n${LocaleTextService.pick('Sonraki ihlalde bekleme', 'Next violation wait')}: ${_formatDuration(e.nextBanSeconds!)}.',
      );
    }

    if (reason == 'daily-token-quota' &&
        e.tokensUsed != null &&
        e.tokenLimit != null) {
      buffer.write(
        '\n${LocaleTextService.pick('Gunluk kullanim', 'Daily usage')}: ${e.tokensUsed}/${e.tokenLimit} token.',
      );
    }

    return buffer.toString();
  }

  static String forError(
    Object e, {
    String? fallback,
  }) {
    final normalizedFallback = fallback ??
        LocaleTextService.pick(
          'Islem su an tamamlanamadi.',
          'The action could not be completed right now.',
        );
    if (e is ApiQuotaExceededException) {
      return forQuota(e);
    }
    if (e is ApiUpgradeRequiredException) {
      return forUpgrade(e);
    }
    return normalizedFallback;
  }

  static String forUpgrade(ApiUpgradeRequiredException e) {
    final reason = (e.reason ?? '').trim().toLowerCase();
    if (reason == 'ai-access-disabled') {
      return LocaleTextService.pick(
        'Ucretsiz AI suresi bitti. Devam etmek icin Premium plana gec.',
        'Your free AI period has ended. Upgrade to Premium to continue.',
      );
    }
    return e.message.isNotEmpty
        ? e.message
        : LocaleTextService.pick(
            'AI ozellikleri icin abonelik gerekli.',
            'A subscription is required for AI features.',
          );
  }

  static String _formatDuration(int totalSeconds) {
    final safe = totalSeconds < 1 ? 1 : totalSeconds;
    final minutes = safe ~/ 60;
    final seconds = safe % 60;

    if (minutes == 0) {
      return LocaleTextService.pick('$seconds sn', '$seconds sec');
    }
    if (seconds == 0) {
      return LocaleTextService.pick('$minutes dk', '$minutes min');
    }
    return LocaleTextService.pick(
      '$minutes dk $seconds sn',
      '$minutes min $seconds sec',
    );
  }
}
