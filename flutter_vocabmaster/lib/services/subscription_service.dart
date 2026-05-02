import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import '../config/app_config.dart';
import 'auth_service.dart';
import 'locale_text_service.dart';

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

  String _text(String tr, String en) => LocaleTextService.pick(tr, en);

  void initializePurchaseStream() {
    final purchaseUpdated = _inAppPurchase.purchaseStream;
    _subscription = purchaseUpdated.listen(
      _onPurchaseUpdate,
      onDone: () => _subscription?.cancel(),
      onError: (error) => debugPrint('IAP Error: $error'),
    );
  }

  void dispose() {
    _subscription?.cancel();
  }

  Future<bool> isIAPAvailable() async {
    return await _inAppPurchase.isAvailable();
  }

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

  Future<bool> purchaseWithIAP(SubscriptionPlan plan) async {
    try {
      final available = await isIAPAvailable();
      if (!available) {
        onPurchaseError?.call(_text(
          'Uygulama ici satin alma su an kullanilamiyor.',
          'In-app purchases are not available right now.',
        ));
        return false;
      }

      final String productId =
          Platform.isIOS ? plan.appleProductId : plan.googlePlayProductId;

      if (productId.isEmpty) {
        onPurchaseError?.call(_text(
          'Bu plan icin magazada urun bulunamadi.',
          'No store product was found for this plan.',
        ));
        return false;
      }

      final products = await getStoreProducts();
      final product = products.where((p) => p.id == productId).firstOrNull;

      if (product == null) {
        onPurchaseError?.call(_text(
          'Urun magazada bulunamadi.',
          'The product could not be found in the store.',
        ));
        return false;
      }

      final PurchaseParam purchaseParam = PurchaseParam(
        productDetails: product,
      );

      final started = await _inAppPurchase.buyNonConsumable(
        purchaseParam: purchaseParam,
      );
      if (!started) {
        onPurchaseError?.call(_text(
          'Satin alma baslatilamadi.',
          'The purchase could not be started.',
        ));
      }
      return started;
    } catch (e) {
      final lower = e.toString().toLowerCase();
      if (lower.contains('already') && lower.contains('owned')) {
        try {
          await syncOwnedPurchases(force: true);
          onPurchaseError?.call(_text(
            'Mevcut magaza aboneligi bulundu, hesabiniza aktariliyor...',
            'An existing store subscription was found and is being restored to your account...',
          ));
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
      onPurchaseError?.call(_text(
        'Satin alma baslatilamadi: $e',
        'The purchase could not be started: $e',
      ));
      return false;
    }
  }

  void _onPurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) async {
    for (var purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        debugPrint('Purchase pending...');
      } else if (purchaseDetails.status == PurchaseStatus.error) {
        final alreadyOwned = _isAlreadyOwnedError(purchaseDetails.error);
        if (alreadyOwned) {
          try {
            await syncOwnedPurchases(force: true);
            onPurchaseError?.call(_text(
              'Mevcut magaza aboneligi bulundu, hesabiniza aktariliyor...',
              'An existing store subscription was found and is being restored to your account...',
            ));
          } catch (e) {
            onPurchaseError?.call(_text(
              'Mevcut abonelik geri yuklenemedi: $e',
              'The existing subscription could not be restored: $e',
            ));
          }
        } else {
          final mapped = _mapPlayStoreError(purchaseDetails.error);
          onPurchaseError?.call(
            mapped ??
                purchaseDetails.error?.message ??
                _text('Satin alma hatasi', 'Purchase error'),
          );
        }
        if (purchaseDetails.pendingCompletePurchase) {
          await _inAppPurchase.completePurchase(purchaseDetails);
        }
      } else if (purchaseDetails.status == PurchaseStatus.purchased ||
          purchaseDetails.status == PurchaseStatus.restored) {
        final verified = await _verifyPurchaseWithBackend(purchaseDetails);

        if (verified) {
          _lastVerificationError = null;
          onPurchaseSuccess?.call(_text(
            'Aboneliginiz basariyla aktiflestirildi.',
            'Your subscription was activated successfully.',
          ));
        } else {
          onPurchaseError?.call(
            _lastVerificationError ??
                _text(
                  'Satin alma dogrulanamadi.',
                  'The purchase could not be verified.',
                ),
          );
        }

        if (purchaseDetails.pendingCompletePurchase) {
          await _inAppPurchase.completePurchase(purchaseDetails);
        }
      }
    }
  }

  Future<bool> _verifyPurchaseWithBackend(
      PurchaseDetails purchaseDetails) async {
    try {
      final apiUrl = await AppConfig.apiBaseUrl;
      var userId = await _resolveUserIdForPurchase();
      var token = await _authService.getToken();
      final purchaseToken =
          purchaseDetails.verificationData.serverVerificationData.trim();

      if (userId == null || userId <= 0) {
        final refreshed = await _authService.refreshSession();
        if (refreshed) {
          userId = await _resolveUserIdForPurchase();
          token = await _authService.getToken();
        }
        if (userId == null || userId <= 0) {
          _lastVerificationError = _text(
            'Kullanici kimligi bulunamadi. Lutfen tekrar deneyin.',
            'Your account identity could not be resolved. Please try again.',
          );
          debugPrint('Backend verification failed: missing userId');
          return false;
        }
      }

      if (token == null || token.isEmpty) {
        final refreshed = await _authService.refreshSession();
        if (refreshed) {
          token = await _authService.getToken();
        }
        if (token == null || token.isEmpty) {
          _lastVerificationError = _text(
            'Oturum yenilenemedi. Lutfen satin alma ekranini tekrar acip yeniden deneyin.',
            'Your session could not be refreshed. Reopen the purchase screen and try again.',
          );
          debugPrint('Backend verification failed: missing token');
          return false;
        }
      }
      if (purchaseToken.isEmpty) {
        _lastVerificationError = _text(
          'Satin alma tokeni bos geldi. Lutfen satin alimlarini geri yukleyin.',
          'The purchase token is empty. Please restore your purchases and try again.',
        );
        debugPrint(
          'Backend verification failed: empty purchase token product=${purchaseDetails.productID}',
        );
        return false;
      }

      final endpoint = Platform.isIOS
          ? '$apiUrl/subscription/verify/apple'
          : '$apiUrl/subscription/verify/google';

      final productId = purchaseDetails.productID;
      String planName = 'PRO_MONTHLY';
      if (productId == 'pro_annual_subscription') {
        planName = 'PRO_ANNUAL';
      } else if (productId == 'premium_monthly') {
        planName = 'PREMIUM';
      } else if (productId == 'premium_plus_monthly') {
        planName = 'PREMIUM_PLUS';
      }

      Future<http.Response> sendVerificationRequest(String bearerToken) {
        return http.post(
          Uri.parse(endpoint),
          headers: {
            'Content-Type': 'application/json',
            'X-User-Id': userId.toString(),
            'Authorization': 'Bearer $bearerToken',
          },
          body: json.encode({
            'planName': planName,
            'purchaseToken': purchaseToken,
            'productId': purchaseDetails.productID,
          }),
        );
      }

      var response = await sendVerificationRequest(token);
      if (response.statusCode == 401 || response.statusCode == 403) {
        final refreshed = await _authService.refreshSession();
        if (refreshed) {
          token = await _authService.getToken();
          userId = await _resolveUserIdForPurchase() ?? userId;
          if (token != null && token.isNotEmpty) {
            response = await sendVerificationRequest(token);
          }
        }
      }

      if (response.statusCode != 200) {
        _lastVerificationError =
            _buildVerificationErrorMessage(response.statusCode, response.body);
        debugPrint(
          'Backend verification failed: status=${response.statusCode} body=${response.body}',
        );
        return false;
      }

      try {
        await _authService.refreshProfile();
      } catch (e) {
        debugPrint('Profile refresh after purchase verification failed: $e');
      }
      return true;
    } catch (e) {
      _lastVerificationError = _text(
        'Dogrulama sirasinda baglanti hatasi: $e',
        'A connection error occurred during verification: $e',
      );
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
      return _text(
        'Google Play odeme tarafinda hata olustu (PG-GEMF-02). Play hesabinizi kontrol edip satin alimlarini geri yukleyin ve tekrar deneyin.',
        'Google Play returned a payment error (PG-GEMF-02). Check your Play account, restore purchases, and try again.',
      );
    }
    if (code == 'error' || code.contains('billingresponse.error')) {
      return _text(
        'Google Play gecici hata verdi (BillingResponse.error). Lutfen 1-2 dakika sonra tekrar deneyin veya geri yukleme yapin.',
        'Google Play returned a temporary error (BillingResponse.error). Please try again in 1-2 minutes or restore purchases.',
      );
    }
    return null;
  }

  String? _mapRawPlayError(String rawError) {
    final lower = rawError.toLowerCase();
    if (lower.contains('pg-gemf-02')) {
      return _text(
        'Google Play odeme tarafinda hata olustu (PG-GEMF-02). Play Store > Odemeler ve abonelikler > Abonelikler ekranindan geri yukleyip tekrar deneyin.',
        'Google Play returned a payment error (PG-GEMF-02). Restore the subscription from Play Store > Payments & subscriptions > Subscriptions, then try again.',
      );
    }
    if (lower.contains('billingresponse.error') ||
        lower.contains('service unavailable')) {
      return _text(
        'Google Play gecici hata verdi (BillingResponse.error). Lutfen 1-2 dakika sonra tekrar deneyin.',
        'Google Play returned a temporary error (BillingResponse.error). Please try again in 1-2 minutes.',
      );
    }
    if (lower.contains('itemalreadyowned') ||
        lower.contains('item_already_owned')) {
      return _text(
        'Mevcut magaza aboneligi bulundu. Satin alimlariniz hesabiniza aktariliyor.',
        'An existing store subscription was found. Your purchases are being restored to your account.',
      );
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
    final normalized = '$code $error $body'.toLowerCase();

    if (statusCode == 401 || statusCode == 403) {
      if (normalized.contains('user identity mismatch')) {
        return _text(
          'Hesap oturumu ile kullanici bilgisi eslesmedi. Oturum otomatik yenileniyor; islemi tekrar deneyin.',
          'Your stored account data did not match the active session. The session is being repaired automatically; please try the purchase again.',
        );
      }
      return _text(
        'Oturum dogrulama hatasi. Lutfen tekrar deneyin. Sorun devam ederse uygulamayi yeniden acin.',
        'Session verification failed. Please try again. If the issue continues, reopen the app and try once more.',
      );
    }
    if (statusCode == 400 && normalized.contains('purchasetoken is required')) {
      return _text(
        'Satin alma tokeni eksik geldi. Abonelik sayfasindan geri yukleme yapip tekrar deneyin.',
        'The purchase token was missing. Restore purchases from the subscription page and try again.',
      );
    }
    if (statusCode == 400 &&
        normalized.contains('unable to map google product/base plan')) {
      return _text(
        'Play Console urun-plani backend ile eslesmedi. Destek ekibiyle iletisime gecin.',
        'The Play Console product plan does not match the backend mapping. Please contact support.',
      );
    }
    if (statusCode == 400 && normalized.contains('mapped plan not found')) {
      return _text(
        'Backend plan eslemesi eksik. Destek ekibiyle iletisime gecin.',
        'The backend plan mapping is missing. Please contact support.',
      );
    }
    if (statusCode == 400 && code == 'INVALID_PURCHASE') {
      return _text(
        'Google satin alma kaydi dogrulanamadi. Satin alma gecmisiyle tekrar deneyin.',
        'Google could not verify this purchase. Please try again from your purchase history.',
      );
    }
    if (statusCode == 503 && code == 'PROVIDER_UNAVAILABLE') {
      return _text(
        'Google dogrulama servisi su an ulasilamiyor. Biraz sonra tekrar deneyin.',
        'The Google verification service is currently unavailable. Please try again shortly.',
      );
    }
    if (error != null && error.isNotEmpty) {
      return _text('Dogrulama hatasi: $error', 'Verification error: $error');
    }
    return _text(
      'Satin alma dogrulanamadi (HTTP $statusCode).',
      'The purchase could not be verified (HTTP $statusCode).',
    );
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
    var userId = await _authService.getUserId();
    var token = await _authService.getToken();

    if (userId == null || userId <= 0 || token == null || token.isEmpty) {
      final refreshed = await _authService.refreshSession();
      if (refreshed) {
        userId = await _authService.getUserId();
        token = await _authService.getToken();
      }
    }

    if (userId == null || userId <= 0) {
      throw Exception(_text(
        'Kullanici oturumu bulunamadi.',
        'The account session could not be resolved.',
      ));
    }

    Future<http.Response> sendStatusRequest(String? bearerToken) {
      return http.get(
        Uri.parse('$apiUrl/users/$userId/subscription/status'),
        headers: {
          'Content-Type': 'application/json',
          'X-User-Id': userId.toString(),
          if (bearerToken != null && bearerToken.isNotEmpty)
            'Authorization': 'Bearer $bearerToken',
        },
      );
    }

    var response = await sendStatusRequest(token);
    if (response.statusCode == 401 || response.statusCode == 403) {
      final refreshed = await _authService.refreshSession();
      if (refreshed) {
        userId = await _authService.getUserId() ?? userId;
        token = await _authService.getToken();
        response = await sendStatusRequest(token);
      }
    }

    if (response.statusCode == 200) {
      try {
        await _authService.refreshProfile();
      } catch (e) {
        debugPrint('Profile refresh after subscription status failed: $e');
      }
      return json.decode(response.body);
    }

    throw Exception(
      _buildVerificationErrorMessage(response.statusCode, response.body),
    );
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
      try {
        await _authService.refreshProfile();
      } catch (e) {
        debugPrint('Profile refresh after demo subscription failed: $e');
      }
      return json.decode(response.body);
    } else {
      final errorBody = json.decode(response.body);
      final error = errorBody['error'] ?? 'Demo aktivasyon başarısız';
      throw Exception(error);
    }
  }
}
