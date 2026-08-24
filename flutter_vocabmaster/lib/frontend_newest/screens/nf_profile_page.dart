import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/app_state_provider.dart';
import '../../services/api_service.dart';
import '../theme/nf_tokens.dart';
import '../widgets/nf_button.dart';
import '../widgets/nf_card.dart';
import '../widgets/nf_chip.dart';
import '../widgets/nf_progress.dart';

/// The PROFILE tab of the "Modern Oyunlu" frontend.
///
/// Everything the learner *is* (name, plan, level) and *has* (streak, words,
/// XP, AI tokens) on one screen, plus the handful of settings that belong to
/// the account rather than to a lesson.
///
/// Navigation is deliberately not owned here: the four callbacks let the host
/// shell decide which route or sheet to open, so this page can be dropped into
/// the new frontend without pulling the old screen stack in behind it.
class NfProfilePage extends StatefulWidget {
  const NfProfilePage({
    super.key,
    this.onManageSubscription,
    this.onOpenNotifications,
    this.onOpenSettings,
    this.onToggleBrightness,
    this.apiService,
    this.skipInitialRemoteLoads = false,
  });

  /// Opens the subscription screen. Also drives the header "Upgrade" button:
  /// upgrading and managing are the same destination in this app.
  final VoidCallback? onManageSubscription;

  final VoidCallback? onOpenNotifications;

  /// Opens the app's settings screen — which is also where the switch back to
  /// the classic design lives, so this row must read as settings and not as a
  /// language picker.
  final VoidCallback? onOpenSettings;

  /// Flips the new frontend between the light and dark palette. The page only
  /// reports the current state; whoever installs [NfTheme] owns the value.
  final VoidCallback? onToggleBrightness;

  /// Injectable for tests. Defaults to the shared [ApiService].
  final ApiService? apiService;

  /// Lets a widget test mount the page without hitting the network.
  final bool skipInitialRemoteLoads;

  @override
  State<NfProfilePage> createState() => _NfProfilePageState();
}

