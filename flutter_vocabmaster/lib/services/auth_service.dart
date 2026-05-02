import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import '../config/app_config.dart';
import '../config/dotenv_safe.dart';
import 'google_login_error_message_formatter.dart';
import 'local_database_service.dart';
import 'xp_manager.dart';

/// Kullanıcı oturum ve profil yönetimi servisi
class AuthService {
  static const String _tokenKey = 'session_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _userDataKey = 'user_data';
  static const String _rememberMeKey = 'remember_me';
  static const String _deviceIdKey = 'install_device_id';
  static const String _forcedResetMigrationKey =
      'forced_auth_reset_2026_04_23_v2';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // Singleton pattern
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  // Google Sign In
  late final GoogleSignIn _googleSignIn = _createGoogleSignIn();

  // Cache
  Map<String, dynamic>? _cachedUser;
  String? _cachedToken;
  String? _cachedRefreshToken;
  bool _hasLoggedUserIdResolution = false;
  bool _hasLoggedUserIdFailure = false;

  void _debugLog(String message) {
    if (!kDebugMode) return;
    debugPrint('[AUTH_DEBUG] $message');
  }

  GoogleSignIn _createGoogleSignIn() {
    final serverClientId = readDotEnvOrDefault('GOOGLE_WEB_CLIENT_ID');
    if (serverClientId.isNotEmpty) {
      return GoogleSignIn(
        scopes: ['email', 'profile'],
        serverClientId: serverClientId,
      );
    }
    return GoogleSignIn(
      scopes: ['email', 'profile'],
    );
  }

  /// Oturum token'ını al
  Future<String?> getToken() async {
    if (_cachedToken != null) return _cachedToken;

    final prefs = await SharedPreferences.getInstance();
    await _removeLegacyOfflineCredentials(prefs);
    _cachedToken = await _readSecureOrMigrate(_tokenKey, prefs);
    return _cachedToken;
  }

  Future<String?> getRefreshToken() async {
    if (_cachedRefreshToken != null) return _cachedRefreshToken;

    final prefs = await SharedPreferences.getInstance();
    _cachedRefreshToken = await _readSecureOrMigrate(_refreshTokenKey, prefs);
    return _cachedRefreshToken;
  }

  Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final random = Random.secure();
    final suffix = List.generate(16, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    final deviceId = 'vm-$suffix';
    await prefs.setString(_deviceIdKey, deviceId);
    return deviceId;
  }

