import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/theme/theme_catalog.dart';
import 'package:vocabmaster/widgets/notification_settings_dialog.dart';

void main() {
  testWidgets('notification dialog toggles preference callbacks',
      (tester) async {
    var dailyReminderEnabled = false;
    bool? lastDailyReminderValue;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => NotificationSettingsDialog(
            theme: VocabThemes.defaultTheme,
            title: 'Notification preferences',
            dailyReminderTitle: 'Daily practice reminder',
            dailyReminderSubtitle: 'A calm reminder for daily practice.',
            dailyReminderEnabled: dailyReminderEnabled,
            onDailyReminderChanged: (value) {
              lastDailyReminderValue = value;
              setState(() => dailyReminderEnabled = value);
            },
            streakGuardTitle: 'Streak guard',
            streakGuardSubtitle: 'One reminder before your streak is at risk.',
            streakGuardEnabled: true,
            onStreakGuardChanged: (_) {},
            dailyWordsTitle: 'Daily words and updates',
            dailyWordsSubtitle: 'New daily content and updates.',
            dailyWordsEnabled: false,
            onDailyWordsChanged: (_) {},
            subscriptionTitle: 'Subscription and account',
            subscriptionSubtitle: 'Important payment or account access alerts.',
            subscriptionEnabled: true,
            onSubscriptionChanged: (_) {},
            socialTitle: 'Community notifications',
            socialSubtitle: 'Alerts from social features when enabled.',
            socialEnabled: true,
            onSocialChanged: (_) {},
            saving: false,
            onClose: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.byType(Switch).first);
    await tester.pump();

    expect(lastDailyReminderValue, true);
    expect(dailyReminderEnabled, true);
  });

  testWidgets('notification dialog disables toggles while saving',
      (tester) async {
    var callbackCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationSettingsDialog(
          theme: VocabThemes.defaultTheme,
          title: 'Notification preferences',
          dailyReminderTitle: 'Daily practice reminder',
          dailyReminderSubtitle: 'A calm reminder for daily practice.',
          dailyReminderEnabled: false,
          onDailyReminderChanged: (_) => callbackCount += 1,
          streakGuardTitle: 'Streak guard',
          streakGuardSubtitle: 'One reminder before your streak is at risk.',
          streakGuardEnabled: true,
          onStreakGuardChanged: (_) {},
          dailyWordsTitle: 'Daily words and updates',
          dailyWordsSubtitle: 'New daily content and updates.',
          dailyWordsEnabled: false,
          onDailyWordsChanged: (_) {},
          subscriptionTitle: 'Subscription and account',
          subscriptionSubtitle: 'Important payment or account access alerts.',
          subscriptionEnabled: true,
          onSubscriptionChanged: (_) {},
          socialTitle: 'Community notifications',
          socialSubtitle: 'Alerts from social features when enabled.',
          socialEnabled: true,
          onSocialChanged: (_) {},
          saving: true,
          onClose: () {},
        ),
      ),
    );

    await tester.tap(find.byType(Switch).first);
    await tester.pump();

    expect(callbackCount, 0);
  });
}
