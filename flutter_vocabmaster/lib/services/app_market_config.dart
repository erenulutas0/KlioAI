import 'package:flutter/widgets.dart';

enum AppMarket {
  auto,
  tr,
  global,
}

class AppMarketConfig {
  AppMarketConfig._();

  static const String _market = String.fromEnvironment(
    'APP_MARKET',
    defaultValue: 'auto',
  );

  static AppMarket get forcedMarket {
    switch (_market.toLowerCase()) {
      case 'tr':
        return AppMarket.tr;
      case 'global':
        return AppMarket.global;
      default:
        return AppMarket.auto;
    }
  }

  static AppMarket resolveMarket(Locale? locale) {
    final forced = forcedMarket;
    if (forced != AppMarket.auto) {
      return forced;
    }
    final effectiveLocale = locale ?? WidgetsBinding.instance.platformDispatcher.locale;
    return effectiveLocale.languageCode.toLowerCase() == 'tr'
        ? AppMarket.tr
        : AppMarket.global;
  }
}
