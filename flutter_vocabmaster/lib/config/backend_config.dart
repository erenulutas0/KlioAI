import 'package:flutter/foundation.dart';
import 'dotenv_safe.dart';

class BackendConfig {
  static const String _defineBackendUrl =
      String.fromEnvironment('BACKEND_URL', defaultValue: '');
  static const String _defineApiPort =
      String.fromEnvironment('API_PORT', defaultValue: '');
  static const String _defineProdBackendUrl =
      String.fromEnvironment(
        'PROD_BACKEND_URL',
        defaultValue: 'https://api.klioai.app',
      );

  static String get baseUrl {
    final explicitBackendUrl = _defineBackendUrl.trim().isNotEmpty
        ? _defineBackendUrl.trim()
        : readDotEnvOrDefault('BACKEND_URL').trim();
    if (explicitBackendUrl.isNotEmpty) {
      return explicitBackendUrl;
    }

    if (!kDebugMode) {
      return _defineProdBackendUrl;
    }

    final port = _defineApiPort.trim().isNotEmpty
        ? _defineApiPort.trim()
        : readDotEnvOrDefault('API_PORT', '8082').trim();

    // Web için localhost
    if (kIsWeb) {
      return 'http://localhost:$port';
    }

    // Tanımlı değilse varsayılan olarak Emülatör IP'si
    return 'http://10.0.2.2:$port';
  }
}
