import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import '../config/app_config.dart';
import 'auth_service.dart';

class SubscriptionPlan {
  final int id;
  final String name;
  final double price;
  final String currency;
  final int durationDays;
  final String? features;

  SubscriptionPlan({
    required this.id,
    required this.name,
    required this.price,
    required this.currency,
    required this.durationDays,
    this.features,
  });

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    return SubscriptionPlan(
      id: json['id'],
      name: json['name'],
      price: json['price'].toDouble(),
      currency: json['currency'],
      durationDays: json['durationDays'],
      features: json['features'],
    );
  }

  /// Maps plan name to Google Play product ID
  String get googlePlayProductId {
    switch (name) {
      case 'PRO_MONTHLY':
        return 'pro_monthly_subscription';
      case 'PRO_ANNUAL':
        return 'pro_annual_subscription';
      case 'PREMIUM':
        return 'premium_monthly';
      case 'PREMIUM_PLUS':
        return 'premium_plus_monthly';
      default:
        return '';
    }
  }

  /// Maps plan name to Apple App Store product ID
  String get appleProductId {
    switch (name) {
      case 'PRO_MONTHLY':
        return 'com.vocabmaster.pro.monthly';
      case 'PRO_ANNUAL':
        return 'com.vocabmaster.pro.annual';
      case 'PREMIUM':
        return 'com.vocabmaster.pro.monthly';
      case 'PREMIUM_PLUS':
        return 'com.vocabmaster.pro.annual';
      default:
        return '';
    }
  }
}

class SubscriptionService {
  final AuthService _authService = AuthService();
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;

  StreamSubscription<List<PurchaseDetails>>? _subscription;
  Function(String message)? onPurchaseSuccess;
  Function(String error)? onPurchaseError;
  String? _lastVerificationError;
  DateTime? _lastRestoreAttemptAt;

  /// Initialize IAP listener
  void initializePurchaseStream() {
    final purchaseUpdated = _inAppPurchase.purchaseStream;
    _subscription = purchaseUpdated.listen(
      _onPurchaseUpdate,
      onDone: () => _subscription?.cancel(),
      onError: (error) => debugPrint('IAP Error: $error'),
    );
  }

  /// Dispose the stream
  void dispose() {
    _subscription?.cancel();
  }

  /// Check if IAP is available
  Future<bool> isIAPAvailable() async {
    return await _inAppPurchase.isAvailable();
  }

  /// Restore previously owned purchases/subscriptions from store.
  Future<void> restorePurchases() async {
    await syncOwnedPurchases(force: true);
  }

