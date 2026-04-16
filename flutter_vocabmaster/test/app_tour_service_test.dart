import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/services/app_tour_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppTourService', () {
    test('defaults to incomplete', () async {
      SharedPreferences.setMockInitialValues({});

      final service = AppTourService();

      expect(await service.isCompleted(), isFalse);
    });

    test('marks tour as completed', () async {
      SharedPreferences.setMockInitialValues({});
      final service = AppTourService();

      await service.markCompleted();

      expect(await service.isCompleted(), isTrue);
    });

    test('resets completion state', () async {
      SharedPreferences.setMockInitialValues({
        'app_tour_completed_v2': true,
      });
      final service = AppTourService();

      await service.reset();

      expect(await service.isCompleted(), isFalse);
    });
  });
}
