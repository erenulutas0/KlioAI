import 'network_failure.dart';

/// Turns a Google sign-in failure into something a screen can act on.
///
/// Two outputs, for two audiences. [codeFor] returns a short stable code —
/// `offline`, `cancelled`, `config` — that the shipping landing page maps to a
/// sentence in the learner's own language. [format] returns an English
/// sentence directly and exists for the retired screens under `lib/screens/`,
/// which show whatever string they are handed; it is kept so they keep
/// compiling, not because anything new should call it.
///
/// The split is the fix for the failure that shipped: every Google error
/// reached the learner as an English paragraph — a Spanish or Portuguese user
/// who tapped the only button on the only screen got "Google login
/// configuration issue detected. Play test builds usually fail like this…" —
/// and a cancelled sheet got Turkish, from a different file. Nothing else in
/// the app switches language when something goes wrong; the sign-in screen
/// was the one place that did, and it is the first screen anyone sees.
class GoogleLoginErrorMessageFormatter {
  /// A stable code for [error], or `unknown`.
  ///
  /// Matched on the exception's text because the sign-in plugin surfaces
  /// platform failures as `PlatformException` with numeric codes in the
  /// message (10 for a signing-certificate mismatch, 12500 for a Play
  /// Services problem, 12501 for the sheet being dismissed) and because a
  /// dropped connection arrives as a `SocketException` two layers down, which
  /// this file cannot name without importing dart:io.
  static String codeFor(Object error) {
    final String normalized = error.toString().toLowerCase();

    // Shared with AiErrorMessageFormatter, so the two cannot drift apart on
    // what counts as being offline.
    if (looksOffline(error)) {
      return 'offline';
    }

    if (normalized.contains('apiexception: 10') ||
        normalized.contains('developer_error')) {
      return 'config';
    }

    if (normalized.contains('12500')) {
      return 'unavailable';
    }

    if (normalized.contains('12501') ||
        normalized.contains('sign_in_canceled') ||
        normalized.contains('sign_in_cancelled') ||
        normalized.contains('canceled') ||
        normalized.contains('cancelled')) {
      return 'cancelled';
    }

    if (normalized.contains('network_error') ||
        normalized.contains('network error') ||
        looksTimedOut(error)) {
      return 'network';
    }

    return 'unknown';
  }

  /// An English sentence for [error]. Retired screens only — see the class
  /// comment. The shipping landing page localises [codeFor] instead.
  static String format(Object error) {
    switch (codeFor(error)) {
      case 'offline':
        return 'You appear to be offline. Check your connection and try again.';
      case 'config':
        return 'Google login configuration issue detected. '
            'Play test builds usually fail like this when the app signing SHA is not registered yet. '
            'Please install the latest Play build or contact support if it continues.';
      case 'unavailable':
        return 'Google login is temporarily unavailable on this build. '
            'Please try again later or update to the latest Play build.';
      case 'cancelled':
        return 'Google login was cancelled.';
      case 'network':
        return 'Google login failed because of a network issue. '
            'Check your connection and try again.';
      default:
        return 'Google sign-in failed. Please try again.';
    }
  }
}
