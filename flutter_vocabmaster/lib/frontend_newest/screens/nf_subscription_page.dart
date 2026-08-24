import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/app_state_provider.dart';
import '../../services/analytics_service.dart';
import '../../services/auth_service.dart';
import '../../services/subscription_service.dart';
import '../theme/nf_tokens.dart';
import '../widgets/nf_button.dart';
import '../widgets/nf_card.dart';
import '../widgets/nf_chip.dart';

/// The paywall in the new frontend's paint.
///
/// This is a RESTYLE of `lib/screens/subscription_page.dart`, not a rewrite:
/// every method that touches money — the purchase stream wiring, the store
/// product lookup, plan selection, demo mode, restore, the owned-purchase sync
/// and all their analytics — is carried over verbatim. Only the widget tree
/// changed: plans sit in [NfCard]s, the learner picks one, and a single
/// [NfPrimaryButton] starts the purchase.
///
/// User-facing copy now goes through `context.tr`. The legacy screen picked
/// between a Turkish and an English literal, which meant a German learner read
/// English on the one screen where money changes hands; the keys carry all
/// three languages.
class NfSubscriptionPage extends StatefulWidget {
  const NfSubscriptionPage({super.key});

  @override
  State<NfSubscriptionPage> createState() => _NfSubscriptionPageState();
}

class _NfSubscriptionPageState extends State<NfSubscriptionPage> {
  final SubscriptionService _subscriptionService = SubscriptionService();
  final AuthService _authService = AuthService();
  List<SubscriptionPlan> _plans = [];
  Map<String, ProductDetails> _storeProductsById = const {};
  bool _isLoading = true;
  bool _isPurchasing = false;
  bool _hasActiveSubscription = false;
  String? _subscriptionEndDateLabel;
  String? _pendingPurchasePlanName;

  /// Which plan the single CTA will buy. Defaults to the annual plan once the
  /// list loads, because that is the one the screen recommends.
  SubscriptionPlan? _selectedPlan;

  static const List<String> _visiblePlanNames = [
    'PRO_MONTHLY',
    'PRO_ANNUAL',
  ];
  final bool _enableMobileIap =
      const bool.fromEnvironment('ENABLE_MOBILE_IAP', defaultValue: true);

  @override
  void initState() {
    super.initState();
    // Same analytics source string as the legacy page: funnels comparing the
    // two frontends still need one name for "the paywall was shown".
    AnalyticsService.logPaywallShown(source: 'subscription_page');
    _initializeIAP();
    _loadPlans().then((_) => _syncOwnedPurchasesIfNeeded());
  }

  void _initializeIAP() {
    _subscriptionService.initializePurchaseStream();
    _subscriptionService.onPurchaseSuccess = (message) async {
      if (!mounted) return;
      setState(() => _isPurchasing = false);
      await AnalyticsService.logPurchaseCompleted(
        planName: _pendingPurchasePlanName,
      );
      _pendingPurchasePlanName = null;
      await _loadPlans();
      if (!mounted) return;
      _showSuccessDialog(message);
    };
    _subscriptionService.onPurchaseError = (error) {
      if (!mounted) return;
      AnalyticsService.logPurchaseFailed(
        planName: _pendingPurchasePlanName,
        reason: error,
      );
      _pendingPurchasePlanName = null;
      final lower = error.toLowerCase();
      final syncing =
          lower.contains('senkronize') || lower.contains('aktariliyor');
      setState(() => _isPurchasing = false);
      _showSnack(error, warning: syncing, error: !syncing);
      if (syncing) {
        Future.delayed(
          const Duration(seconds: 2),
          () async {
            if (mounted) {
              await _loadPlans();
            }
          },
        );
      }
    };
  }

  Future<void> _syncOwnedPurchasesIfNeeded() async {
    if (!mounted ||
        _hasActiveSubscription ||
        _isPurchasing ||
        _subscriptionDemoMode ||
        !_enableMobileIap ||
        (!Platform.isAndroid && !Platform.isIOS)) {
      return;
    }

    try {
      final started = await _subscriptionService.syncOwnedPurchases();
      if (!started) {
        return;
      }
      // Split from the check above so the analyzer can see the guard that
      // makes the `context` read below safe.
      if (!mounted) {
        return;
      }
      _showSnack(
        context.tr('subscription.snack.checkingStore'),
        warning: true,
      );
    } catch (e) {
      debugPrint('Silent purchase sync failed: $e');
    }
  }

