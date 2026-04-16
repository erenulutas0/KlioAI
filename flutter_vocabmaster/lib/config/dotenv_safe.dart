import 'package:flutter_dotenv/flutter_dotenv.dart';

String readDotEnvOrDefault(String key, [String fallback = '']) {
  try {
    return dotenv.env[key] ?? fallback;
  } catch (_) {
    return fallback;
  }
}
