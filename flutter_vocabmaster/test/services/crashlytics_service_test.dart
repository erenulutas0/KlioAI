import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/services/crashlytics_service.dart';

class _FakeCrashlyticsRecorder implements CrashlyticsRecorder {
  int recordFlutterFatalErrorCalls = 0;
  int recordErrorCalls = 0;
  int setUserIdentifierCalls = 0;
  int logCalls = 0;

  FlutterErrorDetails? lastFlutterErrorDetails;
  Object? lastError;
  StackTrace? lastStack;
  bool? lastFatal;
  String? lastReason;
  String? lastUserIdentifier;
  String? lastLogMessage;

  bool throwOnRecordError = false;

  @override
  void recordFlutterFatalError(FlutterErrorDetails details) {
    recordFlutterFatalErrorCalls++;
    lastFlutterErrorDetails = details;
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
    String? reason,
  }) async {
    recordErrorCalls++;
    lastError = error;
    lastStack = stack;
    lastFatal = fatal;
    lastReason = reason;
    if (throwOnRecordError) {
      throw StateError('boom');
    }
  }

  @override
  Future<void> setUserIdentifier(String identifier) async {
    setUserIdentifierCalls++;
    lastUserIdentifier = identifier;
  }

  @override
  Future<void> log(String message) async {
    logCalls++;
    lastLogMessage = message;
  }

  bool? lastCollectionEnabled;

  @override
  Future<void> setCollectionEnabled(bool enabled) async {
    lastCollectionEnabled = enabled;
  }
}

void main() {
  late _FakeCrashlyticsRecorder fakeRecorder;

  setUp(() {
    fakeRecorder = _FakeCrashlyticsRecorder();
    CrashlyticsService.recorder = fakeRecorder;
    CrashlyticsService.setEnabled(false);
  });

  group('a font that failed to download', () {
    // The app does not crash: text falls back to the platform font. It was reported as
    // a fatal crash anyway, for every phone that opened the app offline and every
    // pre-launch test device with a restricted network.
    final Exception fontFailure = Exception(
      'Failed to load font with url: https://fonts.gstatic.com/s/a/nunito.ttf',
    );

    test('is recorded, but not as a crash, from FlutterError.onError', () async {
      CrashlyticsService.setEnabled(true);

      CrashlyticsService.recordFlutterFatalError(
        FlutterErrorDetails(exception: fontFailure, stack: StackTrace.empty),
      );
      await Future<void>.delayed(Duration.zero);

      expect(fakeRecorder.recordFlutterFatalErrorCalls, 0);
      expect(fakeRecorder.recordErrorCalls, 1);
      expect(fakeRecorder.lastFatal, isFalse);
    });

    test('is recorded, but not as a crash, as an uncaught async error', () async {
      CrashlyticsService.setEnabled(true);

      await CrashlyticsService.recordError(fontFailure, StackTrace.empty, fatal: true);

      expect(fakeRecorder.lastFatal, isFalse);
      expect(fakeRecorder.lastReason, contains('platform font'));
    });

    test('and anything else is still a crash', () async {
      CrashlyticsService.setEnabled(true);

      CrashlyticsService.recordFlutterFatalError(
        FlutterErrorDetails(exception: StateError('a real bug')),
      );
      await CrashlyticsService.recordError(StateError('a real bug'), null, fatal: true);

      expect(fakeRecorder.recordFlutterFatalErrorCalls, 1);
      expect(fakeRecorder.lastFatal, isTrue);
    });
  });

  test('disabling collection switches the native collector off too', () async {
    // A crash inside Google's billing or sign-in activity never passes through Dart.
    CrashlyticsService.setEnabled(true);

    await CrashlyticsService.disableCollection();

    expect(fakeRecorder.lastCollectionEnabled, isFalse);
    expect(CrashlyticsService.isEnabled, isFalse);
  });

  group('when disabled (Firebase not initialized / debug run)', () {
    test('recordFlutterFatalError is a no-op', () {
      CrashlyticsService.recordFlutterFatalError(
        FlutterErrorDetails(exception: Exception('x')),
      );
      expect(fakeRecorder.recordFlutterFatalErrorCalls, 0);
    });

    test('recordError is a no-op', () async {
      await CrashlyticsService.recordError(Exception('x'), StackTrace.empty);
      expect(fakeRecorder.recordErrorCalls, 0);
    });

    test('setUserId is a no-op', () async {
      await CrashlyticsService.setUserId('42');
      expect(fakeRecorder.setUserIdentifierCalls, 0);
    });

    test('log is a no-op', () async {
      await CrashlyticsService.log('breadcrumb');
      expect(fakeRecorder.logCalls, 0);
    });
  });

  group('when enabled', () {
    setUp(() {
      CrashlyticsService.setEnabled(true);
    });

    test('isEnabled reflects the current state', () {
      expect(CrashlyticsService.isEnabled, isTrue);
      CrashlyticsService.setEnabled(false);
      expect(CrashlyticsService.isEnabled, isFalse);
    });

    test('recordFlutterFatalError forwards details to the recorder', () {
      final details = FlutterErrorDetails(exception: Exception('crash'));
      CrashlyticsService.recordFlutterFatalError(details);

      expect(fakeRecorder.recordFlutterFatalErrorCalls, 1);
      expect(fakeRecorder.lastFlutterErrorDetails, same(details));
    });

    test('recordError forwards error, stack, fatal, and reason', () async {
      final error = Exception('boom');
      final stack = StackTrace.current;
      await CrashlyticsService.recordError(error, stack,
          fatal: true, reason: 'platform-dispatcher');

      expect(fakeRecorder.recordErrorCalls, 1);
      expect(fakeRecorder.lastError, same(error));
      expect(fakeRecorder.lastStack, same(stack));
      expect(fakeRecorder.lastFatal, isTrue);
      expect(fakeRecorder.lastReason, 'platform-dispatcher');
    });

    test('recordError swallows recorder failures instead of throwing',
        () async {
      fakeRecorder.throwOnRecordError = true;

      await expectLater(
        CrashlyticsService.recordError(Exception('boom'), null),
        completes,
      );
    });

    test('setUserId forwards the identifier', () async {
      await CrashlyticsService.setUserId('42');
      expect(fakeRecorder.setUserIdentifierCalls, 1);
      expect(fakeRecorder.lastUserIdentifier, '42');
    });

    test('setUserId maps null to an empty identifier (clears user)',
        () async {
      await CrashlyticsService.setUserId(null);
      expect(fakeRecorder.lastUserIdentifier, '');
    });

    test('log forwards the breadcrumb message', () async {
      await CrashlyticsService.log('opened speaking practice');
      expect(fakeRecorder.logCalls, 1);
      expect(fakeRecorder.lastLogMessage, 'opened speaking practice');
    });
  });
}
