/// Is this failure the network rather than the request?
///
/// Two formatters need the same answer and a third will:
/// [GoogleLoginErrorMessageFormatter] decides what the sign-in screen says,
/// and [AiErrorMessageFormatter] decides what every other screen says. Both
/// used to reach the same conclusion with their own copy of these patterns,
/// which is how the two would eventually disagree about what "offline" means.
///
/// Matched on text because the failure arrives as several unrelated types --
/// `SocketException` from dart:io, `TimeoutException` from dart:async, a
/// `PlatformException` carrying a plugin's own network code -- and the
/// alternative is importing dart:io into files that have no other reason to
/// touch it.
library;

/// True when the device could not reach the server at all.
bool looksOffline(Object error) {
  final String text = error.toString().toLowerCase();
  return text.contains('socketexception') ||
      text.contains('failed host lookup') ||
      text.contains('connection refused') ||
      text.contains('connection closed') ||
      text.contains('network is unreachable') ||
      text.contains('no address associated with hostname');
}

/// True when the server was reachable but did not answer in time.
bool looksTimedOut(Object error) {
  final String text = error.toString().toLowerCase();
  return text.contains('timeoutexception') ||
      text.contains('connection timed out') ||
      text.contains('deadline exceeded');
}
