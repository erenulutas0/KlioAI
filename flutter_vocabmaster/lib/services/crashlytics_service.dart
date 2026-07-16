import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Thin, enable-gated wrapper around Firebase Crashlytics.
///
/// Mirrors [AnalyticsService]'s static, try/catch-safe pattern: every call is
/// a no-op until [setEnabled] is called (see `_initializeFirebaseTelemetry`
/// in `main.dart`), and a failure inside Crashlytics itself is swallowed and
/// logged instead of crashing the app that is trying to report a crash.
///
/// [recorder] is swapped for a fake in tests so the enable-gating and
/// failure-swallowing logic can be verified without touching the real
/// Firebase SDK (which needs platform channels unavailable in unit tests).
class CrashlyticsService {
  CrashlyticsService._();

  static bool _enabled = false;

  @visibleForTesting
  static CrashlyticsRecorder recorder = _FirebaseCrashlyticsRecorder();

  static void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  static bool get isEnabled => _enabled;

  /// For `FlutterError.onError`.
  static void recordFlutterFatalError(FlutterErrorDetails details) {
    if (!_enabled) return;
    try {
      recorder.recordFlutterFatalError(details);
    } catch (e) {
      debugPrint('Crashlytics recordFlutterFatalError failed: $e');
    }
  }

  /// For `PlatformDispatcher.instance.onError` and manually caught errors
  /// outside the Flutter framework's own error zone.
  static Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
    String? reason,
  }) async {
    if (!_enabled) return;
    try {
      await recorder.recordError(error, stack, fatal: fatal, reason: reason);
    } catch (e) {
      debugPrint('Crashlytics recordError failed: $e');
    }
  }

  /// Attaches the app's user id to subsequent crash reports so a crash can
  /// be correlated with entitlement/support data. Pass null/empty to clear.
  static Future<void> setUserId(String? userId) async {
    if (!_enabled) return;
    try {
      await recorder.setUserIdentifier(userId ?? '');
    } catch (e) {
      debugPrint('Crashlytics setUserId failed: $e');
    }
  }

  /// Short breadcrumb log attached to the next crash report.
  static Future<void> log(String message) async {
    if (!_enabled) return;
    try {
      await recorder.log(message);
    } catch (e) {
      debugPrint('Crashlytics log failed: $e');
    }
  }
}

@visibleForTesting
abstract class CrashlyticsRecorder {
  void recordFlutterFatalError(FlutterErrorDetails details);

  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
    String? reason,
  });

  Future<void> setUserIdentifier(String identifier);

  Future<void> log(String message);
}

class _FirebaseCrashlyticsRecorder implements CrashlyticsRecorder {
  @override
  void recordFlutterFatalError(FlutterErrorDetails details) {
    FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
    String? reason,
  }) {
    return FirebaseCrashlytics.instance
        .recordError(error, stack, fatal: fatal, reason: reason);
  }

  @override
  Future<void> setUserIdentifier(String identifier) {
    return FirebaseCrashlytics.instance.setUserIdentifier(identifier);
  }

  @override
  Future<void> log(String message) {
    return FirebaseCrashlytics.instance.log(message);
  }
}
