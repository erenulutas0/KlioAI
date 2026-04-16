import 'dart:io' show Platform;
import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, visibleForTesting;
import 'package:device_info_plus/device_info_plus.dart';
import 'dotenv_safe.dart';

class AppConfig {
  static const String _defineBackendUrl =
      String.fromEnvironment('BACKEND_URL', defaultValue: '');
  static const String _defineApiPort =
      String.fromEnvironment('API_PORT', defaultValue: '');
  static const String _defineLocalhostIp =
      String.fromEnvironment('LOCALHOST_IP', defaultValue: '');
  static const String _defineEmulatorIp =
      String.fromEnvironment('EMULATOR_IP', defaultValue: '');
  static const String _defineRealDeviceIp =
      String.fromEnvironment('REAL_DEVICE_IP', defaultValue: '');
  static const String _defineProdBackendUrl =
      String.fromEnvironment(
        'PROD_BACKEND_URL',
        defaultValue: 'https://api.klioai.app',
      );

  static String? _cachedBaseUrl;

  static String _readConfigValue(
    String defineValue,
    String envKey,
    String fallback,
  ) {
    final trimmedDefine = defineValue.trim();
    if (trimmedDefine.isNotEmpty) {
      return trimmedDefine;
    }

    final trimmedEnv = readDotEnvOrDefault(envKey).trim();
    if (trimmedEnv.isNotEmpty) {
      return trimmedEnv;
    }

    return fallback;
  }

  static String _normalizeBaseUrl(String value) {
    var normalized = value.trim();
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (normalized.endsWith('/api')) {
      normalized = normalized.substring(0, normalized.length - 4);
    }
    return normalized;
  }

  @visibleForTesting
  static String normalizeAndValidateBaseUrl(
    String value, {
    String sourceLabel = 'BACKEND_URL',
  }) {
    final normalized = _normalizeBaseUrl(value);
    final compactSource = sourceLabel.trim().isEmpty
        ? 'BACKEND_URL'
        : sourceLabel.trim();

    if (normalized.isEmpty) {
      throw FormatException(
        'Invalid $compactSource: empty value. Expected an absolute http/https backend URL.',
      );
    }

    if (RegExp(r'\s').hasMatch(normalized)) {
      throw FormatException(
        'Invalid $compactSource: spaces are not allowed. '
        'Expected a backend root URL like https://api.example.com or https://api.klioai.app. '
        'Received: $normalized',
      );
    }

    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.isAbsolute) {
      throw FormatException(
        'Invalid $compactSource: expected an absolute http/https backend URL. '
        'Received: $normalized',
      );
    }

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      throw FormatException(
        'Invalid $compactSource: only http and https are supported. '
        'Received: $normalized',
      );
    }

    if (uri.host.isEmpty ||
        uri.authority.contains('&') ||
        uri.authority.contains('%20')) {
      throw FormatException(
        'Invalid $compactSource: host is malformed. '
        'Received: $normalized',
      );
    }

    final hasUnexpectedPath = uri.path.isNotEmpty && uri.path != '/';
    if (hasUnexpectedPath || uri.hasQuery || uri.hasFragment) {
      throw FormatException(
        'Invalid $compactSource: use only the server root URL, without extra path/query/fragment parts. '
        'Example: https://api.example.com or https://api.klioai.app. '
        'Received: $normalized',
      );
    }

    return normalized;
  }

  static String _cacheValidatedBaseUrl(
    String candidate, {
    required String sourceLabel,
  }) {
    _cachedBaseUrl = normalizeAndValidateBaseUrl(
      candidate,
      sourceLabel: sourceLabel,
    );
    return _cachedBaseUrl!;
  }

  static Future<String> get baseUrl async {
    if (_cachedBaseUrl != null) return _cachedBaseUrl!;

    final port = _readConfigValue(_defineApiPort, 'API_PORT', '8082');

    // Prefer dart-define in release builds so testers do not inherit bundled dev .env values.
    // `BACKEND_URL` should be the server root, without `/api`.
    // Example: https://api.klioai.app
    final explicit = _readConfigValue(_defineBackendUrl, 'BACKEND_URL', '');
    if (explicit.isNotEmpty) {
      return _cacheValidatedBaseUrl(
        explicit,
        sourceLabel: 'BACKEND_URL',
      );
    }

    if (!kDebugMode) {
      return _cacheValidatedBaseUrl(
        _defineProdBackendUrl,
        sourceLabel: 'PROD_BACKEND_URL',
      );
    }

    if (kIsWeb) {
      final localhostIp =
          _readConfigValue(_defineLocalhostIp, 'LOCALHOST_IP', 'localhost');
      return _cacheValidatedBaseUrl(
        'http://$localhostIp:$port',
        sourceLabel: 'LOCALHOST_IP/API_PORT',
      );
    } else if (Platform.isAndroid) {
      // Check if running on emulator or real device
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final isEmulator = !androidInfo.isPhysicalDevice;

      if (isEmulator) {
        // Emulator: use 10.0.2.2
        final emulatorIp =
            _readConfigValue(_defineEmulatorIp, 'EMULATOR_IP', '10.0.2.2');
        return _cacheValidatedBaseUrl(
          'http://$emulatorIp:$port',
          sourceLabel: 'EMULATOR_IP/API_PORT',
        );
      } else {
        // Real device: use PC's local network IP
        final realDeviceIp = _readConfigValue(
          _defineRealDeviceIp,
          'REAL_DEVICE_IP',
          '192.168.1.100',
        );
        return _cacheValidatedBaseUrl(
          'http://$realDeviceIp:$port',
          sourceLabel: 'REAL_DEVICE_IP/API_PORT',
        );
      }
    } else {
      final localhostIp =
          _readConfigValue(_defineLocalhostIp, 'LOCALHOST_IP', 'localhost');
      return _cacheValidatedBaseUrl(
        'http://$localhostIp:$port',
        sourceLabel: 'LOCALHOST_IP/API_PORT',
      );
    }
  }

  static Future<String> get apiBaseUrl async => '${await baseUrl}/api';
}
