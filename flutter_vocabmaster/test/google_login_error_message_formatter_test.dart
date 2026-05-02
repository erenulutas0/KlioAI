import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/services/google_login_error_message_formatter.dart';

void main() {
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
  });
}