  /// Kullanıcı verilerini al
  Future<Map<String, dynamic>?> getUser() async {
    if (_cachedUser != null) return _cachedUser;

    final prefs = await SharedPreferences.getInstance();
    await _removeLegacyOfflineCredentials(prefs);
    final userData = await _readSecureOrMigrate(_userDataKey, prefs);
    if (userData != null) {
      try {
        _cachedUser = jsonDecode(userData);
        return _cachedUser;
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  /// Kullanıcı giriş yapmış mı?
  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  /// Login (E-posta & Şifre)
  Future<Map<String, dynamic>> login(String email, String password,
      {bool rememberMe = false}) async {
    Uri? loginUri;
    try {
      final baseUrl = await AppConfig.apiBaseUrl;
      final deviceId = await getOrCreateDeviceId();
      loginUri = Uri.parse('$baseUrl/auth/login');
      final response = await http.post(
        loginUri,
        headers: {
          'Content-Type': 'application/json',
          'X-Device-Id': deviceId,
        },
        body: jsonEncode({
          'emailOrTag': email,
          'password': password,
          'deviceInfo': 'Flutter Mobile App',
          'deviceId': deviceId,
        }),
      );

      final data = _decodeResponseBodyMap(
        response.body,
        context: 'login',
        url: loginUri,
      );

      if (response.statusCode == 200 && data['success'] == true) {
        final token = data['accessToken'] ?? data['sessionToken'];
        final refreshToken = data['refreshToken'];
        if (token == null || refreshToken == null) {
          return {'success': false, 'message': 'Token alınamadı'};
        }

        final user = _normalizeUserPayload(
          data['user'],
          fallback: {
            'id': data['userId'],
            'email': email,
            'role': 'USER',
            'displayName': email.split('@')[0],
            'userTag': '#00000',
          },
          responseData: data,
        );

        await saveSession(token, refreshToken, user, rememberMe: rememberMe);

        return {'success': true, 'user': user};
      } else {
        return {
          'success': false,
          'message': data['error'] ?? 'Giriş başarısız'
        };
      }
    } catch (e) {
      debugPrint('Online login failed for $loginUri: $e');
      return {
        'success': false,
        'message':
            'Bağlantı hatası: $e\nURL: ${loginUri?.toString() ?? 'cozulmedi'}',
      };
    }
  }

  Map<String, dynamic> _decodeResponseBodyMap(
    String body, {
    required String context,
    Uri? url,
  }) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      throw FormatException(
        'Unexpected empty response during $context. URL: ${url?.toString() ?? 'unknown'}',
      );
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      throw FormatException(
        'Expected JSON object during $context but received ${decoded.runtimeType}. URL: ${url?.toString() ?? 'unknown'}',
      );
    } catch (_) {
      final preview =
          trimmed.length > 220 ? '${trimmed.substring(0, 220)}...' : trimmed;
      throw FormatException(
        'Unexpected non-JSON response during $context. URL: ${url?.toString() ?? 'unknown'} Body: $preview',
      );
    }
  }

  /// Register (Kayıt Ol)
  Future<Map<String, dynamic>> register(
      String name, String email, String password) async {
    Uri? registerUri;
    try {
      final baseUrl = await AppConfig.apiBaseUrl;
      final deviceId = await getOrCreateDeviceId();
      registerUri = Uri.parse('$baseUrl/auth/register');
      final response = await http.post(
        registerUri,
        headers: {
          'Content-Type': 'application/json',
          'X-Device-Id': deviceId,
        },
        body: jsonEncode({
          'email': email,
          'password': password,
          'displayName': name, // Backend expects displayName
          'deviceInfo': 'Flutter Mobile App',
          'deviceId': deviceId,
        }),
      );

      final data = _decodeResponseBodyMap(
        response.body,
        context: 'register',
        url: registerUri,
      );

      if (response.statusCode == 200 && data['success'] == true) {
        final token = data['accessToken'] ?? data['sessionToken'];
        final refreshToken = data['refreshToken'];
        if (token != null && refreshToken != null) {
          final user = _normalizeUserPayload(
            data['user'],
            fallback: {
              'id': data['userId'],
              'email': email,
              'role': 'USER',
              'displayName': name,
              'userTag': '#00000',
            },
            responseData: data,
          );
          await saveSession(token, refreshToken, user);
          return {'success': true, 'user': user};
        }
        return await login(email, password, rememberMe: true);
      } else {
        return {
          'success': false,
          'message': data['error'] ?? 'Kayıt başarısız'
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message':
            'Bağlantı hatası: $e\nURL: ${registerUri?.toString() ?? 'cozulmedi'}',
      };
    }
  }

  /// Google Login
  Future<Map<String, dynamic>> googleLogin() async {
    Uri? googleLoginUri;
    try {
      _debugLog('googleLogin started');
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        _debugLog('googleLogin cancelled by user');
        return {'success': false, 'message': 'Giriş iptal edildi'};
      }
      _debugLog(
        'google account id=${googleUser.id}, email=${googleUser.email}, displayName=${googleUser.displayName}',
      );

      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      _debugLog(
        'google auth idTokenPresent=${idToken != null && idToken.isNotEmpty}, accessTokenPresent=${googleAuth.accessToken != null && googleAuth.accessToken!.isNotEmpty}',
      );

      // Backend /google-login endpoint'ini kullan
      final baseUrl = await AppConfig.apiBaseUrl;
      final deviceId = await getOrCreateDeviceId();
      final requestBody = <String, dynamic>{
        'email': googleUser.email,
        'displayName': googleUser.displayName ?? googleUser.email.split('@')[0],
        'photoUrl': googleUser.photoUrl,
        'googleId': googleUser.id,
        'deviceInfo': 'Flutter Mobile App',
        'deviceId': deviceId,
      };
      if (idToken != null && idToken.isNotEmpty) {
        requestBody['idToken'] = idToken;
      }
      _debugLog(
        'POST $baseUrl/auth/google-login with googleId=${googleUser.id} email=${googleUser.email}',
      );
      googleLoginUri = Uri.parse('$baseUrl/auth/google-login');
      final response = await http.post(
        googleLoginUri,
        headers: {
          'Content-Type': 'application/json',
          'X-Device-Id': deviceId,
        },
        body: jsonEncode(requestBody),
      );

      final data = _decodeResponseBodyMap(
        response.body,
        context: 'google-login',
        url: googleLoginUri,
      );
      final responseUser = data['user'];
      final responseUserId = responseUser is Map
          ? _toInt(responseUser['id']) ?? _toInt(responseUser['userId'])
          : null;
      _debugLog(
        'google-login response status=${response.statusCode}, success=${data['success']}, userIdField=${data['userId']}, user.id=$responseUserId',
      );

      if (response.statusCode == 200 && data['success'] == true) {
        final token = data['accessToken'] ?? data['sessionToken'];
        final refreshToken = data['refreshToken'];
        if (token == null || refreshToken == null) {
          return {'success': false, 'message': 'Token alınamadı'};
        }

        final user = _normalizeUserPayload(
          data['user'],
          fallback: {
            'id': data['userId'],
            'email': googleUser.email,
            'role': 'USER',
            'displayName':
                googleUser.displayName ?? googleUser.email.split('@')[0],
            'userTag': '#00000',
          },
          responseData: data,
        );
        _debugLog(
          'normalized user id=${user['id']} userId=${user['userId']} email=${user['email']}',
        );

        await saveSession(token, refreshToken, user);
        final resolvedId = await getUserId();
        _debugLog('googleLogin final getUserId=$resolvedId');
        return {'success': true, 'user': user};
      } else {
        _debugLog('googleLogin failed message=${data['error']}');
        return {
          'success': false,
          'message': data['error'] ?? 'Google ile giriş başarısız'
        };
      }
    } catch (e) {
      _debugLog('googleLogin exception=$e');
      return {
        'success': false,
        'message': GoogleLoginErrorMessageFormatter.format(e),
      };
    }
  }

  /// Oturumu kaydet
  Future<void> saveSession(
      String token, String refreshToken, Map<String, dynamic> user,
      {bool rememberMe = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final previousUserId = await _resolveStoredUserId(prefs);
    final resolvedId = _toInt(user['id']) ?? _toInt(user['userId']);

    // Prevent cross-account data leakage on shared devices.
    if (previousUserId != null &&
        resolvedId != null &&
        previousUserId != resolvedId) {
      await _clearLocalLearningState(prefs);
    }

    await _writeSecureString(_tokenKey, token);
    await _writeSecureString(_refreshTokenKey, refreshToken);
    await _writeSecureString(_userDataKey, jsonEncode(user));
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_userDataKey);
    await _removeLegacyOfflineCredentials(prefs);
    await prefs.setBool(_rememberMeKey, rememberMe);
    _cachedToken = token;
    _cachedRefreshToken = refreshToken;
    _cachedUser = user;
    _debugLog(
      'saveSession rememberMe=$rememberMe userId=$resolvedId email=${user['email']}',
    );
  }

  /// Kullanıcı bilgilerini güncelle
  Future<void> updateUser(Map<String, dynamic> user) async {
    await _writeSecureString(_userDataKey, jsonEncode(user));
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userDataKey);
    _cachedUser = user;
  }