class _NfProfilePageState extends State<NfProfilePage>
    with WidgetsBindingObserver {
  late final ApiService _apiService;

  bool _isQuotaLoading = false;

  /// Non-null only when the quota REQUEST failed. Kept apart from
  /// `_aiTokenLimit == 0` so a transient 401 never renders as "you have no
  /// quota" — a paying learner reads that as a broken subscription.
  ///
  /// Holds the l10n *key*, not the sentence: the learner can walk to settings,
  /// change the app language and come back to this very page, and a stored
  /// sentence would still be in the old language.
  String? _quotaErrorKey;

  int _aiTokenLimit = 0;
  int _aiTokensRemaining = 0;
  double _aiRemainingRatio = 1.0;

  /// The plan the server is actually metering against, straight from the quota
  /// response. See [_hasPaidPlan] for why nothing else may decide this.
  String? _aiPlanCode;

  @override
  void initState() {
    super.initState();
    _apiService = widget.apiService ?? ApiService();
    WidgetsBinding.instance.addObserver(this);
    if (!widget.skipInitialRemoteLoads) {
      _loadAiQuota();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from the Play purchase flow is the one moment the plan can
    // change while this page is alive. Re-reading the quota here keeps the plan
    // badge and the token panel from drifting apart until the next cold start.
    if (state == AppLifecycleState.resumed && !widget.skipInitialRemoteLoads) {
      _loadAiQuota();
    }
  }

  Future<void> _loadAiQuota() async {
    if (_isQuotaLoading) return;
    setState(() {
      _isQuotaLoading = true;
      _quotaErrorKey = null;
    });

    try {
      final Map<String, dynamic> data = await _apiService.chatbotQuotaStatus();
      final int limit = _asInt(data['tokenLimit']);
      final int used = _asInt(data['tokensUsed']);
      final int remaining = limit > 0
          ? (limit - used).clamp(0, limit)
          : _asInt(data['tokensRemaining']);
      final double ratio =
          limit > 0 ? (remaining / limit).clamp(0.0, 1.0).toDouble() : 1.0;

      if (!mounted) return;
      setState(() {
        _aiTokenLimit = limit;
        _aiTokensRemaining = remaining;
        _aiRemainingRatio = ratio;
        _aiPlanCode = data['planCode']?.toString();
        _quotaErrorKey = null;
        _isQuotaLoading = false;
      });
    } catch (e) {
      debugPrint('NfProfilePage: AI token quota could not be loaded: $e');
      if (!mounted) return;
      setState(() {
        _quotaErrorKey = e is ApiUnauthorizedException
            ? 'profile.quota.err.auth'
            : 'profile.quota.err.load';
        _isQuotaLoading = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Plan
  // ---------------------------------------------------------------------------

  /// The plan code the *server* is billing and metering, upper-cased.
  ///
  /// Both sources here are the same `/chatbot/quota/status` response — this
  /// page's own read, and the copy `AppStateProvider` merges into `userInfo`.
  /// Neither is the separately loaded subscription date, and that is the point.
  String? _livePlanCode(Map<String, dynamic>? user) {
    final String? own = _aiPlanCode?.trim().toUpperCase();
    if (own != null && own.isNotEmpty) return own;
    final String? merged = user?['planCode']?.toString().trim().toUpperCase();
    if (merged != null && merged.isNotEmpty) return merged;
    return null;
  }

  /// Which plan the learner is on, or [_PlanState.pending] while nobody knows.
  ///
  /// The live quota plan code wins, always. The header used to work this out
  /// from a separately loaded `subscriptionEndDate`, so one screen could show
  /// "PRO Member" above a panel reading 0 / 8000 — the free tier. The quota
  /// response carries the answer and refreshes; the date did not. The date is
  /// only consulted when the server has told us nothing at all, and a date we
  /// cannot parse is not evidence of a subscription.
  ///
  /// The third state exists because "no evidence" is not "free". `_aiPlanCode`
  /// is null until this page's own quota call returns, and `userInfo` carries
  /// no `planCode` until the provider's merge has run, so collapsing that
  /// window to false put "Free plan" and an Upgrade button in front of paying
  /// learners for as long as the request took — the same false claim the token
  /// tile already refuses to make.
  _PlanState _planState(AppStateProvider appState, Map<String, dynamic>? user) {
    final String? planCode = _livePlanCode(user);
    if (planCode != null && planCode != 'UNKNOWN') {
      return planCode == 'FREE' || planCode == 'FREE_TRIAL_7D'
          ? _PlanState.free
          : _PlanState.paid;
    }

    // Positive evidence from the subscription record still counts on its own.
    if (_hasSubscriptionEvidence(user)) {
      return _PlanState.paid;
    }

    // Its *absence* does not: not loaded looks exactly like not subscribed.
    if (_isQuotaLoading || _quotaErrorKey != null) {
      return _PlanState.pending;
    }
    if (appState.isLoadingAiEntitlement || !appState.hasResolvedAiEntitlement) {
      return _PlanState.pending;
    }

    // Both sources have answered and neither named a plan: free is now a
    // conclusion rather than a default.
    return _PlanState.free;
  }

  /// True only when the subscription record positively says "active".
  bool _hasSubscriptionEvidence(Map<String, dynamic>? user) {
    final dynamic explicitActive =
        user?['isActive'] ?? user?['isSubscriptionActive'];
    if (explicitActive is bool && explicitActive) return true;
    if (explicitActive is String && explicitActive.toLowerCase() == 'true') {
      return true;
    }

    final dynamic raw = user?['subscriptionEndDate'] ?? user?['endDate'];
    if (raw == null) return false;
    final String value = raw.toString().trim();
    if (value.isEmpty || value.toLowerCase() == 'null') return false;

    final DateTime? parsed = DateTime.tryParse(value);
    if (parsed == null) return false;
    final DateTime now = parsed.isUtc ? DateTime.now().toUtc() : DateTime.now();
    return parsed.isAfter(now);
  }

  /// Human-readable name for the plan, from the same code the badge uses.
  String _planLabel(Map<String, dynamic>? user, _PlanState state) {
    if (state == _PlanState.pending) {
      return _kPending;
    }
    final String? planCode = _livePlanCode(user);
    if (planCode != null && planCode != 'UNKNOWN') {
      switch (planCode) {
        case 'FREE':
          return context.tr('profile.plan.free');
        case 'FREE_TRIAL_7D':
          return context.tr('profile.plan.trial');
        default:
          // A paid tier the app has no name for. The server's own code is the
          // honest label, and it is the same word in every language.
          return planCode.replaceAll('_', ' ');
      }
    }
    return state == _PlanState.paid
        ? context.tr('profile.plan.pro')
        : context.tr('profile.plan.free');
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final AppStateProvider appState = context.watch<AppStateProvider>();
    final Map<String, dynamic>? user = appState.userInfo;
    final _PlanState planState = _planState(appState, user);

    return ColoredBox(
      color: t.ground,
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            NfSpace.s16,
            NfSpace.s16,
            NfSpace.s16,
            NfSpace.s26,
          ),
          children: <Widget>[
            _buildHeader(t, appState, user, planState),
            const SizedBox(height: NfSpace.s20),
            _buildStatGrid(t, appState),
            const SizedBox(height: NfSpace.s20),
            _buildAiTokenCard(t),
            const SizedBox(height: NfSpace.s20),
            _buildSettingsCard(t),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    NfTokens t,
    AppStateProvider appState,
    Map<String, dynamic>? user,
    _PlanState planState,
  ) {
    final String name = _displayName(appState, user);
    final int level = _asInt(appState.userStats['level']);
    final String subtitle =
        '${_planLabel(user, planState)} · ${context.tr('common.level')} $level';

    return Row(
      children: <Widget>[
        _Avatar(initials: _initials(name), tokens: t),
        const SizedBox(width: NfSpace.s14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NfTokens.display(size: NfFont.s20, color: t.ink),
              ),
              const SizedBox(height: NfSpace.s4),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NfTokens.body(size: NfFont.s13, color: t.inkMuted),
              ),
            ],
          ),
        ),
        // Nothing to upsell to a learner who already pays — and nothing to
        // upsell to one we have not identified yet either. "Manage
        // subscription" on the card below stays reachable in every state, so
        // withholding this costs nobody the route to the paywall.
        if (planState == _PlanState.free) ...<Widget>[
          const SizedBox(width: NfSpace.s12),
          NfPrimaryButton(
            label: context.tr('profile.upgrade'),
            expand: false,
            // The header is a dense row; the secondary height keeps the button
            // from towering over the two lines of text next to it and still
            // clears the 44px tap floor.
            height: NfSize.buttonSecondary,
            onPressed: widget.onManageSubscription,
          ),
        ],
      ],
    );
  }

  Widget _buildStatGrid(NfTokens t, AppStateProvider appState) {
    final Map<String, dynamic> stats = appState.userStats;
    final int streak = _asInt(stats['streak']);
    final int totalXp = _asInt(stats['xp']);
    final int level = _asInt(stats['level']);

    // allWords is the live collection; userStats is the cached count that
    // survives an offline start. Prefer the list, fall back to the cache.
    final int words = appState.allWords.isNotEmpty
        ? appState.allWords.length
        : _asInt(stats['totalWords']);
    final bool wordsPending = appState.isLoadingWords && words == 0;

    return Column(
      children: <Widget>[
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: _StatCard(
                  icon: Icons.local_fire_department_outlined,
                  accent: t.streakText,
                  tint: t.streakSoft,
                  value: '$streak',
                  label: context.tr('session.summary.streak'),
                ),
              ),
              const SizedBox(width: NfSpace.s12),
              Expanded(
                child: _StatCard(
                  icon: Icons.menu_book_outlined,
                  accent: t.primaryText,
                  tint: t.primarySoft,
                  value: wordsPending ? _kPending : '$words',
                  label: context.tr('nav.words'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: NfSpace.s12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: _StatCard(
                  icon: Icons.military_tech_outlined,
                  accent: t.correct,
                  tint: t.correctSoft,
                  value: '$level',
                  label: '${context.tr('common.level')} · $totalXp XP',
                ),
              ),
              const SizedBox(width: NfSpace.s12),
              Expanded(
                child: _StatCard(
                  icon: Icons.bolt_outlined,
                  accent: t.primaryText,
                  tint: t.primarySoft,
                  value: _tokensStatValue(),
                  label: context.tr('profile.ai.left'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The tokens tile must not claim "0 left" while the request is still in
  /// flight or after it failed — that is the same lie the plan badge used to
  /// tell. An em dash says "not known" instead.
  ///
  /// Shows the percentage, not the raw count: the meter card stopped exposing
  /// token numbers, and a stat tile that still said "8000" would reintroduce
  /// them through the side door.
  String _tokensStatValue() {
    if (_isQuotaLoading || _quotaErrorKey != null) return _kPending;
    if (_aiTokenLimit <= 0) return _kPending;
    return _percentLeftLabel();
  }

  int _percentLeft() => (_aiRemainingRatio * 100).clamp(0.0, 100.0).round();

  /// A sliver of quota left still rounds to 0%; saying "0%" while something
  /// remains reads as a bug, so it becomes "<1%".
  ///
  /// Even the sign goes through a key: Turkish writes it in front of the
  /// number (%42), English and German behind it.
  String _percentLeftLabel() {
    final int percent = _percentLeft();
    if (_aiTokensRemaining > 0 && percent == 0) {
      return context.tr('common.percentUnderOne');
    }
    return context.tr('common.percent').replaceAll('{n}', '$percent');
  }

  Widget _buildAiTokenCard(NfTokens t) {
    return NfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _IconTile(
                icon: Icons.bolt_outlined,
                accent: t.primaryText,
                tint: t.primarySoft,
              ),
              const SizedBox(width: NfSpace.s12),
              Expanded(
                child: Text(
                  context.tr('profile.ai.title'),
                  style: NfTokens.display(size: NfFont.s16, color: t.ink),
                ),
              ),
              _TapIcon(
                icon: Icons.refresh_rounded,
                color: t.inkMuted,
                semanticsLabel: context.tr('profile.ai.refresh'),
                onTap: _isQuotaLoading ? null : _loadAiQuota,
              ),
            ],
          ),
          const SizedBox(height: NfSpace.s14),
          ..._buildAiTokenBody(t),
        ],
      ),
    );
  }

  List<Widget> _buildAiTokenBody(NfTokens t) {
    if (_isQuotaLoading) {
      return <Widget>[
        const NfProgressBar(value: 0, animate: false),
        const SizedBox(height: NfSpace.s10),
        Text(
          context.tr('common.loading'),
          style: NfTokens.body(size: NfFont.s125, color: t.inkMuted),
        ),
      ];
    }

    if (_quotaErrorKey case final String key) {
      return <Widget>[
        _RetryRow(message: context.tr(key), tokens: t, onRetry: _loadAiQuota),
      ];
    }

    if (_aiTokenLimit <= 0) {
      return <Widget>[
        Text(
          context.tr('profile.ai.noQuota'),
          style: NfTokens.body(size: NfFont.s125, color: t.inkMuted),
        ),
      ];
    }

    final int percent = _percentLeft();
    // Below a fifth of the allowance the learner hits the wall inside one
    // sitting, so the warning chip appears there rather than at the moment
    // the last token goes. Above that line the meter stays quiet on purpose:
    // no raw token counts, no usage estimates — just how much is left.
    final bool runningLow = _aiTokensRemaining <= 0 || percent < 20;
    final String percentLabel = context
        .tr('profile.ai.percentLeft')
        .replaceAll('{p}', _percentLeftLabel());

    return <Widget>[
      Row(
        children: <Widget>[
          Expanded(
            child: Text(
              percentLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NfTokens.body(
                size: NfFont.s135,
                weight: NfTokens.bodyEmphasisWeight,
                color: t.inkMuted,
              ),
            ),
          ),
          if (runningLow) ...<Widget>[
            const SizedBox(width: NfSpace.s8),
            NfChip(
              label: context.tr('profile.ai.runningLow'),
              icon: Icons.bolt_outlined,
              variant: NfChipVariant.streak,
              dense: true,
            ),
          ],
        ],
      ),
      const SizedBox(height: NfSpace.s10),
      NfProgressBar(
        value: _aiRemainingRatio,
        height: NfSize.progressQuiet,
        semanticsLabel: percentLabel,
      ),
    ];
  }

  Widget _buildSettingsCard(NfTokens t) {
    final bool isDark = t.isDark;
    final String languageCode =
        context.l10n.locale.languageCode.toUpperCase();

    return NfCard(
      padding: EdgeInsets.zero,
      clipContent: true,
      child: Column(
        children: <Widget>[
          _SettingsRow(
            icon: Icons.workspace_premium_outlined,
            label: context.tr('profile.manageSubscription'),
            tokens: t,
            onTap: widget.onManageSubscription,
          ),
          _Divider(tokens: t),
          _SettingsRow(
            icon: Icons.notifications_none_rounded,
            label: context.tr('profile.notificationPrefs'),
            tokens: t,
            onTap: widget.onOpenNotifications,
          ),
          _Divider(tokens: t),
          // Labelled as settings, not as "Language". The language code stays as
          // the trailing value because it is genuinely useful, but it is a
          // detail of the destination, not its name.
          _SettingsRow(
            icon: Icons.settings_outlined,
            label: context.tr('settings.title'),
            tokens: t,
            trailing: Text(
              languageCode,
              style: NfTokens.body(size: NfFont.s13, color: t.inkMuted),
            ),
            onTap: widget.onOpenSettings,
          ),
          // A "switch to classic design" row used to sit here, from when this
          // frontend was a preview. It is gone with the preview: the preference
          // it wrote is no longer read, so the row would have looked like a
          // choice and done nothing.
          _Divider(tokens: t),
          _SettingsRow(
            icon: isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
            label: context.tr('settings.appearance'),
            tokens: t,
            // The chip is the value, not a second control: it has no onTap, so
            // the tap falls through to the row and toggles the palette.
            trailing: NfChip(
              label: context.tr(
                isDark
                    ? 'settings.appearance.dark'
                    : 'settings.appearance.light',
              ),
              variant: NfChipVariant.selected,
              dense: true,
            ),
            showChevron: false,
            onTap: widget.onToggleBrightness,
          ),
        ],
      ),
    );
  }

  String _displayName(AppStateProvider appState, Map<String, dynamic>? user) {
    final String fromUser = user?['displayName']?.toString().trim() ?? '';
    if (fromUser.isNotEmpty) return fromUser;
    final String fromState = appState.userName.trim();
    if (fromState.isNotEmpty) return fromState;
    return context.tr('profile.defaultName');
  }

  /// Up to two initials: first letter of the first and last name parts.
  String _initials(String name) {
    final List<String> parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((String part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return _firstLetter(parts.first);
    return '${_firstLetter(parts.first)}${_firstLetter(parts.last)}';
  }

  /// First *rune*, not first code unit: `substring(0, 1)` on a name that opens
  /// with an astral character would hand back half a surrogate pair.
  String _firstLetter(String part) =>
      String.fromCharCode(part.runes.first).toUpperCase();
}

/// Stand-in for a number we do not know yet. Never shown as a real zero.
const String _kPending = '—';

/// What is known about the learner's plan. [pending] is the state before any
/// source has answered — it is not "free", and must never be rendered as one.
enum _PlanState { pending, free, paid }

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

// -----------------------------------------------------------------------------
// Pieces
// -----------------------------------------------------------------------------

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initials, required this.tokens});

  final String initials;
  final NfTokens tokens;

  static const double _size = 56;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tokens.primarySoft,
        shape: BoxShape.circle,
        border: Border.fromBorderSide(tokens.sideOf(tokens.primary)),
      ),
      child: Text(
        initials,
        style: NfTokens.display(size: NfFont.s20, color: tokens.primaryText),
      ),
    );
  }
}

