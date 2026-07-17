import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';
import 'package:vocabmaster/providers/app_state_provider.dart';
import 'package:vocabmaster/screens/profile_page.dart';
import 'package:vocabmaster/services/api_service.dart';
import 'package:vocabmaster/services/local_reminder_service.dart';
import 'package:vocabmaster/services/push_token_service.dart';
import 'package:vocabmaster/theme/theme_provider.dart';

class _FakeApiService extends ApiService {
  _FakeApiService({
    required this.preferences,
  });

  Map<String, dynamic> preferences;
  Map<String, dynamic>? lastSavedPreferences;

  @override
  Future<Map<String, dynamic>> getNotificationPreferences() async {
    return Map<String, dynamic>.from(preferences);
  }

  @override
  Future<Map<String, dynamic>> updateNotificationPreferences(
    Map<String, dynamic> preferences,
  ) async {
    lastSavedPreferences = Map<String, dynamic>.from(preferences);
    this.preferences = Map<String, dynamic>.from(preferences);
    return Map<String, dynamic>.from(this.preferences);
  }
}

class _FakeLocalReminderService extends LocalReminderService {
  _FakeLocalReminderService({required this.dailyReminderEnabled});

  bool dailyReminderEnabled;
  final requestedValues = <bool>[];

  @override
  Future<bool> isDailyReminderEnabled() async => dailyReminderEnabled;

  @override
  Future<bool> setDailyReminderEnabled(bool enabled) async {
    requestedValues.add(enabled);
    dailyReminderEnabled = enabled;
    return enabled;
  }
}

class _FakePushTokenService extends PushTokenService {
  _FakePushTokenService() : super(skipMessagingInstance: true);

  int refreshCount = 0;

  @override
  Future<void> refreshTokenRegistration() async {
    refreshCount += 1;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'Profile notification preferences save through local and API flow',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});

    final apiService = _FakeApiService(
      preferences: {
        'dailyRemindersEnabled': false,
        'streakGuardEnabled': true,
        'productUpdatesEnabled': false,
        'subscriptionAlertsEnabled': true,
        'socialEnabled': true,
      },
    );
    final localReminderService =
        _FakeLocalReminderService(dailyReminderEnabled: false);
    final pushTokenService = _FakePushTokenService();
    final themeProvider = ThemeProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppStateProvider()),
          ChangeNotifierProvider.value(value: themeProvider),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: ProfilePage(
            apiService: apiService,
            localReminderService: localReminderService,
            pushTokenService: pushTokenService,
            skipInitialRemoteLoads: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final notificationTile =
        find.byKey(const ValueKey('profile-notification-preferences-tile'));
    await tester.ensureVisible(notificationTile);
    await tester.tap(notificationTile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final dailyReminderTile =
        find.byKey(const ValueKey('notification-daily-reminder-switch'));
    expect(dailyReminderTile, findsOneWidget);

    await tester.tap(
      find.descendant(
        of: dailyReminderTile,
        matching: find.byType(Switch),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(localReminderService.requestedValues, [true]);
    expect(apiService.lastSavedPreferences, isNotNull);
    expect(apiService.lastSavedPreferences!['dailyRemindersEnabled'], true);
    expect(apiService.lastSavedPreferences!['streakGuardEnabled'], true);
    expect(apiService.lastSavedPreferences!['productUpdatesEnabled'], false);
    expect(
      apiService.lastSavedPreferences!['subscriptionAlertsEnabled'],
      true,
    );
    expect(apiService.lastSavedPreferences!['socialEnabled'], true);
    expect(apiService.lastSavedPreferences!['timezone'], isA<String>());
    expect(pushTokenService.refreshCount, 1);
  });
}
