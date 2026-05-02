import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../services/auth_service.dart';
import '../services/analytics_service.dart';
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
  bool _isLoading = true;
  bool _isPurchasing = false;
  bool _hasActiveSubscription = false;
  String? _subscriptionEndDateLabel;
  String? _pendingPurchasePlanName;
  static const String _singlePlanName = 'PRO_MONTHLY';
  static const double _singlePlanDisplayPrice = 20;
  static const String _singlePlanDisplayCurrency = 'TRY';
  final bool _enableMobileIap =
      const bool.fromEnvironment('ENABLE_MOBILE_IAP', defaultValue: true);

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
        const SnackBar(
          content: Text('Mevcut mağaza aboneliği kontrol ediliyor...'),
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
        _hasActiveSubscription = active;
        _subscriptionEndDateLabel = endDate;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e')),
      );
    }
  }

  List<SubscriptionPlan> _selectVisiblePlans(List<SubscriptionPlan> plans) {
    for (final plan in plans) {
      if (plan.name == _singlePlanName) {
        return [plan];
      }
    }

    for (final plan in plans) {
      if (plan.name != 'FREE') {
        return [plan];
      }
    }

    return const [];
  }

  String _displayPriceLabel(SubscriptionPlan plan) {
    final price =
        plan.name == _singlePlanName ? _singlePlanDisplayPrice : plan.price;
    final priceText = price % 1 == 0 ? price.toStringAsFixed(0) : price.toStringAsFixed(2);
    final currency = plan.name == _singlePlanName
        ? _singlePlanDisplayCurrency
        : plan.currency;
    return '$priceText $currency';
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
      currency: plan.name == _singlePlanName
          ? _singlePlanDisplayCurrency
          : plan.currency,
      price: plan.name == _singlePlanName ? _singlePlanDisplayPrice : plan.price,
    );

    setState(() => _isPurchasing = true);

    // DEMO MODE: Skip payment entirely
    if (_subscriptionDemoMode) {
      _activateDemoSubscription(plan);
      return;
    }

    if (!Platform.isAndroid && !Platform.isIOS) {
      setState(() => _isPurchasing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Abonelik satın alma sadece mobil uygulamada desteklenir.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!_enableMobileIap) {
      setState(() => _isPurchasing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bu buildde mobil satin alma kapali.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final success = await _subscriptionService.purchaseWithIAP(plan);
      if (!mounted) return;
      if (!success) {
        setState(() => _isPurchasing = false);
      }
      // Purchase result will come through the stream callback
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPurchasing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ödeme hatası: $e')),
      );
    }
  }

  void _activateDemoSubscription(SubscriptionPlan plan) async {
    try {
      final result =
          await _subscriptionService.activateDemoSubscription(plan.id);
      if (!mounted) return;
      setState(() => _isPurchasing = false);
      _showSuccessDialog(result['message'] ?? 'Demo abonelik aktif!');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPurchasing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Demo hatası: $e'), backgroundColor: Colors.red),
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
        const SnackBar(
          content: Text('Geri yukleme baslatildi. Abonelik senkronu bekleniyor...'),
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
          content: Text('Geri yukleme hatasi: $e'),
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
        title:
            const Text('🎉 Tebrikler!', style: TextStyle(color: Colors.white)),
        content: Text(
          message ?? 'PRO üyeliğiniz başarıyla aktif edildi. Keyifle öğrenin!',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context); // Return to previous screen
            },
            child:
                const Text('Tamam', style: TextStyle(color: Color(0xFF22D3EE))),
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
        title: const Text('PRO Üyelik',
            style: TextStyle(fontWeight: FontWeight.bold)),
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
                        child: const Text(
                          'DEMO ODEME MODU AKTIF',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    const Text(
                      'Dil Öğrenme Yolculuğunu\nÜst Seviyeye Taşı',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Yapay zeka destekli özelliklerle hızla ilerle.',
                      style: TextStyle(color: Colors.white60, fontSize: 16),
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
                              ? 'Aboneliğiniz aktif.'
                              : 'Aboneliğiniz aktif. Bitiş: $_subscriptionEndDateLabel',
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (_plans.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'Abonelik plani su anda bulunamadi.',
                          style: TextStyle(color: Colors.white70, fontSize: 15),
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
                          child: const Text(
                            'Satin alimlari geri yukle',
                            style: TextStyle(color: Colors.white70),
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
                          ? 'Yıllık Plan'
                          : 'Aylık Plan',
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
                        child: const Text('%40 Tasarruf',
                            style: TextStyle(
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
                      plan.durationDays == 30 ? ' / ay' : ' / yıl',
                      style:
                          const TextStyle(color: Colors.white60, fontSize: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildPerk(Icons.check_circle, 'Sınırsız AI Chat Buddy'),
                _buildPerk(Icons.check_circle, 'IELTS Speaking Simülasyonu'),
                _buildPerk(Icons.check_circle, 'Gelişmiş Gramer Kontrolü'),
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
                          ? 'Abonelik Aktif'
                          : 'Hemen Yükselt',
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