/// The square behind an icon: soft tint, small radius, no border — a 2px
/// outline on a 34px tile inside an already-outlined card is noise.
class _IconTile extends StatelessWidget {
  const _IconTile({
    required this.icon,
    required this.accent,
    required this.tint,
  });

  final IconData icon;
  final Color accent;
  final Color tint;

  static const double _size = 34;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint,
        borderRadius: NfRadius.iconTileAll,
      ),
      child: Icon(icon, size: 18, color: accent),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.accent,
    required this.tint,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color accent;
  final Color tint;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    return NfCard(
      padding: const EdgeInsets.all(NfSpace.s14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _IconTile(icon: icon, accent: accent, tint: tint),
          const SizedBox(height: NfSpace.s10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: NfTokens.display(size: NfFont.s23, color: t.ink),
          ),
          const SizedBox(height: NfSpace.s4),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: NfTokens.body(size: NfFont.s125, color: t.inkMuted),
          ),
        ],
      ),
    );
  }
}

/// A failed quota read, with the whole row acting as the retry target.
class _RetryRow extends StatelessWidget {
  const _RetryRow({
    required this.message,
    required this.tokens,
    required this.onRetry,
  });

  final String message;
  final NfTokens tokens;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onRetry,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: NfSize.minTap),
            child: Row(
              children: <Widget>[
                Icon(Icons.error_outline_rounded,
                    size: 18, color: tokens.wrong),
                const SizedBox(width: NfSpace.s8),
                Expanded(
                  child: Text(
                    message,
                    style: NfTokens.body(
                      size: NfFont.s125,
                      color: tokens.inkMuted,
                    ),
                  ),
                ),
                const SizedBox(width: NfSpace.s8),
                Text(
                  context.tr('common.retry'),
                  style: NfTokens.display(
                    size: NfFont.s13,
                    color: tokens.primaryText,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A bare icon with a full [NfSize.minTap] hit area around it.
class _TapIcon extends StatelessWidget {
  const _TapIcon({
    required this.icon,
    required this.color,
    required this.semanticsLabel,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String semanticsLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: MouseRegion(
        cursor: onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: NfSize.minTap,
            height: NfSize.minTap,
            child: Icon(
              icon,
              size: 20,
              color: onTap == null ? t.inkFaint : color,
            ),
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.tokens});

  final NfTokens tokens;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: NfStroke.border,
      child: ColoredBox(color: tokens.border),
    );
  }
}

/// One row of the settings list.
///
/// Feedback is a background tint rather than a scale or a ripple: a row that
/// shrinks under the finger looks broken inside a card that does not.
class _SettingsRow extends StatefulWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.tokens,
    required this.onTap,
    this.trailing,
    this.showChevron = true,
  });

  final IconData icon;
  final String label;
  final NfTokens tokens;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool showChevron;

  @override
  State<_SettingsRow> createState() => _SettingsRowState();
}

