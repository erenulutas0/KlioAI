import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
import 'auth_service.dart';

/// Piper TTS (Text-to-Speech) servis sınıfı
/// Backend'deki TTS endpoint'lerini kullanır
class PiperTtsService {
  PiperTtsService({AuthService? authService})
      : _authService = authService ?? AuthService();

  final AuthService _authService;
  String? _cachedBaseUrl;

  Future<String> get _baseUrl async {
    _cachedBaseUrl ??= await AppConfig.baseUrl;
    return _cachedBaseUrl!;
  }

  /// Backend `/api/tts` prod'da JWT ister (enforce-auth). Eski istemci hiç
  /// auth header göndermediği için prod'da sessizce 401 alıyordu ve
  /// kullanıcılar hep cihaz-içi TTS fallback'ini duyuyordu. Oturum yoksa
  /// header'sız devam ederiz; karar backend'indir.
  Future<Map<String, String>> _headers() async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    try {
      final token = await _authService.getToken();
      final userId = await _authService.getUserId();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
      if (userId != null && userId > 0) {
        headers['X-User-Id'] = userId.toString();
      }
    } catch (e) {
      debugPrint('Piper TTS auth headers unavailable: $e');
    }
    return headers;
  }

  /// Piper TTS'in kullanılabilir olup olmadığını kontrol eder
  Future<bool> isAvailable() async {
    try {
      final baseUrl = await _baseUrl;
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/tts/status'),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['available'] == true;
      }
      return false;
    } catch (e) {
      debugPrint('Piper TTS availability check failed: $e');
      return false;
    }
  }

  /// Metni sese dönüştürür
  /// WAV formatında ses datası döner (Uint8List)
  Future<Uint8List?> synthesize(
    String text, {
    String voice = 'amy',
  }) async {
    try {
      final baseUrl = await _baseUrl;
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/tts/synthesize'),
            headers: await _headers(),
            body: jsonEncode({
              'text': text,
              'voice': voice,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        // Backend Base64 encoded audio gönderir
        final Map<String, dynamic> data = jsonDecode(response.body);

        if (data.containsKey('audio')) {
          String base64String = data['audio'];
          return base64Decode(base64String);
        } else {
          debugPrint('Piper TTS response missing "audio" key');
          return null;
        }
      } else {
        debugPrint('Piper TTS synthesis failed: ${response.statusCode}');
        debugPrint('Response: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Piper TTS synthesis error: $e');
      return null;
    }
  }

  /// Mevcut sesleri getirir
  Future<List<String>> getVoices() async {
    try {
      final baseUrl = await _baseUrl;
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/tts/status'),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['voices'] != null) {
          return List<String>.from(data['voices']);
        }
      }
      return ['lessac', 'amy', 'alan']; // Default voices
    } catch (e) {
      debugPrint('Failed to get voices: $e');
      return ['lessac', 'amy', 'alan'];
    }
  }
}