  @override
  void dispose() {
    _subscriptionService.dispose();
    super.dispose();
  }

  Future<void> _loadPlans() async {
    try {
      final plans = await _subscriptionService.getPlans();
      final storeProductsById = await _loadStoreProductsById();
      var active = false;
      String? endDateRaw;
      try {
        final status = await _subscriptionService.getUserSubscriptionStatus();
        active = _isActiveSubscription(status);
        endDateRaw = _extractSubscriptionEnd(status);
        if (active) {
          await _authService.refreshProfile();
          if (mounted) {
            await context.read<AppStateProvider>().refreshUserData();
          }
        }
      } catch (e) {
        debugPrint('Subscription status refresh failed: $e');
      }
      if (!mounted) return;
      setState(() {
        _plans = _selectVisiblePlans(plans);
        _storeProductsById = storeProductsById;
        _hasActiveSubscription = active;
        // Formatted here rather than up in the try: the month name comes out
        // of the l10n map, and reading it needs a context that is only known
        // to be alive past the `mounted` check above.
        _subscriptionEndDateLabel = endDateRaw == null
            ? null
            : _formatReadableDate(context, endDateRaw);
        _isLoading = false;
        // Keep an existing choice across reloads; otherwise recommend annual.
        if (_selectedPlan == null ||
            !_plans.any((p) => p.id == _selectedPlan!.id)) {
          _selectedPlan = _plans.isEmpty
              ? null
              : _plans.firstWhere(
                  (p) => p.name.contains('ANNUAL'),
                  orElse: () => _plans.first,
                );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnack(
        context.tr('subscription.err.load').replaceAll('{error}', '$e'),
        error: true,
      );
    }
  }

  Future<Map<String, ProductDetails>> _loadStoreProductsById() async {
    if (!_canUseStoreProducts) {
      return const {};
    }

    try {
      final products = await _subscriptionService.getStoreProducts();
      return {
        for (final product in products) product.id: product,
      };
    } catch (e) {
      debugPrint('Store product price lookup failed: $e');
      return const {};
    }
  }

  bool get _canUseStoreProducts =>
      _enableMobileIap &&
      !_subscriptionDemoMode &&
      (Platform.isAndroid || Platform.isIOS);

  List<SubscriptionPlan> _selectVisiblePlans(List<SubscriptionPlan> plans) {
    final visiblePlans =
        plans.where((plan) => _visiblePlanNames.contains(plan.name)).toList()
          ..sort(
            (a, b) => _visiblePlanNames
                .indexOf(a.name)
                .compareTo(_visiblePlanNames.indexOf(b.name)),
          );

    if (visiblePlans.isNotEmpty) {
      return visiblePlans;
    }

    return plans.where((plan) => plan.name != 'FREE').toList()
      ..sort((a, b) => a.price.compareTo(b.price));
  }

  String _displayPriceLabel(SubscriptionPlan plan) {
    final storePrice = _storeProductForPlan(plan)?.price.trim();
    if (storePrice != null && storePrice.isNotEmpty) {
      return storePrice;
    }

    final price = plan.price;
    final priceText =
        price % 1 == 0 ? price.toStringAsFixed(0) : price.toStringAsFixed(2);
    final currency = plan.currency;
    return '$priceText $currency';
  }

  ProductDetails? _storeProductForPlan(SubscriptionPlan plan) {
    final productId =
        Platform.isIOS ? plan.appleProductId : plan.googlePlayProductId;
    if (productId.isEmpty) {
      return null;
    }
    return _storeProductsById[productId];
  }

  double _analyticsPriceForPlan(SubscriptionPlan plan) {
    return _storeProductForPlan(plan)?.rawPrice ?? plan.price;
  }

  String _analyticsCurrencyForPlan(SubscriptionPlan plan) {
    final currencyCode = _storeProductForPlan(plan)?.currencyCode.trim();
    if (currencyCode != null && currencyCode.isNotEmpty) {
      return currencyCode;
    }
    return plan.currency;
  }

  bool _isActiveSubscription(Map<String, dynamic> status) {
    final active = status['isActive'] ?? status['subscriptionActive'];
    if (active is bool) {
      return active;
    }
    final end = status['subscriptionEndDate'] ?? status['endDate'];
    if (end == null) {
      return false;
    }
    final text = end.toString().trim().toLowerCase();
    return text.isNotEmpty && text != 'null';
  }

  /// The raw end-date string the server sent, or null when it sent nothing
  /// usable. Formatting happens later, where a [BuildContext] is in hand.
  String? _extractSubscriptionEnd(Map<String, dynamic> status) {
    final end = status['subscriptionEndDate'] ?? status['endDate'];
    if (end == null) {
      return null;
    }
    final text = end.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') {
      return null;
    }
    return text;
  }

  /// Raw ISO timestamp → readable, localized date. Unparseable input is shown
  /// as-is rather than breaking the screen.
  ///
  /// Both halves are localized: the month name, and the order the day, month
  /// and year go in — English puts the month first, Turkish and German the
  /// day.
  String _formatReadableDate(BuildContext context, String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      return raw;
    }
    return context
        .tr('common.dateLong')
        .replaceAll('{day}', '${parsed.day}')
        .replaceAll('{month}', context.tr('common.month.${parsed.month}'))
        .replaceAll('{year}', '${parsed.year}');
  }

  // Payment demo mode can be enabled only via build-time flag for test builds:
  // flutter run --dart-define=SUBSCRIPTION_DEMO_MODE=true
  static const bool _subscriptionDemoMode =
      bool.fromEnvironment('SUBSCRIPTION_DEMO_MODE', defaultValue: false);

  void _startPayment(SubscriptionPlan plan) async {
    if (_isPurchasing) return;

    _pendingPurchasePlanName = plan.name;
    await AnalyticsService.logPurchaseStarted(
      planName: plan.name,
      currency: _analyticsCurrencyForPlan(plan),
      price: _analyticsPriceForPlan(plan),
    );

    setState(() => _isPurchasing = true);

    // DEMO MODE: Skip payment entirely
    if (_subscriptionDemoMode) {
      _activateDemoSubscription(plan);
      return;
    }

    if (!Platform.isAndroid && !Platform.isIOS) {
      await AnalyticsService.logPurchaseFailed(
        planName: plan.name,
        reason: 'unsupported_platform',
      );
      if (!mounted) return;
      _pendingPurchasePlanName = null;
      setState(() => _isPurchasing = false);
      _showSnack(context.tr('subscription.err.platform'), warning: true);
      return;
    }

    if (!_enableMobileIap) {
      await AnalyticsService.logPurchaseFailed(
        planName: plan.name,
        reason: 'mobile_iap_disabled',
      );
      if (!mounted) return;
      _pendingPurchasePlanName = null;
      setState(() => _isPurchasing = false);
      _showSnack(context.tr('subscription.err.iapDisabled'), warning: true);
      return;
    }

    try {
      final success = await _subscriptionService.purchaseWithIAP(plan);
      if (!mounted) return;
      if (!success) {
        await AnalyticsService.logPurchaseFailed(
          planName: plan.name,
          reason: 'purchase_not_started',
        );
        _pendingPurchasePlanName = null;
        setState(() => _isPurchasing = false);
      }
      // Purchase result will come through the stream callback
    } catch (e) {
      if (!mounted) return;
      await AnalyticsService.logPurchaseFailed(
        planName: plan.name,
        reason: e.toString(),
      );
      if (!mounted) return;
      _pendingPurchasePlanName = null;
      setState(() => _isPurchasing = false);
      _showSnack(
        context.tr('subscription.err.payment').replaceAll('{error}', '$e'),
        error: true,
      );
    }
  }

  void _activateDemoSubscription(SubscriptionPlan plan) async {
    try {
      final result =
          await _subscriptionService.activateDemoSubscription(plan.id);
      if (!mounted) return;
      setState(() => _isPurchasing = false);
      // Read before the await below, so the context is one the guard above
      // has already vouched for.
      final String fallback = context.tr('subscription.demo.active');
      await AnalyticsService.logPurchaseCompleted(planName: plan.name);
      _showSuccessDialog(result['message'] ?? fallback);
    } catch (e) {
      if (!mounted) return;
      await AnalyticsService.logPurchaseFailed(
        planName: plan.name,
        reason: 'demo:${e.toString()}',
      );
      if (!mounted) return;
      setState(() => _isPurchasing = false);
      _showSnack(
        context.tr('subscription.err.demo').replaceAll('{error}', '$e'),
        error: true,
      );
    }
  }

  Future<void> _restorePurchases() async {
    if (_isPurchasing) return;
    setState(() => _isPurchasing = true);
    try {
      await _subscriptionService.restorePurchases();
      if (!mounted) return;
      setState(() => _isPurchasing = false);
      _showSnack(
        context.tr('subscription.snack.restoreStarted'),
        warning: true,
      );
      Future.delayed(
        const Duration(seconds: 2),
        () async {
          if (mounted) {
            await _loadPlans();
          }
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPurchasing = false);
      _showSnack(
        context.tr('subscription.err.restore').replaceAll('{error}', '$e'),
        error: true,
      );
    }
  }

  /// One snackbar shape for the whole screen. Warning states are amber and
  /// errors are red — the same two semantic tokens the rest of the frontend
  /// uses for them.
  void _showSnack(String message, {bool warning = false, bool error = false}) {
    final NfTokens t = NfTokens.of(context);
    final Color background = error
        ? t.wrong
        : warning
            ? t.streakText
            : t.ink;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: NfTokens.body(size: NfFont.s135, color: t.primaryInk),
        ),
        backgroundColor: background,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccessDialog([String? message]) {
    // Captured from the page, not from the dialog's own context. A dialog route
    // is built above this page's NfTheme, so resolving there falls back to the
    // device brightness — a white congratulations box over a dark page.
    final NfTokens t = NfTokens.of(context);
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: t.surface,
          shape: RoundedRectangleBorder(
            borderRadius: NfRadius.cardAll,
            side: t.side,
          ),
          title: Text(
            context.tr('subscription.success.title'),
            style: NfTokens.display(size: NfFont.s20, color: t.ink),
          ),
          content: Text(
            message ?? context.tr('subscription.success.body'),
            style: NfTokens.body(size: NfFont.s14, color: t.inkMuted),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                Navigator.pop(context); // Return to previous screen
              },
              child: Text(
                context.tr('common.ok'),
                style:
                    NfTokens.display(size: NfFont.s14, color: t.primaryText),
              ),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  /// The palette comes from the `NfThemeScope` the shell wraps this route in.
  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    return Scaffold(
      backgroundColor: t.ground,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NfSpace.s12,
                NfSpace.s8,
                NfSpace.s16,
                NfSpace.s4,
              ),
              child: Row(
                children: <Widget>[
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    iconSize: NfFont.s22,
                    color: t.ink,
                    icon: const Icon(Icons.arrow_back_rounded),
                    tooltip:
                        MaterialLocalizations.of(context).backButtonTooltip,
                  ),
                  const SizedBox(width: NfSpace.s4),
                  Expanded(
                    child: Text(
                      context.tr('subscription.title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NfTokens.display(size: NfFont.s20, color: t.ink),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody(t)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(NfTokens t) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          strokeWidth: NfStroke.border,
          color: t.primary,
        ),
      );
    }

    final SubscriptionPlan? selected = _selectedPlan;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        NfSpace.s16,
        NfSpace.s8,
        NfSpace.s16,
        NfSpace.s26,
      ),
      children: <Widget>[
        if (_subscriptionDemoMode) ...<Widget>[
          NfCard(
            backgroundColor: t.streakSoft,
            borderColor: t.streak,
            padding: const EdgeInsets.symmetric(
              horizontal: NfSpace.s14,
              vertical: NfSpace.s10,
            ),
            child: Text(
              context.tr('subscription.demo.banner'),
              textAlign: TextAlign.center,
              style: NfTokens.body(
                size: NfFont.s12,
                weight: NfTokens.bodyEmphasisWeight,
                color: t.streakText,
              ),
            ),
          ),
          const SizedBox(height: NfSpace.s16),
        ],
        Text(
          context.tr('subscription.hero.title'),
          textAlign: TextAlign.center,
          style: NfTokens.display(size: NfFont.s25, color: t.ink),
        ),
        const SizedBox(height: NfSpace.s8),
        Text(
          context.tr('subscription.hero.subtitle'),
          textAlign: TextAlign.center,
          style: NfTokens.body(size: NfFont.s145, color: t.inkMuted),
        ),
        const SizedBox(height: NfSpace.s20),
        if (_hasActiveSubscription) ...<Widget>[
          NfCard(
            backgroundColor: t.correctSoft,
            borderColor: t.correct,
            padding: const EdgeInsets.all(NfSpace.s14),
            child: Row(
              children: <Widget>[
                Icon(Icons.verified_outlined, size: 20, color: t.correct),
                const SizedBox(width: NfSpace.s10),
                Expanded(
                  child: Text(
                    _subscriptionEndDateLabel == null
                        ? context.tr('subscription.active')
                        : context.tr('subscription.activeUntil').replaceAll(
                              '{date}',
                              _subscriptionEndDateLabel!,
                            ),
                    style: NfTokens.body(
                      size: NfFont.s135,
                      weight: NfTokens.bodyEmphasisWeight,
                      color: t.correct,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: NfSpace.s16),
        ],
        if (_plans.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: NfSpace.s26),
            child: Text(
              context.tr('subscription.empty'),
              textAlign: TextAlign.center,
              style: NfTokens.body(size: NfFont.s145, color: t.inkMuted),
            ),
          )
        else ...<Widget>[
          for (final SubscriptionPlan plan in _plans) ...<Widget>[
            _buildPlanCard(t, plan),
            const SizedBox(height: NfSpace.s12),
          ],
          const SizedBox(height: NfSpace.s8),
          NfPrimaryButton(
            label: context.tr(
              _hasActiveSubscription
                  ? 'subscription.cta.active'
                  : 'subscription.cta.upgrade',
            ),
            busy: _isPurchasing,
            onPressed: _hasActiveSubscription || selected == null
                ? null
                : () => _startPayment(selected),
          ),
          const SizedBox(height: NfSpace.s12),
          // The backend grants every new account a 7-day trial AI quota
          // (FREE_TRIAL_7D); the paywall keeps naming it so the trial does
          // conversion work instead of being given away silently.
          Text(
            key: const ValueKey('paywall-trial-note'),
            context.tr('subscription.trialNote'),
            textAlign: TextAlign.center,
            style: NfTokens.body(size: NfFont.s12, color: t.inkFaint),
          ),
        ],
        if ((Platform.isAndroid || Platform.isIOS) && _enableMobileIap) ...<Widget>[
          const SizedBox(height: NfSpace.s16),
          NfSecondaryButton(
            label: context.tr('subscription.restore'),
            onPressed:
                _isPurchasing ? null : () => unawaited(_restorePurchases()),
          ),
        ],
      ],
    );
  }

  Widget _buildPlanCard(NfTokens t, SubscriptionPlan plan) {
    if (plan.name == 'FREE') return const SizedBox.shrink();

    final bool isSelected = _selectedPlan?.id == plan.id;
    final bool isAnnual = plan.name.contains('ANNUAL');
    final String periodKey = plan.durationDays == 30
        ? 'subscription.perMonth'
        : 'subscription.perYear';

    return NfCard(
      backgroundColor: isSelected ? t.primarySoft : t.surface,
      borderColor: isSelected ? t.primary : t.border,
      onTap: _hasActiveSubscription
          ? null
          : () => setState(() => _selectedPlan = plan),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  context.tr(
                    isAnnual
                        ? 'subscription.plan.annual'
                        : 'subscription.plan.monthly',
                  ),
                  style: NfTokens.display(
                    size: NfFont.s17,
                    color: isSelected ? t.primaryText : t.ink,
                  ),
                ),
              ),
              if (isAnnual)
                NfChip(
                  label: context.tr('subscription.plan.save40'),
                  variant: NfChipVariant.streak,
                  dense: true,
                ),
            ],
          ),
          const SizedBox(height: NfSpace.s10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Flexible(
                child: Text(
                  _displayPriceLabel(plan),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NfTokens.display(size: NfFont.s25, color: t.ink),
                ),
              ),
              Text(
                // The leading space belongs to the layout, not the copy, so
                // it stays out of the translation.
                ' ${context.tr(periodKey)}',
                style: NfTokens.body(size: NfFont.s14, color: t.inkMuted),
              ),
            ],
          ),
          const SizedBox(height: NfSpace.s14),
          _buildPerk(t, context.tr('subscription.perk.daily')),
          _buildPerk(t, context.tr('subscription.perk.sentences')),
          _buildPerk(t, context.tr('subscription.perk.speaking')),
        ],
      ),
    );
  }

  Widget _buildPerk(NfTokens t, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: NfSpace.s6),
      child: Row(
        children: <Widget>[
          Icon(Icons.check_circle_outline_rounded,
              size: 16, color: t.correct),
          const SizedBox(width: NfSpace.s8),
          Expanded(
            child: Text(
              text,
              style: NfTokens.body(size: NfFont.s135, color: t.inkMuted),
            ),
          ),
        ],
      ),
    );
  }
}
