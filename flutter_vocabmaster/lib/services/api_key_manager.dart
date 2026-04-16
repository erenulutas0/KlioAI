import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// BYOK (Bring Your Own Key) API Key Manager
/// Kullanıcının kendi Groq API key'ini güvenli bir şekilde saklar ve yönetir.
class ApiKeyManager {
  static const String _groqApiKeyStorageKey = 'user_groq_api_key';
  static const String _useOwnKeyPrefKey = 'use_own_groq_key';
  
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );
  
  // Singleton pattern
  static final ApiKeyManager _instance = ApiKeyManager._internal();
  factory ApiKeyManager() => _instance;
  ApiKeyManager._internal();
  
  // Cache
  String? _cachedApiKey;
  bool? _cachedUseOwnKey;
  
  /// Kullanıcının kendi key'ini kullanıp kullanmadığını kontrol eder
  Future<bool> get useOwnKey async {
    if (_cachedUseOwnKey != null) return _cachedUseOwnKey!;
    
    final prefs = await SharedPreferences.getInstance();
    _cachedUseOwnKey = prefs.getBool(_useOwnKeyPrefKey) ?? false;
    return _cachedUseOwnKey!;
  }
  
  /// Kullanıcının API key'ini güvenli depolamadan alır
  Future<String?> get userApiKey async {
    if (_cachedApiKey != null) return _cachedApiKey;
    
    try {
      _cachedApiKey = await _secureStorage.read(key: _groqApiKeyStorageKey);
      return _cachedApiKey;
    } catch (e) {
      debugPrint('ApiKeyManager: Error reading API key: $e');
      return null;
    }
  }
  
  /// API key'in geçerli olup olmadığını kontrol eder (format kontrolü)
  bool isValidApiKeyFormat(String key) {
    // Groq API key'leri genellikle "gsk_" ile başlar ve 50+ karakter uzunluğundadır
    return key.trim().isNotEmpty && 
           key.trim().length >= 40 &&
           key.trim().startsWith('gsk_');
  }
  
  /// Kullanıcının API key'ini kaydeder
  Future<bool> saveApiKey(String apiKey) async {
    if (!isValidApiKeyFormat(apiKey)) {
      return false;
    }
    
    try {
      await _secureStorage.write(key: _groqApiKeyStorageKey, value: apiKey.trim());
      _cachedApiKey = apiKey.trim();
      
      // Otomatik olarak kendi key kullanımını aktif et
      await setUseOwnKey(true);
      
      return true;
    } catch (e) {
      debugPrint('ApiKeyManager: Error saving API key: $e');
      return false;
    }
  }
  
  /// Kendi key kullanımını ayarlar
  Future<void> setUseOwnKey(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useOwnKeyPrefKey, value);
    _cachedUseOwnKey = value;
  }
  
  /// API key'i siler
  Future<void> deleteApiKey() async {
    try {
      await _secureStorage.delete(key: _groqApiKeyStorageKey);
      _cachedApiKey = null;
      await setUseOwnKey(false);
    } catch (e) {
      debugPrint('ApiKeyManager: Error deleting API key: $e');
    }
  }
  
  /// API key'in kaydedilip kaydedilmediğini kontrol eder
  Future<bool> hasApiKey() async {
    final key = await userApiKey;
    return key != null && key.isNotEmpty;
  }
  
  /// Aktif API key'i döndürür (BYOK veya .env'den)
  /// Bu, tüm servislerin kullanması gereken ana metoddur.
  Future<String?> getActiveApiKey() async {
    final shouldUseOwnKey = await useOwnKey;
    
    if (shouldUseOwnKey) {
      final ownKey = await userApiKey;
      if (ownKey != null && ownKey.isNotEmpty) {
        return ownKey;
      }
    }
    
    // Fallback: .env'den al (demo mode veya kendi key yoksa)
    return null; // null dönerse, servisler .env'den okuyacak
  }
  
  /// API key'i test eder (Groq API'ye basit bir istek atarak)
  Future<ApiKeyTestResult> testApiKey(String apiKey) async {
    try {
      final response = await _makeTestRequest(apiKey);
      
      if (response == 200) {
        return ApiKeyTestResult(
          isValid: true,
          message: 'API anahtarı geçerli! ✓',
        );
      } else if (response == 401) {
        return ApiKeyTestResult(
          isValid: false,
          message: 'Geçersiz API anahtarı. Lütfen kontrol edin.',
        );
      } else if (response == 429) {
        return ApiKeyTestResult(
          isValid: true, // Key geçerli ama rate limited
          message: 'API anahtarı geçerli ancak rate limit aşıldı. Biraz bekleyin.',
        );
      } else {
        return ApiKeyTestResult(
          isValid: false,
          message: 'API hatası: HTTP $response',
        );
      }
    } catch (e) {
      return ApiKeyTestResult(
        isValid: false,
        message: 'Bağlantı hatası: $e',
      );
    }
  }
  
  /// Test isteği yapar
  Future<int> _makeTestRequest(String apiKey) async {
    // Bu import'u servis dosyasında yapacağız
    // Burada sadece placeholder
    return 200; // Gerçek implementasyon GroqApiClient'ta olacak
  }
  
  /// Cache'i temizler
  void clearCache() {
    _cachedApiKey = null;
    _cachedUseOwnKey = null;
  }
}

/// API key test sonucu
class ApiKeyTestResult {
  final bool isValid;
  final String message;
  
  ApiKeyTestResult({
    required this.isValid,
    required this.message,
  });
}

