import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/services/google_login_error_message_formatter.dart';

void main() {
  group('GoogleLoginErrorMessageFormatter', () {
    test('formats offline ngrok backend response as stale build guidance', () {
      final message = GoogleLoginErrorMessageFormatter.format(
        const FormatException(
          'Unexpected non-JSON response during google-login. '
          'URL: https://sanda-sheathiest-uncredulously.ngrok-free.dev/api/auth/google-login '
          'Body: The endpoint sanda-sheathiest-uncredulously.ngrok-free.dev is offline.',
        ),
      );

      expect(message, contains('old ngrok backend'));
      expect(message, contains('https://api.klioai.app'));
      expect(message, isNot(contains('email login')));
    });

    test('maps developer configuration errors to Play signing guidance', () {
      final message = GoogleLoginErrorMessageFormatter.format(
        Exception('ApiException: 10: DEVELOPER_ERROR'),
      );

      expect(message, contains('Google login configuration issue'));
      expect(message, contains('app signing SHA'));
      expect(message, contains('latest Play build'));
      expect(message, isNot(contains('email login')));
    });

    test('maps Google service error 12500 without suggesting email auth', () {
      final message = GoogleLoginErrorMessageFormatter.format(
        Exception('sign_in_failed 12500'),
      );

      expect(message, contains('temporarily unavailable'));
      expect(message, contains('latest Play build'));
      expect(message, isNot(contains('email login')));
    });

    test('maps user cancellation variants to a neutral message', () {
      expect(
        GoogleLoginErrorMessageFormatter.format(Exception('12501')),
        'Google login was cancelled.',
      );
      expect(
        GoogleLoginErrorMessageFormatter.format(Exception('sign_in_cancelled')),
        'Google login was cancelled.',
      );
    });

    test('maps network errors to connection guidance', () {
      final message = GoogleLoginErrorMessageFormatter.format(
        Exception('NETWORK_ERROR'),
      );

      expect(message, contains('network issue'));
      expect(message, contains('Check your connection'));
    });

    test('uses generic retry guidance for unknown errors', () {
      final message = GoogleLoginErrorMessageFormatter.format(
        Exception('unknown failure'),
      );

      expect(message, 'Google sign-in failed. Please try again.');
      expect(message, isNot(contains('email login')));
    });
  });
}
