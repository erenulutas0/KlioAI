import 'api_service.dart';

class AiErrorMessageFormatter {
  static String forQuota(ApiQuotaExceededException e) {
    final reason = (e.reason ?? '').trim().toLowerCase();
    final buffer = StringBuffer();

    if (reason == 'abuse-ban' || (e.banLevel ?? 0) > 0) {
      buffer.write('Anormal AI kullanimi algilandi. Gecici erisim kisitlandi.');
    } else if (reason == 'daily-token-quota') {
      buffer.write('Gunluk AI hakkin doldu.');
    } else if (reason == 'daily-quota' ||
        reason == 'user-burst' ||
        reason == 'ip-burst') {
      buffer.write('AI istek limitine ulasildi.');
    } else if (reason == 'redis-fail-closed') {
      buffer.write(
          'AI servisi su an koruma modunda. Lutfen biraz sonra tekrar dene.');
    } else {
      buffer.write(
          e.message.isNotEmpty ? e.message : 'AI istegi su an tamamlanamadi.');
    }

    if (e.retryAfterSeconds != null && e.retryAfterSeconds! > 0) {
      buffer
          .write('\nTekrar deneme: ${_formatDuration(e.retryAfterSeconds!)}.');
    }

    if (e.banLevel != null && e.banLevel! > 0) {
      buffer.write('\nBan seviyesi: ${e.banLevel}.');
    }

    if (e.nextBanSeconds != null && e.nextBanSeconds! > 0) {
      buffer.write(
          '\nSonraki ihlalde bekleme: ${_formatDuration(e.nextBanSeconds!)}.');
    }

    if (reason == 'daily-token-quota' &&
        e.tokensUsed != null &&
        e.tokenLimit != null) {
      buffer.write('\nGunluk kullanim: ${e.tokensUsed}/${e.tokenLimit} token.');
    }

    return buffer.toString();
  }

  static String forError(
    Object e, {
    String fallback = 'Islem su an tamamlanamadi.',
  }) {
    if (e is ApiQuotaExceededException) {
      return forQuota(e);
    }
    if (e is ApiUpgradeRequiredException) {
      return forUpgrade(e);
    }
    return fallback;
  }

  static String forUpgrade(ApiUpgradeRequiredException e) {
    final reason = (e.reason ?? '').trim().toLowerCase();
    if (reason == 'ai-access-disabled') {
      return 'Ucretsiz AI suresi bitti. Devam etmek icin Premium plana gec.';
    }
    return e.message.isNotEmpty
        ? e.message
        : 'AI ozellikleri icin abonelik gerekli.';
  }

  static String _formatDuration(int totalSeconds) {
    final safe = totalSeconds < 1 ? 1 : totalSeconds;
    final minutes = safe ~/ 60;
    final seconds = safe % 60;

    if (minutes == 0) {
      return '$seconds sn';
    }
    if (seconds == 0) {
      return '$minutes dk';
    }
    return '$minutes dk $seconds sn';
  }
}
