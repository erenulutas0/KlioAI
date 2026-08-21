import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/services/app_market_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppMarketConfig', () {
    test('defaults to auto market selection in test builds', () {
      expect(AppMarketConfig.forcedMarket, AppMarket.auto);
    });

    test('resolves Turkish locale to the TR market', () {
      expect(AppMarketConfig.resolveMarket(const Locale('tr')), AppMarket.tr);
    });

    test('resolves non-Turkish locales to global market by default', () {
      expect(
          AppMarketConfig.resolveMarket(const Locale('en')), AppMarket.global);
      expect(
          AppMarketConfig.resolveMarket(const Locale('es')), AppMarket.global);
    });
  });
}
