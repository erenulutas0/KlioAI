import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_key_manager.dart';
import '../config/dotenv_safe.dart';

/// Merkezi Groq API istemcisi
/// BYOK (Bring Your Own Key) desteği ile API çağrılarını yönetir.
class GroqApiClient {
  static const String _baseUrl = 'https://api.groq.com/openai/v1/chat/completions';
  // Pay-as-you-go planı ile 70b modeline geri dönüldü (Yüksek Kalite)
  static const String _defaultModel = 'llama-3.3-70b-versatile';
  
  static final ApiKeyManager _keyManager = ApiKeyManager();
  static const String _allowEmbeddedKeyEnv = 'ALLOW_EMBEDDED_GROQ_KEY';

  static bool get _allowEmbeddedKey {
    if (kReleaseMode) {
      return false;
    }
    final raw = readDotEnvOrDefault(_allowEmbeddedKeyEnv, 'false');
    return raw.trim().toLowerCase() == 'true';
  }
  
  /// Aktif API key'i alır (BYOK veya Default)
  static Future<String> _getApiKey() async {
    // 1) Kullanıcı kendi key'ini girmişse onu kullan
    final userKey = await _keyManager.getActiveApiKey();
    if (userKey != null && userKey.isNotEmpty) {
      return userKey;
    }

    // 2) Embedded/demo key only when explicitly allowed.
    if (_allowEmbeddedKey) {
      final envKey = readDotEnvOrDefault('GROQ_API_KEY');
      if (envKey.isNotEmpty) {
        return envKey;
      }
    }

    throw ApiKeyNotFoundException(
      'Groq API anahtarı bulunamadı. Profil > API Key bölümünden kendi anahtarınızı ekleyin.',
    );
  }
  
  /// Groq API'ye chat completion isteği gönderir
  static Future<Map<String, dynamic>> chatCompletion({
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int? maxTokens,
    bool jsonResponse = false,
    String? model,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final apiKey = await _getApiKey();
    
    final body = <String, dynamic>{
      'model': model ?? _defaultModel,
      'messages': messages,
      'temperature': temperature,
    };
    
    if (maxTokens != null) {
      body['max_tokens'] = maxTokens;
    }
    
    if (jsonResponse) {
      body['response_format'] = {'type': 'json_object'};
    }
    
    try {
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode(body),
      ).timeout(timeout);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return data;
      } else if (response.statusCode == 401) {
        throw InvalidApiKeyException('Geçersiz API anahtarı. Lütfen anahtarınızı kontrol edin.');
      } else if (response.statusCode == 429) {
        throw RateLimitException('API istek limiti aşıldı. Lütfen biraz bekleyin.');
      } else {
        throw GroqApiException('API Hatası: ${response.statusCode}', response.statusCode);
      }
    } on http.ClientException catch (e) {
      throw NetworkException('Ağ bağlantısı hatası: $e');
    }
  }
  
  /// Chat completion'dan içerik string'ini çıkarır
  static Future<String> getCompletionContent({
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int? maxTokens,
    bool jsonResponse = false,
    String? model,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final response = await chatCompletion(
      messages: messages,
      temperature: temperature,
      maxTokens: maxTokens,
      jsonResponse: jsonResponse,
      model: model,
      timeout: timeout,
    );
    
    return response['choices'][0]['message']['content'] as String;
  }
  
  /// JSON response'u parse eder
  static Future<Map<String, dynamic>> getJsonResponse({
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int? maxTokens,
    String? model,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final content = await getCompletionContent(
      messages: messages,
      temperature: temperature,
      maxTokens: maxTokens,
      jsonResponse: true,
      model: model,
      timeout: timeout,
    );
    
    // Markdown formatting temizleme
    String cleanContent = content.trim();
    cleanContent = cleanContent.replaceAll('```json', '').replaceAll('```', '').trim();
    
    return jsonDecode(cleanContent);
  }
  
  /// API key'i test eder
  static Future<ApiKeyTestResult> testApiKey(String apiKey) async {
    try {
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'llama-3.1-8b-instant', // Hızlı ve ucuz model
          'messages': [
            {'role': 'user', 'content': 'Hi'}
          ],
          'max_tokens': 5,
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        return ApiKeyTestResult(
          isValid: true,
          message: 'API anahtarı geçerli! ✓',
        );
      } else if (response.statusCode == 401) {
        return ApiKeyTestResult(
          isValid: false,
          message: 'Geçersiz API anahtarı. Lütfen kontrol edin.',
        );
      } else if (response.statusCode == 429) {
        return ApiKeyTestResult(
          isValid: true, // Key geçerli ama rate limited
          message: 'API anahtarı geçerli! (Rate limit aktif, biraz bekleyin)',
        );
      } else {
        return ApiKeyTestResult(
          isValid: false,
          message: 'API hatası: HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      return ApiKeyTestResult(
        isValid: false,
        message: 'Bağlantı hatası: ${e.toString().split(':').first}',
      );
    }
  }
  
  /// Mevcut API key durumunu kontrol eder
  static Future<ApiKeyStatus> checkApiKeyStatus() async {
    final keyManager = ApiKeyManager();
    final useOwnKey = await keyManager.useOwnKey;
    final hasOwnKey = await keyManager.hasApiKey();
    final envKey = readDotEnvOrDefault('GROQ_API_KEY');
    
    if (useOwnKey && hasOwnKey) {
      return ApiKeyStatus(
        source: ApiKeySource.userProvided,
        isConfigured: true,
        message: 'Kendi API anahtarınız kullanılıyor',
      );
    } else if (_allowEmbeddedKey && envKey.isNotEmpty) {
      return ApiKeyStatus(
        source: ApiKeySource.environment,
        isConfigured: true,
        message: 'Demo modu (sınırlı kullanım)',
      );
    } else {
      return ApiKeyStatus(
        source: ApiKeySource.none,
        isConfigured: false,
        message: 'API anahtarı yapılandırılmamış',
      );
    }
  }
}

// ==================== Exceptions ====================

class GroqApiException implements Exception {
  final String message;
  final int? statusCode;
  
  GroqApiException(this.message, [this.statusCode]);
  
  @override
  String toString() => message;
}

class ApiKeyNotFoundException extends GroqApiException {
  ApiKeyNotFoundException(super.message);
}

class InvalidApiKeyException extends GroqApiException {
  InvalidApiKeyException(super.message);
}

class RateLimitException extends GroqApiException {
  RateLimitException(super.message);
}

class NetworkException extends GroqApiException {
  NetworkException(super.message);
}

// ==================== Data Classes ====================

enum ApiKeySource {
  userProvided,  // Kullanıcının BYOK key'i
  environment,   // .env'den (demo mode)
  none,          // Hiç key yok
}

class ApiKeyStatus {
  final ApiKeySource source;
  final bool isConfigured;
  final String message;
  
  ApiKeyStatus({
    required this.source,
    required this.isConfigured,
    required this.message,
  });
}
