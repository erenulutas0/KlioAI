import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/config/app_config.dart';

void main() {
  group('AppConfig.normalizeAndValidateBaseUrl', () {
    test('accepts server root URLs and trims trailing api path', () {
      expect(
        AppConfig.normalizeAndValidateBaseUrl(
          'https://api.example.com/api/',
        ),
        'https://api.example.com',
      );

      expect(
        AppConfig.normalizeAndValidateBaseUrl(
          'http://192.168.1.102:8082',
        ),
        'http://192.168.1.102:8082',
      );
    });

    test('rejects whitespace in backend URL', () {
      expect(
        () => AppConfig.normalizeAndValidateBaseUrl(
          'https://sanda-sheathiest- & c',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('spaces are not allowed'),
          ),
        ),
      );
    });

    test('rejects accidental path/query fragments in backend URL', () {
      expect(
        () => AppConfig.normalizeAndValidateBaseUrl(
          'https://example.com/flutter/src/flutter/bin/internal/exit_with_errorlevel.bat',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('without extra path/query/fragment parts'),
          ),
        ),
      );

      expect(
        () => AppConfig.normalizeAndValidateBaseUrl(
          'https://example.com?foo=bar',
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
