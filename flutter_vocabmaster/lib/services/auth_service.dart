import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../config/app_config.dart';
import 'local_database_service.dart';
import 'xp_manager.dart';

/// Kullanıcı oturum ve profil yönetimi servisi
class AuthService {
  static const String _tokenKey = 'session_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _userDataKey = 'user_data';
  static const String _rememberMeKey = 'remember_me';

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
    final serverClientId = dotenv.env['GOOGLE_WEB_CLIENT_ID'];
    if (serverClientId != null && serverClientId.isNotEmpty) {
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
    _cachedToken = prefs.getString(_tokenKey);
    return _cachedToken;
  }

  Future<String?> getRefreshToken() async {
    if (_cachedRefreshToken != null) return _cachedRefreshToken;

    final prefs = await SharedPreferences.getInstance();
    _cachedRefreshToken = prefs.getString(_refreshTokenKey);
    return _cachedRefreshToken;
  }

  /// Kullanıcı verilerini al
  Future<Map<String, dynamic>?> getUser() async {
    if (_cachedUser != null) return _cachedUser;

    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString(_userDataKey);
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
    final baseUrl = await AppConfig.apiBaseUrl;
    final loginUri = Uri.parse('$baseUrl/auth/login');
    try {
      final response = await http.post(
        loginUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'emailOrTag': email,
          'password': password,
          'deviceInfo': 'Flutter Mobile App',
        }),
      );

      final data = jsonDecode(response.body);

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

        // Offline giriş için şifre hash'ini kaydet
        await _saveOfflineCredentials(email, password, user);

