import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Where a new install lands.
///
/// For most of this app's life the answer was "on a sign-in screen". Firebase
/// counted 235 people opening the app in a month against 40 accounts created,
/// and of 105 accounts only 11 ever opened it on a second day: the wall was at
/// the door, before the tutor had said a word. Both first-run paths now go
/// through NfGuestGate, which opens a guest account and lands in the tutor.
///
/// A test on two route builders is unusual, and this one earns it: the flow only
/// runs on a cold first launch of a fresh install, no other test covers it, and
/// putting the sign-in screen back is a one-word edit that every other test in
/// this suite would stay green through.
void main() {
  final File main = File('lib/main.dart');
  final File splash = File('lib/screens/splash_screen.dart');

  test('both files are where this test thinks they are', () {
    expect(main.existsSync(), isTrue);
    expect(splash.existsSync(), isTrue);
  });

  test('the first run after onboarding opens a conversation, not a form', () {
    final String source = main.readAsStringSync();

    expect(source, contains('NfGuestGate()'));
    expect(source.contains('NfLandingPage'), isFalse,
        reason: 'the first run reaches the sign-in screen again');
  });

  test('so does a launch with no session', () {
    final String source = splash.readAsStringSync();

    expect(source, contains('NfGuestGate()'));
    expect(source.contains('NfLandingPage('), isFalse,
        reason: 'a returning install with no session is asked to sign in '
            'before it is allowed to speak');
  });

  test('the gate falls back to signing in when the server cannot be reached', () {
    // The guest account comes from the server. Without this fallback a learner
    // on a dead connection would meet a spinner instead of the screen they used
    // to get, which is worse than the wall we are removing.
    final String gate =
        File('lib/frontend_newest/screens/nf_guest_gate.dart').readAsStringSync();

    expect(gate, contains('NfLandingPage()'));
    expect(gate, contains('startGuestSession'));
  });
}
