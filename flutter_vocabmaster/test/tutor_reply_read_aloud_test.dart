import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/frontend_newest/screens/nf_tutor_page.dart';

/// The tutor answers out loud, without being asked twice.
///
/// Timed on the server, five spoken turns: Whisper, the tutor and Piper came
/// to about 1.1 seconds together. Then the phone waited 2.5 to 12 seconds
/// before asking for the audio, because nothing asked until the learner
/// pressed play -- twelve on the turns with a correction card, which they read
/// first. That wait was the tutor, not the server.
///
/// So a reply is read as soon as it arrives. What these pin is when it is not:
/// each case is a way a voice starting on its own would be wrong.
void main() {
  bool reads({
    bool serverVoice = true,
    bool visible = true,
    bool recording = false,
    AppLifecycleState? lifecycle = AppLifecycleState.resumed,
  }) =>
      nfReadsReplyAloud(
        serverVoice: serverVoice,
        visible: visible,
        recording: recording,
        lifecycle: lifecycle,
      );

  test('a reply is read aloud the moment it arrives', () {
    expect(reads(), isTrue);
  });

  test('only in the tutor\'s own voice', () {
    // The device fallback is the robotic voice the persona exists to replace.
    // Starting it unasked would be the app talking, not the tutor; a tap on
    // the bubble still gets it.
    expect(reads(serverVoice: false), isFalse);
  });

  test('never from a tab the learner has left', () {
    // The shell keeps every tab alive, so a reply can land after they moved on.
    expect(reads(visible: false), isFalse);
  });

  test('never over the learner\'s own recording', () {
    expect(reads(recording: true), isFalse);
  });

  test('never from the background', () {
    for (final AppLifecycleState state in <AppLifecycleState>[
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ]) {
      expect(reads(lifecycle: state), isFalse, reason: '$state');
    }
  });

  test('an app that has not reported its state yet is in front', () {
    // Early in a launch the binding has no state to report. The learner is
    // talking to the app, so that is where it is.
    expect(reads(lifecycle: null), isTrue);
  });
}