        return {'success': true, 'user': user};
      } else {
        return {
          'success': false,
          'message': data['error'] ?? 'Giriş başarısız'
        };
      }
    } catch (e) {
      // Bağlantı hatası durumunda offline giriş dene
      print('Online login failed for $loginUri, trying offline: $e');
      final offline = await _tryOfflineLogin(email, password);
      if (offline['success'] == true) {
        return offline;
      }
      // Offline login yoksa/başarısızsa, online hatayı mesajda göster ki root-cause net olsun.
      final offlineMsg = offline['message']?.toString().trim();
      final msgPrefix = (offlineMsg != null && offlineMsg.isNotEmpty)
          ? '$offlineMsg\n'
          : '';
      return {
        'success': false,
        'message': '${msgPrefix}Bağlantı hatası: $e\nURL: $loginUri',
      };
    }
  }

  Future<void> _saveOfflineCredentials(
      String email, String password, Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('offline_email', email.toLowerCase());
    await prefs.setString('offline_password_hash', _hashPassword(password));
    // User data is already saved in saveSession via user_data key
  }

  Future<Map<String, dynamic>> _tryOfflineLogin(
      String email, String password) async {
    final prefs = await SharedPreferences.getInstance();

    final cachedEmail = prefs.getString('offline_email');
    final cachedPasswordHash = prefs.getString('offline_password_hash');
    final cachedUserData =
        prefs.getString(_userDataKey); // saveSession'da kullanılan key

    if (cachedEmail == null ||
        cachedPasswordHash == null ||
        cachedUserData == null) {
      return {
        'success': false,
        'message':
            'İnternet bağlantısı yok ve kayıtlı offline oturum bulunamadı.'
      };
    }

    // Email kontrolü (hashlenmiş email ile de yapılabilirdi ama basitçe lowercase)
    // Email veya Tag girişi olduğu için cachedEmail ile eşleşiyor mu basitçe bakıyoruz
    // Tag ile offline giriş zor olabilir, sadece email'i cacheledik.
    // Kullanıcıya kolaylık olsun diye, eğer inputcached email ile eşleşiyorsa kabul edelim.

    if (email.toLowerCase() != cachedEmail.toLowerCase()) {
      // Belki kullanıcı tag girdi? Offline modda tag desteği zor.
      // Şimdilik sadece email match
      return {
        'success': false,
        'message':
            'Offline modda email eşleşmedi. Lütfen son kullandığınız email ile deneyin.'
      };
    }

    if (_hashPassword(password) != cachedPasswordHash) {
      return {'success': false, 'message': 'Şifre hatalı (Offline)'};
    }

    // Başarılı Offline Giriş
    try {
      final user = jsonDecode(cachedUserData);
      // Token'ı yenilemeye gerek yok, eskisi kalsın veya dummy
      // _cachedUser vs güncellenmeli
      _cachedUser = user;
      return {'success': true, 'user': user, 'isOffline': true};
    } catch (e) {
      return {'success': false, 'message': 'Offline kullanıcı verisi bozuk.'};
    }
  }

  String _hashPassword(String password) {
    // Basit hash - gerçek production için crypto kütüphanesi kullanılmalı
    var hash = 0;
    for (var i = 0; i < password.length; i++) {
      hash = ((hash << 5) - hash) + password.codeUnitAt(i);
      hash = hash & 0xFFFFFFFF;
    }
    return hash.toString();
  }

  /// Register (Kayıt Ol)
  Future<Map<String, dynamic>> register(
      String name, String email, String password) async {
    final baseUrl = await AppConfig.apiBaseUrl;
    final registerUri = Uri.parse('$baseUrl/auth/register');
    try {
      final response = await http.post(
        registerUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'displayName': name, // Backend expects displayName
          'deviceInfo': 'Flutter Mobile App',
        }),
      );

      final data = jsonDecode(response.body);

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
        'message': 'Bağlantı hatası: $e\nURL: $registerUri',
      };
    }
  }

  /// Google Login
  Future<Map<String, dynamic>> googleLogin() async {
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
      final requestBody = <String, dynamic>{
        'email': googleUser.email,
        'displayName': googleUser.displayName ?? googleUser.email.split('@')[0],
        'photoUrl': googleUser.photoUrl,
        'googleId': googleUser.id,
        'deviceInfo': 'Flutter Mobile App',
      };
      if (idToken != null && idToken.isNotEmpty) {
        requestBody['idToken'] = idToken;
      }
      _debugLog(
        'POST $baseUrl/auth/google-login with googleId=${googleUser.id} email=${googleUser.email}',
      );
      final response = await http.post(
        Uri.parse('$baseUrl/auth/google-login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      final data = jsonDecode(response.body);
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
      return {'success': false, 'message': 'Google giriş hatası: $e'};
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

    await prefs.setString(_tokenKey, token);
    await prefs.setString(_refreshTokenKey, refreshToken);
    await prefs.setString(_userDataKey, jsonEncode(user));
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userDataKey, jsonEncode(user));
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
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_userDataKey);
    await prefs.remove('offline_email');
    await prefs.remove('offline_password_hash');
    // Remember me kalsın mı? Genelde logout olunca her şey silinir.

    _cachedToken = null;
    _cachedRefreshToken = null;
    _cachedUser = null;
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
  }

  Future<int?> _resolveStoredUserId(SharedPreferences prefs) async {
    final cachedId = _toInt(_cachedUser?['id']) ?? _toInt(_cachedUser?['userId']);
    if (cachedId != null && cachedId > 0) {
      return cachedId;
    }

    final rawUser = prefs.getString(_userDataKey);
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
    XPManager.resetIdempotency();
  }

  /// Profil bilgilerini backend'den yenile
  Future<Map<String, dynamic>?> refreshProfile() async {
    // Backend'de /me endpoint'i auth_controller'da yoktu.
    // Şimdilik cached datayı dön
    return getUser();
  }

  /// Kullanıcı ID'sini al
  Future<int?> getUserId() async {
    final user = await getUser();
    final userId = _toInt(user?['id']) ?? _toInt(user?['userId']);
    if (userId != null && userId > 0) {
      if (!_hasLoggedUserIdResolution) {
        _debugLog('getUserId resolved from user payload: $userId');
        _hasLoggedUserIdResolution = true;
      }
      return userId;
    }

    final token = await getToken();
    final jwtUserId = _extractUserIdFromJwt(token);
    if (jwtUserId != null && jwtUserId > 0) {
      if (!_hasLoggedUserIdResolution) {
        _debugLog('getUserId resolved from jwt: $jwtUserId');
        _hasLoggedUserIdResolution = true;
      }
      if (user != null) {
        final updatedUser = Map<String, dynamic>.from(user);
        updatedUser['id'] = jwtUserId;
        updatedUser['userId'] = jwtUserId;
        await updateUser(updatedUser);
      }
      return jwtUserId;
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
