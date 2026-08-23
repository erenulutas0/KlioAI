import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/api_service.dart';
import '../../services/local_reminder_service.dart';
import '../../services/push_token_service.dart';
import '../theme/nf_tokens.dart';
import '../widgets/nf_card.dart';

/// Notification preferences, in the new frontend's own paint.
///
/// This exists so the shell never has to push `ProfilePage` on top of itself.
/// That screen carries the legacy `BottomNav`, whose taps run
/// `pushAndRemoveUntil(..., (route) => false)` — inside the new shell that
/// silently tears down the running `NfShell` and everything held in its
/// `IndexedStack`: the tutor conversation, the words query, every scroll
/// position. Legacy-to-legacy the same shell was simply rebuilt, so it cost
/// nothing; here it loses real state.
///
/// The switches themselves call exactly the services `ProfilePage` calls —
/// [LocalReminderService] for what the on-device schedulers read, [ApiService]
/// for what the push backend sends — so the two screens cannot drift apart in
/// behaviour, only in appearance.
class NfNotificationsPage extends StatefulWidget {
  const NfNotificationsPage({
    super.key,
    this.apiService,
    this.localReminderService,
    this.pushTokenService,
    this.skipInitialRemoteLoads = false,
  });

  /// Injectable for tests. Default to the shared implementations.
  final ApiService? apiService;
  final LocalReminderService? localReminderService;
  final PushTokenService? pushTokenService;

  /// Lets a widget test mount the page without hitting the network.
  final bool skipInitialRemoteLoads;

  @override
  State<NfNotificationsPage> createState() => _NfNotificationsPageState();
}

/// One row's worth of state. Keeping the five switches in a list rather than in
/// five field pairs is what stops the save path from growing a branch per
/// switch.
enum _Pref {
  dailyReminder,
  streakGuard,
  wordRecall,
  productUpdates,
  subscriptionAlerts,
  social,
}

class _NfNotificationsPageState extends State<NfNotificationsPage> {
  late final ApiService _apiService;
  late final LocalReminderService _reminders;
  late final PushTokenService _pushTokens;

  /// Server field names. Deliberately the exact set `ProfilePage` sends — word
  /// recall is missing on purpose, because that reminder is scheduled on the
  /// device and the backend has never had a field for it.
  static const Map<_Pref, String> _remoteKeys = <_Pref, String>{
    _Pref.dailyReminder: 'dailyRemindersEnabled',
    _Pref.streakGuard: 'streakGuardEnabled',
    _Pref.productUpdates: 'productUpdatesEnabled',
    _Pref.subscriptionAlerts: 'subscriptionAlertsEnabled',
    _Pref.social: 'socialEnabled',
  };

  /// The switches a device-side scheduler actually reads. For these the phone
  /// is the authority: the server copy only decides whether a *push* is sent.
  static const Map<_Pref, String> _localKeys = <_Pref, String>{
    _Pref.streakGuard: LocalReminderService.streakGuardKey,
    _Pref.subscriptionAlerts: LocalReminderService.subscriptionAlertKey,
    _Pref.wordRecall: LocalReminderService.wordRecallKey,
  };

