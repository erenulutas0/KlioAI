import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../services/analytics_service.dart';
import '../../services/local_reminder_service.dart';
import '../../services/push_token_service.dart';
import '../theme/nf_tokens.dart';
import 'nf_button.dart';

/// When a learner is asked whether they want to be reminded.
///
/// The app used to open the system prompt at launch: a dialog about notifications before it
/// had said anything at all. Android 13 allows two refusals and then closes the setting for
/// good, and the result was 12 push tokens across 105 accounts — the reminders meant to bring
/// people back could not reach nine in ten of them. So the system prompt is now only ever
/// opened by somebody who has just said yes to being reminded, and this decides when they are
/// asked: after a conversation, twice at most, three days apart, and never once notifications
/// are already allowed.
class NfReminderPromptSchedule {
  const NfReminderPromptSchedule._();

  static const Duration minBetweenAsks = Duration(days: 3);
  static const int maxAsks = 2;

  static const String lastAskedKey = 'reminder_prompt:last_asked';
  static const String askCountKey = 'reminder_prompt:asks';

  /// [now] is injected by the tests.
  static Future<bool> shouldAsk({DateTime? now}) async {
    try {
      if (await LocalReminderService().hasNotificationPermission()) {
        return false;
      }
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if ((prefs.getInt(askCountKey) ?? 0) >= maxAsks) {
        return false;
      }
      final String? last = prefs.getString(lastAskedKey);
      if (last == null) {
        return true;
      }
      final DateTime? at = DateTime.tryParse(last);
      return at == null ||
          (now ?? DateTime.now()).difference(at) >= minBetweenAsks;
    } catch (e) {
      // Bookkeeping must never put a sheet in front of somebody by failing open.
      debugPrint('Reminder offer check skipped: $e');
      return false;
    }
  }

  static Future<void> recordAsked({DateTime? now}) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          lastAskedKey, (now ?? DateTime.now()).toIso8601String());
      await prefs.setInt(askCountKey, (prefs.getInt(askCountKey) ?? 0) + 1);
    } catch (e) {
      debugPrint('Reminder offer not recorded: $e');
    }
  }
}

/// "Shall I remind you tomorrow?" — asked in the learner's own language, right after a
/// conversation, and only then followed by the system prompt.
class NfReminderOfferSheet extends StatefulWidget {
  const NfReminderOfferSheet({super.key, required this.reason});

  /// Which moment produced the offer, for the analytics event. Not shown.
  final String reason;

  /// Shows the offer when it is due. Returns whether it was shown, so a caller with
  /// something else to put on screen can hold that back rather than stack two asks on one
  /// conversation.
  static Future<bool> maybeShow(BuildContext context,
      {required String reason}) async {
    if (!await NfReminderPromptSchedule.shouldAsk() || !context.mounted) {
      return false;
    }
    await NfReminderPromptSchedule.recordAsked();
    if (!context.mounted) {
      return false;
    }
    unawaited(AnalyticsService.logEvent(
      'reminder_offer_shown',
      parameters: <String, Object>{'reason': reason},
    ));
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NfReminderOfferSheet(reason: reason),
    );
    return true;
  }

  @override
  State<NfReminderOfferSheet> createState() => _NfReminderOfferSheetState();
}

class _NfReminderOfferSheetState extends State<NfReminderOfferSheet> {
  bool _working = false;

  Future<void> _accept() async {
    if (_working) {
      return;
    }
    setState(() => _working = true);

    // This is where the system prompt finally opens: the switch asks for the permission it
    // needs and schedules the reminder when it is given.
    final bool enabled = await LocalReminderService().setDailyReminderEnabled(true);
    if (enabled) {
      // The server's reminders need a token, and until now there was nobody to give one to.
      unawaited(PushTokenService().initialize());
    }
    unawaited(AnalyticsService.logEvent(
      'reminder_offer_answered',
      parameters: <String, Object>{
        'reason': widget.reason,
        'enabled': enabled.toString(),
      },
    ));

    if (!mounted) {
      return;
    }
    final NfTokens t = NfTokens.of(context);
    final String message = enabled
        ? context.tr('reminder.offer.done')
        : context.tr('reminder.offer.blocked');
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message,
          style: NfTokens.body(size: NfFont.s14, color: t.primaryInk)),
      backgroundColor: enabled ? t.correct : t.inkMuted,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
          NfSpace.s20, NfSpace.s12, NfSpace.s20, NfSpace.s22),
      decoration: BoxDecoration(
        color: t.ground,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(NfRadius.card)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: NfSpace.s16),
                decoration: BoxDecoration(
                  color: t.border,
                  borderRadius: BorderRadius.circular(NfRadius.pill),
                ),
              ),
            ),
            Text(
              context.tr('reminder.offer.title'),
              style: NfTokens.body(
                  size: NfFont.s18, color: t.ink, weight: FontWeight.w800),
            ),
            const SizedBox(height: NfSpace.s8),
            Text(
              context.tr('reminder.offer.body'),
              style: NfTokens.body(size: NfFont.s14, color: t.inkMuted),
            ),
            const SizedBox(height: NfSpace.s16),
            NfPrimaryButton(
              key: const ValueKey<String>('reminder-offer-yes'),
              label: context.tr('reminder.offer.yes'),
              busy: _working,
              onPressed: () => unawaited(_accept()),
            ),
            TextButton(
              key: const ValueKey<String>('reminder-offer-later'),
              onPressed: _working ? null : () => Navigator.of(context).pop(),
              child: Text(
                context.tr('reminder.offer.later'),
                style: NfTokens.body(size: NfFont.s14, color: t.inkFaint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
