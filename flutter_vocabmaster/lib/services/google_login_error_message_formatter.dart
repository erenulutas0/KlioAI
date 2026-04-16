class GoogleLoginErrorMessageFormatter {
  static String format(Object error) {
    final raw = error.toString();
    final normalized = raw.toLowerCase();

    if ((normalized.contains('ngrok-free.dev') ||
            normalized.contains('the endpoint') ||
            normalized.contains('unexpected non-json response')) &&
        normalized.contains('offline')) {
      return 'This build is still pointing to an old ngrok backend that is now offline. '
          'Install a fresh build that targets https://api.klioai.app and try again.';
    }

    if (normalized.contains('apiexception: 10') ||
        normalized.contains('developer_error')) {
      return 'Google login configuration issue detected. '
          'Play test builds usually fail like this when the app signing SHA is not registered yet. '
          'You can use email login for now.';
    }

    if (normalized.contains('12500')) {
      return 'Google login is temporarily unavailable on this build. '
          'Please try again later or use email login.';
    }

    if (normalized.contains('12501') ||
        normalized.contains('sign_in_canceled') ||
        normalized.contains('sign_in_cancelled') ||
        normalized.contains('canceled') ||
        normalized.contains('cancelled')) {
      return 'Google login was cancelled.';
    }

    if (normalized.contains('network_error') ||
        normalized.contains('network error')) {
      return 'Google login failed because of a network issue. '
          'Check your connection and try again.';
    }

    return 'Google sign-in failed. Please try again or use email login.';
  }
}