  final Map<_Pref, bool> _values = <_Pref, bool>{
    _Pref.dailyReminder: true,
    _Pref.streakGuard: true,
    _Pref.wordRecall: true,
    _Pref.productUpdates: false,
    _Pref.subscriptionAlerts: true,
    _Pref.social: true,
  };

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _apiService = widget.apiService ?? ApiService();
    _reminders = widget.localReminderService ?? LocalReminderService();
    _pushTokens = widget.pushTokenService ?? PushTokenService();
    if (widget.skipInitialRemoteLoads) {
      _loading = false;
    } else {
      unawaited(_load());
    }
  }

  // ---------------------------------------------------------------------------
  // Load / save
  // ---------------------------------------------------------------------------

  Future<void> _load() async {
    // The device switches are the authority for anything a local scheduler
    // reads: they are what decides whether a notification is actually raised.
    // The server copy only matters for push, so it is the fallback, never the
    // override, for those two rows.
    final bool localDaily = await _reminders.isDailyReminderEnabled();
    final bool localStreak = await _reminders.isStreakGuardEnabled();
    final bool localRecall = await _reminders.isWordRecallEnabled();
    final bool localSubscription = await _reminders.isSubscriptionAlertEnabled();

    Map<String, dynamic>? remote;
    try {
      remote = await _apiService.getNotificationPreferences();
    } catch (e) {
      // An unreachable backend must not lock the learner out of the switches;
      // the device values above are enough to render an honest screen.
      debugPrint('NfNotificationsPage: preferences unavailable ($e)');
    }

    if (!mounted) return;
    setState(() {
      _values[_Pref.dailyReminder] =
          _boolPref(remote, _remoteKeys[_Pref.dailyReminder]!, localDaily);
      _values[_Pref.streakGuard] = localStreak;
      _values[_Pref.wordRecall] = localRecall;
      _values[_Pref.subscriptionAlerts] = localSubscription;
      _values[_Pref.productUpdates] = _boolPref(
        remote,
        _remoteKeys[_Pref.productUpdates]!,
        false,
      );
      _values[_Pref.social] =
          _boolPref(remote, _remoteKeys[_Pref.social]!, true);
      _loading = false;
    });
  }

  static bool _boolPref(
    Map<String, dynamic>? preferences,
    String key,
    bool fallback,
  ) {
    final dynamic value = preferences?[key];
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    return fallback;
  }

  Future<void> _toggle(_Pref pref, bool value) async {
    if (_saving) return;
    setState(() {
      _values[pref] = value;
      _saving = true;
    });

    try {
      // The daily reminder is the one switch that can refuse: turning it on
      // asks the OS for permission, and a denial has to be reflected back into
      // the row rather than left showing a promise the phone will not keep.
      if (pref == _Pref.dailyReminder) {
        bool applied = value;
        try {
          applied = await _reminders
              .setDailyReminderEnabled(value)
              .timeout(const Duration(seconds: 8));
        } catch (e) {
          debugPrint('NfNotificationsPage: daily reminder not applied ($e)');
          applied = false;
        }
        if (!mounted) return;
        if (applied != value) {
          setState(() => _values[_Pref.dailyReminder] = applied);
          _showMessage(
            // TODO(i18n): needs a key
            'Notifications are off for this app in your phone settings.',
          );
        }
      }

      final String? localKey = _localKeys[pref];
      if (localKey != null) {
        await _reminders.setReminderEnabled(localKey, _values[pref] ?? value);
      }

      final Map<String, dynamic> saved = await _apiService
          .updateNotificationPreferences(<String, dynamic>{
            for (final MapEntry<_Pref, String> entry in _remoteKeys.entries)
              entry.value: _values[entry.key] ?? false,
            'timezone': DateTime.now().timeZoneName,
          })
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;
      setState(() {
        for (final MapEntry<_Pref, String> entry in _remoteKeys.entries) {
          // The two device-backed rows keep the value the phone just stored;
          // the server's copy of them is only used for push.
          if (_localKeys.containsKey(entry.key)) continue;
          _values[entry.key] =
              _boolPref(saved, entry.value, _values[entry.key] ?? false);
        }
      });
      unawaited(_pushTokens.refreshTokenRegistration());
    } catch (e) {
      debugPrint('NfNotificationsPage: preferences not saved ($e)');
      if (!mounted) return;
      // TODO(i18n): needs a key
      _showMessage('Notification preferences could not be saved.');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _showMessage(String text) {
    final NfTokens t = NfTokens.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          text,
          style: NfTokens.body(size: NfFont.s135, color: t.primaryInk),
        ),
        backgroundColor: t.ink,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  /// The palette comes from the `NfThemeScope` the shell wraps this route in,
  /// not from this page — see `NfShell._pushNf`.
  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    return Scaffold(
      backgroundColor: t.ground,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _Header(
              title: context.tr('profile.notificationPrefs'),
              tokens: t,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(child: _buildBody(t)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(NfTokens t) {
    if (_loading) {
      return Center(
        child: SizedBox(
          width: NfSpace.s26,
          height: NfSpace.s26,
          child: CircularProgressIndicator(
            strokeWidth: NfStroke.border,
            color: t.primary,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        NfSpace.s16,
        NfSpace.s8,
        NfSpace.s16,
        NfSpace.s26,
      ),
      children: <Widget>[
        NfCard(
          padding: EdgeInsets.zero,
          clipContent: true,
          child: Column(
            children: <Widget>[
              _row(
                t,
                _Pref.dailyReminder,
                // TODO(i18n): needs a key
                'Daily practice reminder',
                // TODO(i18n): needs a key
                'A calm reminder for daily practice.',
                first: true,
              ),
              _row(
                t,
                _Pref.streakGuard,
                // TODO(i18n): needs a key
                'Streak guard',
                // TODO(i18n): needs a key
                'One reminder before your streak is at risk.',
              ),
              _row(
                t,
                _Pref.wordRecall,
                // TODO(i18n): needs a key
                'Word recall',
                // TODO(i18n): needs a key
                'Once a day, asks you about a word whose review is overdue.',
              ),
              _row(
                t,
                _Pref.productUpdates,
                // TODO(i18n): needs a key
                'Daily words and updates',
                // TODO(i18n): needs a key
                'New daily content and low-frequency updates.',
              ),
              _row(
                t,
                _Pref.subscriptionAlerts,
                // TODO(i18n): needs a key
                'Subscription and account',
                // TODO(i18n): needs a key
                'Important payment or account access alerts.',
              ),
              _row(
                t,
                _Pref.social,
                // TODO(i18n): needs a key
                'Community notifications',
                // TODO(i18n): needs a key
                'Alerts from social features when enabled.',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(
    NfTokens t,
    _Pref pref,
    String title,
    String subtitle, {
    bool first = false,
  }) {
    return Column(
      children: <Widget>[
        if (!first)
          Divider(
            height: NfStroke.border,
            thickness: NfStroke.border,
            color: t.border,
          ),
        _SwitchRow(
          title: title,
          subtitle: subtitle,
          value: _values[pref] ?? false,
          tokens: t,
          // Every row is disabled while one save is in flight: the request
          // sends all five values at once, so a second toggle mid-flight would
          // race the response back into the UI.
          onChanged: _saving ? null : (bool v) => unawaited(_toggle(pref, v)),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PIECES
// ═══════════════════════════════════════════════════════════════════════════

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.tokens,
    required this.onBack,
  });

  final String title;
  final NfTokens tokens;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NfSpace.s12,
        NfSpace.s8,
        NfSpace.s16,
        NfSpace.s8,
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: onBack,
            iconSize: NfFont.s22,
            color: tokens.ink,
            // The default 48px IconButton already clears the tap floor.
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          ),
          const SizedBox(width: NfSpace.s4),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NfTokens.display(size: NfFont.s20, color: tokens.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// A title/subtitle row with the frontend's own switch.
///
/// Material's `Switch` is not used: it draws a blurred elevation shadow on the
/// thumb, which is the one thing this design never does.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.tokens,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final NfTokens tokens;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onChanged != null;

    return Semantics(
      toggled: value,
      enabled: enabled,
      label: title,
      child: InkWell(
        onTap: enabled ? () => onChanged!(!value) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NfSpace.s16,
            vertical: NfSpace.s14,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      title,
                      style: NfTokens.body(
                        size: NfFont.s145,
                        weight: NfTokens.bodyEmphasisWeight,
                        color: enabled ? tokens.ink : tokens.inkFaint,
                      ),
                    ),
                    const SizedBox(height: NfSpace.s4),
                    Text(
                      subtitle,
                      style: NfTokens.body(
                        size: NfFont.s125,
                        color: tokens.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: NfSpace.s12),
              ExcludeSemantics(
                child: _NfSwitch(value: value, tokens: tokens),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NfSwitch extends StatelessWidget {
  const _NfSwitch({required this.value, required this.tokens});

  static const double _width = 50;
  static const double _height = 30;

  /// Track height minus its 2px border on both sides, minus [_inset] on both
  /// sides. Stated as arithmetic so the knob cannot silently outgrow the track.
  static const double _inset = 3;
  static const double _knob = _height - 2 * NfStroke.border - 2 * _inset;

  final bool value;
  final NfTokens tokens;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      width: _width,
      height: _height,
      padding: const EdgeInsets.all(_inset),
      alignment: value ? Alignment.centerRight : Alignment.centerLeft,
      decoration: BoxDecoration(
        color: value ? tokens.primary : tokens.raised,
        borderRadius: BorderRadius.circular(NfRadius.pill),
        border: Border.fromBorderSide(
          value ? tokens.sideOf(tokens.primaryShadow) : tokens.sideStrong,
        ),
      ),
      child: Container(
        width: _knob,
        height: _knob,
        decoration: BoxDecoration(
          color: value ? tokens.primaryInk : tokens.surface,
          shape: BoxShape.circle,
          border: Border.fromBorderSide(
            value ? tokens.sideOf(tokens.primary) : tokens.sideStrong,
          ),
        ),
      ),
    );
  }
}
