import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class NotificationSettingsDialog extends StatelessWidget {
  const NotificationSettingsDialog({
    super.key,
    required this.theme,
    required this.title,
    required this.dailyReminderTitle,
    required this.dailyReminderSubtitle,
    required this.dailyReminderEnabled,
    required this.onDailyReminderChanged,
    required this.streakGuardTitle,
    required this.streakGuardSubtitle,
    required this.streakGuardEnabled,
    required this.onStreakGuardChanged,
    required this.dailyWordsTitle,
    required this.dailyWordsSubtitle,
    required this.dailyWordsEnabled,
    required this.onDailyWordsChanged,
    required this.subscriptionTitle,
    required this.subscriptionSubtitle,
    required this.subscriptionEnabled,
    required this.onSubscriptionChanged,
    required this.socialTitle,
    required this.socialSubtitle,
    required this.socialEnabled,
    required this.onSocialChanged,
    required this.saving,
    required this.onClose,
  });

  final AppThemeConfig theme;
  final String title;
  final String dailyReminderTitle;
  final String dailyReminderSubtitle;
  final bool dailyReminderEnabled;
  final ValueChanged<bool> onDailyReminderChanged;
  final String streakGuardTitle;
  final String streakGuardSubtitle;
  final bool streakGuardEnabled;
  final ValueChanged<bool> onStreakGuardChanged;
  final String dailyWordsTitle;
  final String dailyWordsSubtitle;
  final bool dailyWordsEnabled;
  final ValueChanged<bool> onDailyWordsChanged;
  final String subscriptionTitle;
  final String subscriptionSubtitle;
  final bool subscriptionEnabled;
  final ValueChanged<bool> onSubscriptionChanged;
  final String socialTitle;
  final String socialSubtitle;
  final bool socialEnabled;
  final ValueChanged<bool> onSocialChanged;
  final bool saving;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: theme.colors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        padding: const EdgeInsets.all(24),
        width: MediaQuery.of(context).size.width * 0.9,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          Icons.notifications_active_outlined,
                          color: theme.colors.accent,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: onClose,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _NotificationSwitchTile(
                key: const ValueKey('notification-daily-reminder-switch'),
                theme: theme,
                title: dailyReminderTitle,
                subtitle: dailyReminderSubtitle,
                value: dailyReminderEnabled,
                onChanged: onDailyReminderChanged,
                enabled: !saving,
              ),
              const SizedBox(height: 12),
              _NotificationSwitchTile(
                key: const ValueKey('notification-streak-guard-switch'),
                theme: theme,
                title: streakGuardTitle,
                subtitle: streakGuardSubtitle,
                value: streakGuardEnabled,
                onChanged: onStreakGuardChanged,
                enabled: !saving,
              ),
              const SizedBox(height: 12),
              _NotificationSwitchTile(
                key: const ValueKey('notification-daily-words-switch'),
                theme: theme,
                title: dailyWordsTitle,
                subtitle: dailyWordsSubtitle,
                value: dailyWordsEnabled,
                onChanged: onDailyWordsChanged,
                enabled: !saving,
              ),
              const SizedBox(height: 12),
              _NotificationSwitchTile(
                key: const ValueKey('notification-subscription-switch'),
                theme: theme,
                title: subscriptionTitle,
                subtitle: subscriptionSubtitle,
                value: subscriptionEnabled,
                onChanged: onSubscriptionChanged,
                enabled: !saving,
              ),
              const SizedBox(height: 12),
              _NotificationSwitchTile(
                key: const ValueKey('notification-social-switch'),
                theme: theme,
                title: socialTitle,
                subtitle: socialSubtitle,
                value: socialEnabled,
                onChanged: onSocialChanged,
                enabled: !saving,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationSwitchTile extends StatelessWidget {
  const _NotificationSwitchTile({
    super.key,
    required this.theme,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.enabled,
  });

  final AppThemeConfig theme;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: theme.colors.accent.withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: enabled ? onChanged : null,
            activeThumbColor: Colors.white,
            activeTrackColor: theme.colors.accent,
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
          ),
        ],
      ),
    );
  }
}
