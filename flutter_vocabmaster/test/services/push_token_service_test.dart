import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/services/api_service.dart';
import 'package:vocabmaster/services/auth_service.dart';
import 'package:vocabmaster/services/local_reminder_service.dart';
import 'package:vocabmaster/services/push_token_service.dart';

class RecordingApiService extends ApiService {
  RecordingApiService() : super(baseUrl: 'https://api.test');

  final List<Map<String, Object?>> registrations = [];

  @override
  Future<void> registerPushToken({
    required String token,
    required String platform,
    String? deviceId,
    String? appVersion,
    String? locale,
    String? timezone,
    bool dailyRemindersEnabled = false,
  }) async {
    registrations.add({
      'token': token,
      'platform': platform,
      'deviceId': deviceId,
      'appVersion': appVersion,
      'locale': locale,
      'timezone': timezone,
      'dailyRemindersEnabled': dailyRemindersEnabled,
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      LocalReminderService.dailyReminderKey: true,
    });
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'KlioAI',
      packageName: 'com.klioai.app',
      version: '1.2.3',
      buildNumber: '45',
      buildSignature: '',
      installerStore: 'com.android.vending',
    );

    await AuthService().saveSession(
      'test-token',
      'test-refresh',
      {
        'id': 44,
        'email': 'test@example.com',
        'displayName': 'Test User',
      },
    );
  });

  test('registers push token once per day/version unless forced or changed',
      () async {
    final api = RecordingApiService();
    final service = PushTokenService(
      apiService: api,
      skipMessagingInstance: true,
    );

    await service.registerTokenForTesting('fcm-token');
    await service.registerTokenForTesting('fcm-token');
    await service.registerTokenForTesting('fcm-token', force: true);
    await service.registerTokenForTesting('new-fcm-token');

    expect(api.registrations, hasLength(3));
    expect(api.registrations[0]['token'], 'fcm-token');
    expect(api.registrations[0]['appVersion'], '1.2.3+45');
    expect(api.registrations[0]['dailyRemindersEnabled'], true);
    expect(api.registrations[1]['token'], 'fcm-token');
    expect(api.registrations[2]['token'], 'new-fcm-token');
  });
}