  Future<bool> syncOwnedPurchases({bool force = false}) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return false;
    }

    final available = await isIAPAvailable();
    if (!available) {
      return false;
    }

    final now = DateTime.now();
    final lastAttemptAt = _lastRestoreAttemptAt;
    if (!force &&
        lastAttemptAt != null &&
        now.difference(lastAttemptAt) < const Duration(seconds: 10)) {
      return false;
    }

    _lastRestoreAttemptAt = now;
    await _inAppPurchase.restorePurchases();
    return true;
  }

  /// Get available products from store
  Future<List<ProductDetails>> getStoreProducts() async {
    final Set<String> productIds = {
      'pro_monthly_subscription',
      'pro_annual_subscription',
      'premium_monthly',
      'premium_plus_monthly',
    };

    final ProductDetailsResponse response =
        await _inAppPurchase.queryProductDetails(productIds);

    if (response.notFoundIDs.isNotEmpty) {
      debugPrint('Products not found: ${response.notFoundIDs}');
    }

    return response.productDetails;
  }

  /// Start Google Play / Apple IAP purchase
  Future<bool> purchaseWithIAP(SubscriptionPlan plan) async {
    try {
      final available = await isIAPAvailable();
      if (!available) {
        onPurchaseError?.call('Uygulama içi satın alma kullanılamıyor');
        return false;
      }

      final String productId =
          Platform.isIOS ? plan.appleProductId : plan.googlePlayProductId;

      if (productId.isEmpty) {
        onPurchaseError?.call('Bu plan için ürün bulunamadı');
        return false;
      }

      final products = await getStoreProducts();
      final product = products.where((p) => p.id == productId).firstOrNull;

      if (product == null) {
        onPurchaseError?.call('Ürün mağazada bulunamadı');
        return false;
      }

      final PurchaseParam purchaseParam = PurchaseParam(
        productDetails: product,
      );

      // For subscriptions
      final started = await _inAppPurchase.buyNonConsumable(
        purchaseParam: purchaseParam,
      );
      if (!started) {
        onPurchaseError?.call('Satın alma başlatılamadı');
      }
      return started;
    } catch (e) {
      final lower = e.toString().toLowerCase();
      if (lower.contains('already') && lower.contains('owned')) {
        try {
          await syncOwnedPurchases(force: true);
          onPurchaseError?.call(
            'Mevcut magaza aboneligi bulundu, hesabiniza aktariliyor...',
          );
          return false;
        } catch (_) {
          // fall through to generic error reporting below
        }
      }
      final mapped = _mapRawPlayError(e.toString());
      if (mapped != null) {
        onPurchaseError?.call(mapped);
        return false;
      }
      onPurchaseError?.call('Satın alma başlatılamadı: $e');
      return false;
    }
  }

  /// Handle purchase updates
  void _onPurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) async {
    for (var purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        debugPrint('Purchase pending...');
      } else if (purchaseDetails.status == PurchaseStatus.error) {
        final alreadyOwned = _isAlreadyOwnedError(purchaseDetails.error);
        if (alreadyOwned) {
          try {
            await syncOwnedPurchases(force: true);
            onPurchaseError?.call(
              'Mevcut magaza aboneligi bulundu, hesabiniza aktariliyor...',
            );
          } catch (e) {
            onPurchaseError?.call('Mevcut abonelik geri yüklenemedi: $e');
          }
        } else {
          final mapped = _mapPlayStoreError(purchaseDetails.error);
          onPurchaseError?.call(
            mapped ?? purchaseDetails.error?.message ?? 'Satın alma hatası',
          );
        }
        if (purchaseDetails.pendingCompletePurchase) {
          await _inAppPurchase.completePurchase(purchaseDetails);
        }
      } else if (purchaseDetails.status == PurchaseStatus.purchased ||
          purchaseDetails.status == PurchaseStatus.restored) {
        // Verify purchase with backend
        final verified = await _verifyPurchaseWithBackend(purchaseDetails);

        if (verified) {
          _lastVerificationError = null;
          onPurchaseSuccess?.call('Aboneliğiniz başarıyla aktifleştirildi!');
        } else {
          onPurchaseError
              ?.call(_lastVerificationError ?? 'Satın alma doğrulanamadı');
        }

        if (purchaseDetails.pendingCompletePurchase) {
          await _inAppPurchase.completePurchase(purchaseDetails);
        }
      }
    }
  }

  /// Verify purchase with backend
  Future<bool> _verifyPurchaseWithBackend(
      PurchaseDetails purchaseDetails) async {
    try {
      final apiUrl = await AppConfig.apiBaseUrl;
      final userId = await _resolveUserIdForPurchase();
      final token = await _authService.getToken();
      final purchaseToken =
          purchaseDetails.verificationData.serverVerificationData.trim();

      if (userId == null || userId <= 0) {
        _lastVerificationError =
            'Kullanici kimligi bulunamadi. Lutfen cikis yapip tekrar girin.';
        debugPrint('Backend verification failed: missing userId');
        return false;
      }

      if (token == null || token.isEmpty) {
        _lastVerificationError =
            'Oturum bulunamadi. Lutfen cikis yapip tekrar girin.';
        debugPrint('Backend verification failed: missing token');
        return false;
      }
      if (purchaseToken.isEmpty) {
        _lastVerificationError =
            'Satin alma tokeni bos geldi. Lutfen satin alimlari geri yukleyin.';
        debugPrint(
          'Backend verification failed: empty purchase token product=${purchaseDetails.productID}',
        );
        return false;
      }

      final endpoint = Platform.isIOS
          ? '$apiUrl/subscription/verify/apple'
          : '$apiUrl/subscription/verify/google';

      // Keep mock-mode compatibility while supporting new product IDs.
      final productId = purchaseDetails.productID;
      String planName = 'PRO_MONTHLY';
      if (productId == 'pro_annual_subscription') {
        planName = 'PRO_ANNUAL';
      } else if (productId == 'premium_monthly') {
        planName = 'PREMIUM';
      } else if (productId == 'premium_plus_monthly') {
        planName = 'PREMIUM_PLUS';
      }

      final response = await http.post(
        Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
          'X-User-Id': userId.toString(),
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'planName': planName,
          'purchaseToken': purchaseToken,
          'productId': purchaseDetails.productID,
        }),
      );

      if (response.statusCode != 200) {
        _lastVerificationError =
            _buildVerificationErrorMessage(response.statusCode, response.body);
        debugPrint(
          'Backend verification failed: status=${response.statusCode} body=${response.body}',
        );
      }

      return response.statusCode == 200;
    } catch (e) {
      _lastVerificationError = 'Dogrulama sirasinda baglanti hatasi: $e';
      debugPrint('Backend verification failed: $e');
      return false;
    }
  }

  bool _isAlreadyOwnedError(IAPError? error) {
    if (error == null) {
      return false;
    }
    final code = error.code.toLowerCase();
    final message = error.message.toLowerCase();
    return code.contains('already') ||
        code.contains('owned') ||
        code.contains('item_already_owned') ||
        message.contains('already owned');
  }

  String? _mapPlayStoreError(IAPError? error) {
    if (error == null) {
      return null;
    }
    final code = error.code.toLowerCase();
    final message = error.message.toLowerCase();
    if (message.contains('pg-gemf-02') || code.contains('pg-gemf-02')) {
      return 'Google Play odeme tarafinda hata olustu (PG-GEMF-02). '
          'Play hesabinizi kontrol edip satin alimlari geri yukleyin ve tekrar deneyin.';
    }
    if (code == 'error' || code.contains('billingresponse.error')) {
      return 'Google Play gecici hata verdi (BillingResponse.error). '
          'Lutfen 1-2 dakika sonra tekrar deneyin veya geri yukleme yapin.';
    }
    return null;
  }

  String? _mapRawPlayError(String rawError) {
    final lower = rawError.toLowerCase();
    if (lower.contains('pg-gemf-02')) {
      return 'Google Play odeme tarafinda hata olustu (PG-GEMF-02). '
          'Play Store > Odemeler ve abonelikler > Abonelikler ekranindan geri yukleyip tekrar deneyin.';
    }
    if (lower.contains('billingresponse.error') ||
        lower.contains('service unavailable')) {
      return 'Google Play gecici hata verdi (BillingResponse.error). '
          'Lutfen 1-2 dakika sonra tekrar deneyin.';
    }
    if (lower.contains('itemalreadyowned') ||
        lower.contains('item_already_owned')) {
      return 'Mevcut magaza aboneligi bulundu. Satin alimlariniz hesabiniza aktariliyor.';
    }
    return null;
  }

  Future<int?> _resolveUserIdForPurchase() async {
    var userId = await _authService.getUserId();
    if (userId != null && userId > 0) {
      return userId;
    }

    try {
      await _authService.refreshProfile();
    } catch (_) {
      // ignore and retry local resolution
    }

    userId = await _authService.getUserId();
    return (userId != null && userId > 0) ? userId : null;
  }

  String _buildVerificationErrorMessage(int statusCode, String body) {
    String? code;
    String? error;
    try {
      final parsed = json.decode(body);
      if (parsed is Map<String, dynamic>) {
        code = parsed['code']?.toString();
        error = parsed['error']?.toString();
      }
    } catch (_) {
      // fall through
    }
    final normalized = '${code ?? ''} ${error ?? ''} $body'.toLowerCase();

    if (statusCode == 401 || statusCode == 403) {
      return 'Oturum dogrulama hatasi. Lutfen cikis yapip tekrar girin.';
    }
    if (statusCode == 400 && normalized.contains('purchasetoken is required')) {
      return 'Satin alma tokeni eksik geldi. Abonelik sayfasindan geri yukleme yapip tekrar deneyin.';
    }
    if (statusCode == 400 &&
        normalized.contains('unable to map google product/base plan')) {
      return 'Play Console urun-plani backend ile eslesmedi. Destek ekibiyle iletisime gecin.';
    }
    if (statusCode == 400 && normalized.contains('mapped plan not found')) {
      return 'Backend plan eslemesi eksik. Destek ekibiyle iletisime gecin.';
    }
    if (statusCode == 400 && code == 'INVALID_PURCHASE') {
      return 'Google satin alma kaydi dogrulanamadi. Satin alma gecmisiyle tekrar deneyin.';
    }
    if (statusCode == 503 && code == 'PROVIDER_UNAVAILABLE') {
      return 'Google dogrulama servisi su an ulasilamiyor. Biraz sonra tekrar deneyin.';
    }
    if (error != null && error.isNotEmpty) {
      return 'Dogrulama hatasi: $error';
    }
    return 'Satin alma dogrulanamadi (HTTP $statusCode).';
  }

  /// Get plans from backend
  Future<List<SubscriptionPlan>> getPlans() async {
    final apiUrl = await AppConfig.apiBaseUrl;
    final url = '$apiUrl/subscription/plans';
    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => SubscriptionPlan.fromJson(json)).toList();
      } else {
        throw Exception(
            'Paketler yüklenemedi: HTTP ${response.statusCode} at $url');
      }
    } catch (e) {
      throw Exception('Bağlantı hatası: $e (URL: $url)');
    }
  }

  /// Get user's subscription status
  Future<Map<String, dynamic>> getUserSubscriptionStatus() async {
    final apiUrl = await AppConfig.apiBaseUrl;
    final userId = await _authService.getUserId();
    final token = await _authService.getToken();

    if (userId == null) throw Exception('Kullanıcı ID bulunamadı');

    final response = await http.get(
      Uri.parse('$apiUrl/users/$userId/subscription/status'),
      headers: {
        'Content-Type': 'application/json',
        'X-User-Id': userId.toString(),
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Abonelik durumu alınamadı');
    }
  }

  /// DEMO MODE: Activate subscription without payment (for testing only!)
  Future<Map<String, dynamic>> activateDemoSubscription(int planId) async {
    final apiUrl = await AppConfig.apiBaseUrl;
    final userId = await _authService.getUserId();

    final response = await http.post(
      Uri.parse('$apiUrl/subscription/demo/activate'),
      headers: {
        'Content-Type': 'application/json',
        'X-User-Id': userId.toString(),
      },
      body: json.encode({
        'planId': planId,
      }),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final errorBody = json.decode(response.body);
      final error = errorBody['error'] ?? 'Demo aktivasyon başarısız';
      throw Exception(error);
    }
  }
}
