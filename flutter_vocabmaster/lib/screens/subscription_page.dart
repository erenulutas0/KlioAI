import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../services/auth_service.dart';
import '../services/analytics_service.dart';
import '../services/locale_text_service.dart';
import '../services/subscription_service.dart';
import '../widgets/modern_background.dart';

class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  final SubscriptionService _subscriptionService = SubscriptionService();
  final AuthService _authService = AuthService();
  List<SubscriptionPlan> _plans = [];
  Map<String, ProductDetails> _storeProductsById = const {};
  bool _isLoading = true;
  bool _isPurchasing = false;
  bool _hasActiveSubscription = false;
  String? _subscriptionEndDateLabel;
  String? _pendingPurchasePlanName;
  static const List<String> _visiblePlanNames = [
    'PRO_MONTHLY',
    'PRO_ANNUAL',
  ];
  final bool _enableMobileIap =
      const bool.fromEnvironment('ENABLE_MOBILE_IAP', defaultValue: true);

  String _text(String tr, String en) => LocaleTextService.pick(tr, en);

  @override
  void initState() {
    super.initState();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: syncing ? Colors.orange : Colors.red,
        ),
      );
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
      if (!started || !mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_text(
            'Mevcut magaza aboneligi kontrol ediliyor...',
            'Checking your existing store subscription...',
          )),
          backgroundColor: Colors.orange,
        ),
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
      String? endDate;
      try {
        final status = await _subscriptionService.getUserSubscriptionStatus();
        active = _isActiveSubscription(status);
        endDate = _extractSubscriptionEnd(status);
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
        _subscriptionEndDateLabel = endDate;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_text('Hata: $e', 'Error: $e')),
        ),
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

  String? _extractSubscriptionEnd(Map<String, dynamic> status) {
    final end = status['subscriptionEndDate'] ?? status['endDate'];
    if (end == null) {
      return null;
    }
    final text = end.toString().trim();
    return text.isEmpty || text.toLowerCase() == 'null' ? null : text;
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
      _pendingPurchasePlanName = null;
      setState(() => _isPurchasing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_text(
            'Abonelik satin alma sadece mobil uygulamada desteklenir.',
            'Subscription purchases are supported only in the mobile app.',
          )),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!_enableMobileIap) {
      await AnalyticsService.logPurchaseFailed(
        planName: plan.name,
        reason: 'mobile_iap_disabled',
      );
      _pendingPurchasePlanName = null;
      setState(() => _isPurchasing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_text(
            'Bu buildde mobil satin alma kapali.',
            'Mobile purchases are disabled in this build.',
          )),
          backgroundColor: Colors.orange,
        ),
      );
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
      _pendingPurchasePlanName = null;
      setState(() => _isPurchasing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_text('Odeme hatasi: $e', 'Payment error: $e')),
        ),
      );
    }
  }

  void _activateDemoSubscription(SubscriptionPlan plan) async {
    try {
      final result =
          await _subscriptionService.activateDemoSubscription(plan.id);
      if (!mounted) return;
      setState(() => _isPurchasing = false);
      await AnalyticsService.logPurchaseCompleted(planName: plan.name);
      _showSuccessDialog(result['message'] ??
          _text('Demo abonelik aktif!', 'Demo subscription is active!'));
    } catch (e) {
      if (!mounted) return;
      await AnalyticsService.logPurchaseFailed(
        planName: plan.name,
        reason: 'demo:${e.toString()}',
      );
      setState(() => _isPurchasing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_text('Demo hatasi: $e', 'Demo error: $e')),
          backgroundColor: Colors.red,
        ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_text(
            'Geri yukleme baslatildi. Abonelik senkronu bekleniyor...',
            'Restore started. Waiting for subscription sync...',
          )),
          backgroundColor: Colors.orange,
        ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_text(
            'Geri yukleme hatasi: $e',
            'Restore error: $e',
          )),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showSuccessDialog([String? message]) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          _text('Tebrikler!', 'Congratulations!'),
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          message ??
              _text(
                'PRO uyeliginiz basariyla aktif edildi. Keyifle ogrenin!',
                'Your PRO membership is active. Enjoy learning!',
              ),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context); // Return to previous screen
            },
            child: Text(
              _text('Tamam', 'OK'),
              style: const TextStyle(color: Color(0xFF22D3EE)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          _text('PRO Uyelik', 'PRO Membership'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ModernBackground(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF22D3EE)))
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 100, 20, 20),
                child: Column(
                  children: [
                    if (_subscriptionDemoMode)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange),
                        ),
                        child: Text(
                          _text(
                            'DEMO ODEME MODU AKTIF',
                            'DEMO PAYMENT MODE ACTIVE',
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.orange,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    Text(
                      _text(
                        'AI destekli\ngunluk pratik',
                        'AI-powered\ndaily practice',
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _text(
                        'Cumle uretme, konusma ve tekrar tek planda.',
                        'Create sentences, practice speaking, and review in one plan.',
                      ),
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(color: Colors.white60, fontSize: 16),
                    ),
                    const SizedBox(height: 40),
                    if (_hasActiveSubscription)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.greenAccent),
                        ),
                        child: Text(
                          _subscriptionEndDateLabel == null
                              ? _text(
                                  'Aboneliginiz aktif.',
                                  'Your subscription is active.',
                                )
                              : _text(
                                  'Aboneliginiz aktif. Bitis: $_subscriptionEndDateLabel',
                                  'Your subscription is active. Ends: $_subscriptionEndDateLabel',
                                ),
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (_plans.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          _text(
                            'Abonelik plani su anda bulunamadi.',
                            'No subscription plan is available right now.',
                          ),
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 15),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      ..._plans.map((plan) => _buildPlanCard(plan)),
                    if ((Platform.isAndroid || Platform.isIOS) &&
                        _enableMobileIap)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: TextButton(
                          onPressed: _isPurchasing ? null : _restorePurchases,
                          child: Text(
                            _text(
                              'Satin alimlari geri yukle',
                              'Restore purchases',
                            ),
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildPlanCard(SubscriptionPlan plan) {
    bool isFree = plan.name == 'FREE';
    if (isFree) return const SizedBox.shrink(); // Don't show free in pro page

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      plan.name.contains('ANNUAL')
                          ? _text('Yillik Plan', 'Annual Plan')
                          : _text('Aylik Plan', 'Monthly Plan'),
                      style: const TextStyle(
                          color: Color(0xFF22D3EE),
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
                    if (plan.name.contains('ANNUAL'))
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12)),
                        child: Text(_text('%40 Tasarruf', 'Save 40%'),
                            style: const TextStyle(
                                color: Colors.amber,
                                fontSize: 12,
                                fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      _displayPriceLabel(plan),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold),
                    ),
                    Text(
                      plan.durationDays == 30
                          ? _text(' / ay', ' / month')
                          : _text(' / yil', ' / year'),
                      style:
                          const TextStyle(color: Colors.white60, fontSize: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildPerk(
                  Icons.check_circle,
                  _text(
                      'AI destekli gunluk pratik', 'AI-powered daily practice'),
                ),
                _buildPerk(
                  Icons.check_circle,
                  _text('Cumle uretme ve ceviri destegi',
                      'Sentence creation and translation support'),
                ),
                _buildPerk(
                  Icons.check_circle,
                  _text(
                      'Konusma ve tekrar modlari', 'Speaking and review modes'),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _hasActiveSubscription
                        ? null
                        : () => _startPayment(plan),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF22D3EE),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text(
                      _hasActiveSubscription
                          ? _text('Abonelik Aktif', 'Subscription Active')
                          : _text('Hemen Yukselt', 'Upgrade Now'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPerk(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF22D3EE), size: 18),
          const SizedBox(width: 10),
          Text(text,
              style: const TextStyle(color: Colors.white70, fontSize: 15)),
        ],
      ),
    );
  }
}
