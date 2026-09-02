import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/services/google_login_error_message_formatter.dart';

/// The sign-in screen is the first screen anyone sees, and its failures were
/// the one place in the app that switched language: every Google error was an
/// English paragraph, a cancelled sheet was Turkish from a different file, and
/// a dropped connection fell through to "Google sign-in failed" because
/// nothing recognised a SocketException.
///
/// The landing page now maps a short code to a sentence in the learner's
/// language. These pin the codes, because the strings that hang off them are
/// in seven locales and a code that stops matching is seven sentences nobody
/// sees.
void main() {
  String code(Object e) => GoogleLoginErrorMessageFormatter.codeFor(e);

  test('a dropped connection is offline, not a Google failure', () {
    expect(code("SocketException: Failed host lookup: 'api.klioai.app'"),
        'offline');
    expect(code('SocketException: Connection refused'), 'offline');
    expect(code('OS Error: Network is unreachable, errno = 101'), 'offline');
  });

  test('the dismissed sheet, in every spelling the plugin uses', () {
    expect(code('PlatformException(sign_in_canceled, ...)'), 'cancelled');
    expect(code('PlatformException(sign_in_cancelled, ...)'), 'cancelled');
    expect(code('ApiException: 12501: Sign in cancelled'), 'cancelled');
  });

  test('a signing-certificate mismatch is a configuration problem', () {
    // The one that hits a Play build whose SHA is not registered. The sentence
    // for it tells the learner to install the latest version, which is the
    // only thing they can do about it.
    expect(code('ApiException: 10: DEVELOPER_ERROR'), 'config');
    expect(code('PlatformException(sign_in_failed, ... DEVELOPER_ERROR ...)'),
        'config');
  });

  test('Play Services trouble is temporary, and says so', () {
    expect(code('ApiException: 12500: Sign in failed'), 'unavailable');
  });

  test('a plugin network error and a timeout both read as network', () {
    expect(code('PlatformException(network_error, ...)'), 'network');
    expect(code('TimeoutException after 0:00:30.000000'), 'network');
  });

  test('anything else is unknown, never a wrong specific', () {
    // A wrong diagnosis is worse than none: "you are offline" to someone who
    // is not sends them to check a router.
    expect(code('some new exception nobody has seen'), 'unknown');
    expect(code(StateError('bad state')), 'unknown');
  });

  test('every code has a sentence in the retired formatter too', () {
    // format() is what lib/screens still shows. It must not fall to the
    // generic line for a code the landing page distinguishes.
    for (final String c in <String>[
      'offline',
      'config',
      'unavailable',
      'cancelled',
      'network'
    ]) {
      final String sample = <String, String>{
        'offline': 'SocketException',
        'config': 'DEVELOPER_ERROR',
        'unavailable': '12500',
        'cancelled': '12501',
        'network': 'network_error',
      }[c]!;
      expect(GoogleLoginErrorMessageFormatter.format(sample),
          isNot('Google sign-in failed. Please try again.'),
          reason: '$c fell through to the generic sentence');
    }
  });
}
