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
  /// account and no payment method. Their analytics are not learners', so this turns
  /// both collectors off there.
  ///
  /// It was written for a Crashlytics report it did not explain. The billing and
  /// sign-in crashes of builds 463-483 came from OnePlus and Huawei phones on Android
  /// 11 starting those activities by name, under a second into a session: a launch
  /// that never reaches Dart, so nothing here could have run. PlayActivityLaunchGuard,
  /// on the Android side, is what handles them.
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
