import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Play refuses an upload that targets an API level below its current floor,
/// and it says so at upload time — after the build, after the version code is
/// spent, and only in the Console. Version 444 was built, uploaded and
/// rejected with "your app currently targets API level 35, but must target at
/// least 36".
///
/// The floor rises every year, so this test is not the answer to it. What it
/// does is make the number visible from the test suite instead of only from a
/// Gradle file nobody reads between releases, and fail with the reason rather
/// than the symptom.
///
/// The behaviour change to watch when raising it is edge-to-edge, which
/// Android 16 stops letting apps opt out of. This app never opted in to the
/// opt-out — there is no `windowOptOutEdgeToEdgeEnforcement` anywhere — so it
/// has been drawing under the system bars since it targeted 35, and the second
/// test below is what keeps that true.
void main() {
  /// The Gradle file with `//` comments removed, so a number written in prose
  /// cannot be read as a setting. The comment beside targetSdk explains the
  /// rejection and contains "35".
  String gradleWithoutComments() {
    final File file = File('android/app/build.gradle');
    expect(file.existsSync(), isTrue,
        reason: 'run this from the flutter_vocabmaster directory');
    return file
        .readAsLinesSync()
        .map((String line) {
          final int at = line.indexOf('//');
          return at < 0 ? line : line.substring(0, at);
        })
        .join('\n');
  }

  int settingOf(String name) {
    final RegExpMatch? match =
        RegExp('$name\\s*=\\s*([0-9]+)').firstMatch(gradleWithoutComments());
    expect(match, isNotNull, reason: '$name is not set in android/app/build.gradle');
    return int.parse(match!.group(1)!);
  }

  test('the app targets the API level Play requires', () {
    // Raised from 35 on 2 September 2026, after Play rejected version 444.
    const int playFloor = 36;
    final int target = settingOf('targetSdk');

    expect(target, greaterThanOrEqualTo(playFloor),
        reason: 'targetSdk is $target and Play will not accept an upload below '
            '$playFloor. It fails at upload, not at build, so nothing else in '
            'this repository would have told you.');
  });

  test('compileSdk is not behind targetSdk', () {
    // Targeting an API you did not compile against is legal and a bad idea:
    // the platform applies the new behaviour while the code was checked
    // against the old surface.
    expect(settingOf('compileSdk'), greaterThanOrEqualTo(settingOf('targetSdk')),
        reason: 'compileSdk is behind targetSdk');
  });

  test('nothing opts out of edge-to-edge enforcement', () {
    // Android 16 ignores this flag for apps targeting 36, so adding it would
    // be a screen drawn under the status bar in the belief that it is not.
    // The reason raising targetSdk was safe here is that it was never present.
    final List<String> offenders = <String>[];
    for (final String path in <String>[
      'android/app/src/main/AndroidManifest.xml',
      'android/app/src/main/res/values/styles.xml',
      'android/app/src/main/res/values-night/styles.xml',
    ]) {
      final File file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path is missing');
      if (file.readAsStringSync().contains('OptOutEdgeToEdgeEnforcement')) {
        offenders.add(path);
      }
    }

    expect(offenders, isEmpty,
        reason: 'These opt out of edge-to-edge, which Android 16 ignores for '
            'an app targeting 36:\n${offenders.join('\n')}');
  });
}