class _SettingsRowState extends State<_SettingsRow> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onTap == null || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final NfTokens t = widget.tokens;
    final bool enabled = widget.onTap != null;

    final Widget row = Container(
      color: _pressed ? t.raised : t.surface,
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.symmetric(
        horizontal: NfSpace.s16,
        vertical: NfSpace.s12,
      ),
      child: Row(
        children: <Widget>[
          _IconTile(
            icon: widget.icon,
            accent: enabled ? t.primaryText : t.inkFaint,
            tint: t.primarySoft,
          ),
          const SizedBox(width: NfSpace.s14),
          Expanded(
            child: Text(
              widget.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: NfTokens.body(
                size: NfFont.s15,
                weight: NfTokens.bodyEmphasisWeight,
                color: enabled ? t.ink : t.inkFaint,
              ),
            ),
          ),
          if (widget.trailing != null) ...<Widget>[
            const SizedBox(width: NfSpace.s10),
            widget.trailing!,
          ],
          if (widget.showChevron) ...<Widget>[
            const SizedBox(width: NfSpace.s8),
            Icon(Icons.chevron_right_rounded, size: 20, color: t.inkFaint),
          ],
        ],
      ),
    );

    if (!enabled) return row;

    return Semantics(
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          onTap: widget.onTap,
          child: row,
        ),
      ),
    );
  }
}