  /// Çıkış yap
  Future<void> logout() async {
    final token = await getToken();
    final refreshToken = await getRefreshToken();

    if (token != null) {
      try {
        final baseUrl = await AppConfig.apiBaseUrl;
        await http.post(
          Uri.parse('$baseUrl/auth/logout'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            if (refreshToken != null) 'refreshToken': refreshToken,
          }),
        );
      } catch (e) {
        // Sessizce geç
      }
    }

    // Yerel verileri temizle
    final prefs = await SharedPreferences.getInstance();
    await _clearLocalLearningState(prefs);
    await _deleteSecureString(_tokenKey);
    await _deleteSecureString(_refreshTokenKey);
    await _deleteSecureString(_userDataKey);
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_userDataKey);
    await _removeLegacyOfflineCredentials(prefs);
    // Remember me kalsın mı? Genelde logout olunca her şey silinir.

    _cachedToken = null;
    _cachedRefreshToken = null;
    _cachedUser = null;
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
  }

  Future<bool> enforceMandatorySessionResetIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_forcedResetMigrationKey) == true) {
      return false;
    }

    await _clearLocalSessionOnly(prefs, disconnectGoogle: true);
    await prefs.setBool(_forcedResetMigrationKey, true);
    _debugLog('mandatory local session reset applied');
    return true;
  }

  Future<String?> _readSecureOrMigrate(
      String key, SharedPreferences prefs) async {
    final secureValue = await _readSecureString(key);
    if (secureValue != null && secureValue.isNotEmpty) {
      if (prefs.containsKey(key)) {
        await prefs.remove(key);
      }
      return secureValue;
    }

    final legacyValue = prefs.getString(key);
    if (legacyValue == null || legacyValue.isEmpty) {
      return null;
    }

    await _writeSecureString(key, legacyValue);
    await prefs.remove(key);
    return legacyValue;
  }

  Future<String?> _readSecureString(String key) async {
    try {
      return await _secureStorage.read(key: key);
    } catch (e) {
      _debugLog('secure storage read failed for $key: $e');
      return null;
    }
  }

  Future<void> _writeSecureString(String key, String value) async {
    try {
      await _secureStorage.write(key: key, value: value);
    } catch (e) {
      _debugLog('secure storage write failed for $key: $e');
      throw StateError('Secure session storage is unavailable');
    }
  }

  Future<void> _deleteSecureString(String key) async {
    try {
      await _secureStorage.delete(key: key);
    } catch (e) {
      _debugLog('secure storage delete failed for $key: $e');
    }
  }

  Future<void> _removeLegacyOfflineCredentials(SharedPreferences prefs) async {
    await prefs.remove('offline_email');
    await prefs.remove('offline_password_hash');
  }

  Future<int?> _resolveStoredUserId(SharedPreferences prefs) async {
    final cachedId =
        _toInt(_cachedUser?['id']) ?? _toInt(_cachedUser?['userId']);
    if (cachedId != null && cachedId > 0) {
      return cachedId;
    }

    final rawUser = await _readSecureOrMigrate(_userDataKey, prefs);
    if (rawUser == null || rawUser.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(rawUser);
      if (decoded is Map<String, dynamic>) {
        final id = _toInt(decoded['id']) ?? _toInt(decoded['userId']);
        if (id != null && id > 0) {
          return id;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _clearLocalLearningState(SharedPreferences prefs) async {
    try {
      await LocalDatabaseService().clearAll();
    } catch (e) {
      _debugLog('local DB clear failed: $e');
    }

    final keys = prefs.getKeys().toList(growable: false);
    for (final key in keys) {
      final shouldRemove = key == 'total_xp_persistent' ||
          key == 'xp_transactions' ||
          key == 'current_streak' ||
          key == 'last_activity_date' ||
          key == 'weekly_activity' ||
          key.startsWith('xp_') ||
          key.startsWith('xp_awarded_') ||
          key.startsWith('learned_today_');
      if (shouldRemove) {
        await prefs.remove(key);
      }
    }
    XPManager.clearIdempotencyCache();
  }

  Future<void> _clearLocalSessionOnly(
    SharedPreferences prefs, {
    required bool disconnectGoogle,
  }) async {
    await _clearLocalLearningState(prefs);
    await _deleteSecureString(_tokenKey);
    await _deleteSecureString(_refreshTokenKey);
    await _deleteSecureString(_userDataKey);
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_userDataKey);
    await prefs.remove(_rememberMeKey);
    await _removeLegacyOfflineCredentials(prefs);
    _cachedToken = null;
    _cachedRefreshToken = null;
    _cachedUser = null;

    if (disconnectGoogle) {
      try {
        await _googleSignIn.signOut();
      } catch (_) {}
      try {
        await _googleSignIn.disconnect();
      } catch (_) {}
    }
  }

  /// Profil bilgilerini backend'den yenile
  Future<Map<String, dynamic>?> refreshProfile() async {
    final userId = await getUserId();
    if (userId == null || userId <= 0) {
      return getUser();
    }

    final token = await getToken();
    final baseUrl = await AppConfig.apiBaseUrl;
    final response = await http.get(
      Uri.parse('$baseUrl/users/$userId'),
      headers: {
        'Content-Type': 'application/json',
        'X-User-Id': userId.toString(),
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Profil yenilenemedi: HTTP ${response.statusCode}');
    }

    final profile = _decodeResponseBodyMap(
      response.body,
      context: 'refresh-profile',
      url: Uri.parse('$baseUrl/users/$userId'),
    );
    final merged =
        Map<String, dynamic>.from(await getUser() ?? <String, dynamic>{})
          ..addAll(profile);
    await updateUser(merged);
    return merged;
  }

  /// Kullanıcı ID'sini al
  Future<bool> refreshSession() async {
    final refreshToken = await getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      return false;
    }

    try {
      final baseUrl = await AppConfig.apiBaseUrl;
      final deviceId = await getOrCreateDeviceId();
      final response = await http.post(
        Uri.parse('$baseUrl/auth/refresh'),
        headers: {
          'Content-Type': 'application/json',
          'X-Device-Id': deviceId,
        },
        body: jsonEncode({
          'refreshToken': refreshToken,
          'deviceInfo': 'Flutter Mobile App',
          'deviceId': deviceId,
        }),
      );

      if (response.statusCode != 200) {
        _debugLog('refreshSession failed with status=${response.statusCode}');
        return false;
      }

      final data = _decodeResponseBodyMap(
        response.body,
        context: 'refresh-session',
        url: Uri.parse('$baseUrl/auth/refresh'),
      );
      final newAccessToken =
          (data['accessToken'] ?? data['sessionToken'])?.toString();
      final newRefreshToken = (data['refreshToken'] ?? refreshToken).toString();
      if (newAccessToken == null || newAccessToken.isEmpty) {
        return false;
      }

      final currentUser =
          Map<String, dynamic>.from(await getUser() ?? <String, dynamic>{});
      final refreshedUserId = _toInt(data['userId']);
      if (refreshedUserId != null && refreshedUserId > 0) {
        currentUser['id'] = refreshedUserId;
        currentUser['userId'] = refreshedUserId;
      }
      currentUser['role'] = data['role'] ?? currentUser['role'] ?? 'USER';
      currentUser['email'] = currentUser['email'] ?? '';
      currentUser['displayName'] = currentUser['displayName'] ?? 'User';
      currentUser['userTag'] = currentUser['userTag'] ?? '#00000';

      await saveSession(
        newAccessToken,
        newRefreshToken,
        currentUser,
      );
      return true;
    } catch (e) {
      _debugLog('refreshSession exception=$e');
      return false;
    }
  }

  Future<int?> getUserId() async {
    final user = await getUser();
    final token = await getToken();
    final jwtUserId = _extractUserIdFromJwt(token);
    if (jwtUserId != null && jwtUserId > 0) {
      if (!_hasLoggedUserIdResolution) {
        _debugLog('getUserId resolved from jwt: $jwtUserId');
        _hasLoggedUserIdResolution = true;
      }
      final storedUserId = _toInt(user?['id']) ?? _toInt(user?['userId']);
      if (user != null && storedUserId != jwtUserId) {
        final updatedUser = Map<String, dynamic>.from(user);
        updatedUser['id'] = jwtUserId;
        updatedUser['userId'] = jwtUserId;
        await updateUser(updatedUser);
      }
      return jwtUserId;
    }

    final userId = _toInt(user?['id']) ?? _toInt(user?['userId']);
    if (userId != null && userId > 0) {
      if (!_hasLoggedUserIdResolution) {
        _debugLog('getUserId resolved from user payload: $userId');
        _hasLoggedUserIdResolution = true;
      }
      return userId;
    }
    if (!_hasLoggedUserIdFailure) {
      _debugLog('getUserId could not resolve user id');
      _hasLoggedUserIdFailure = true;
    }
    return null;
  }

  Map<String, dynamic> _normalizeUserPayload(
    dynamic rawUser, {
    Map<String, dynamic>? fallback,
    Map<String, dynamic>? responseData,
  }) {
    final normalized = <String, dynamic>{};

    if (rawUser is Map<String, dynamic>) {
      normalized.addAll(rawUser);
    } else if (rawUser is Map) {
      normalized.addAll(Map<String, dynamic>.from(rawUser));
    }

    if (normalized.isEmpty && fallback != null) {
      normalized.addAll(fallback);
    }

    final id = _toInt(normalized['id']) ??
        _toInt(normalized['userId']) ??
        _toInt(responseData?['userId']) ??
        _toInt(fallback?['id']) ??
        _toInt(fallback?['userId']);
    if (id != null && id > 0) {
      normalized['id'] = id;
      normalized['userId'] = id;
    }

    normalized['email'] ??= responseData?['email'] ?? fallback?['email'] ?? '';
    normalized['displayName'] ??=
        responseData?['displayName'] ?? fallback?['displayName'] ?? 'User';
    normalized['role'] ??= responseData?['role'] ?? fallback?['role'] ?? 'USER';
    normalized['userTag'] ??=
        responseData?['userTag'] ?? fallback?['userTag'] ?? '#00000';

    return normalized;
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  int? _extractUserIdFromJwt(String? token) {
    if (token == null || token.isEmpty) return null;
    final parts = token.split('.');
    if (parts.length < 2) return null;

    try {
      final payloadBytes = base64Url.decode(base64Url.normalize(parts[1]));
      final payloadText = utf8.decode(payloadBytes);
      final payload = jsonDecode(payloadText);
      if (payload is! Map) return null;
      return _toInt(
        payload['userId'] ?? payload['uid'] ?? payload['sub'] ?? payload['id'],
      );
    } catch (_) {
      return null;
    }
  }
}
