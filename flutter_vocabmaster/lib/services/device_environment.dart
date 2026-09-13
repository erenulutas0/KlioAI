import 'dart:io';

import 'package:flutter/services.dart';

/// Facts about the device the app is running on that the app itself cannot see.
class DeviceEnvironment {
  DeviceEnvironment._();

  static const MethodChannel _channel = MethodChannel('klioai/device');

  /// Whether this is one of Google's own test devices.
  ///
  /// Every build uploaded to a Play testing track is installed on a set of Firebase
  /// Test Lab devices for the pre-launch report, and a robot taps through every screen
  /// -- the paywall and "Sign in with Google" included -- on devices with no real
  /// account and no payment method. Crashlytics for 1.4.1 showed exactly that: the
  /// billing screen and the Google sign-in screen each crashing for the same twelve
  /// "users", on the days builds were uploaded, alongside font downloads failing on
  /// devices with restricted network. Counted as users, they put the crash-free rate at
  /// 75% and made it look as though people trying to subscribe could not.
  ///
  /// Test Lab marks its devices with a system setting. False everywhere else, and on
  /// any failure to ask: a real learner must never be mistaken for a robot.
  static Future<bool> isTestLab() async {
    if (!Platform.isAndroid) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('isTestLab') == true;
    } catch (_) {
      return false;
    }
  }
}
