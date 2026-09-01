import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Google Play will not accept an upload built against an old Play Billing
/// Library, and the deadline for 8.0.0 was 31 August 2026. The app was on
/// 7.1.1 and found out from a policy notice in the Console, after the date had
/// passed — the first sign was "you will not be able to publish app updates".
///
/// Nothing in a Flutter project names the billing library. It arrives through
/// `in_app_purchase` -> `in_app_purchase_android` -> a version pinned inside
/// that package's own Gradle file, so the number Play cares about is three
/// steps from anything a person reads. This test puts the mapping somewhere it
/// will be seen, and fails if a resolution ever walks the version back.
///
///   in_app_purchase_android 0.4.x  ->  billing 7.1.1   rejected by Play
///   in_app_purchase_android 0.5.0  ->  billing 8.0.0   current floor
///
/// Confirmed against Gradle rather than assumed:
///
///   ./gradlew :app:dependencies --configuration releaseRuntimeClasspath
///   +--- com.android.billingclient:billing:8.0.0
///
/// If this fails after an upgrade, check the new package's android/build.gradle
/// for its `com.android.billingclient:billing` line before raising the floor
/// here — the point is the billing version, not the Dart one.
void main() {
  test('the resolved in_app_purchase_android still carries billing 8', () {
    final File lock = File('pubspec.lock');
    expect(lock.existsSync(), isTrue,
        reason: 'run this from the flutter_vocabmaster directory');

    final String text = lock.readAsStringSync();
    final RegExp entry = RegExp(
        r'^  in_app_purchase_android:\n(?:.*\n)*?    version: "([^"]+)"',
        multiLine: true);
    final RegExpMatch? match = entry.firstMatch(text);
    expect(match, isNotNull,
        reason: 'in_app_purchase_android is not in the lockfile at all, so '
            'either the dependency is gone or this test can no longer read it');

    final String version = match!.group(1)!;
    final List<int> parts = version
        .split(RegExp(r'[.+-]'))
        .takeWhile((String p) => int.tryParse(p) != null)
        .map(int.parse)
        .toList();
    expect(parts.length, greaterThanOrEqualTo(2),
        reason: 'could not read a version out of "$version"');

    final int major = parts[0];
    final int minor = parts[1];
    expect(major > 0 || minor >= 5, isTrue,
        reason: 'in_app_purchase_android is $version, which ships Play Billing '
            '7.1.1. Play stopped accepting uploads built against it on '
            '31 August 2026, so this would be rejected at upload rather than '
            'at build.');
  });

  test('the constraint in pubspec.yaml cannot resolve back to billing 7', () {
    // The lockfile above says what resolved today. This says what is allowed
    // to resolve tomorrow: a caret on ^0.4.0 would let `pub upgrade` walk
    // straight back down, and nothing would fail until Play refused the
    // upload.
    final String spec = File('pubspec.yaml').readAsStringSync();
    final RegExpMatch? line =
        RegExp(r'^\s+in_app_purchase:\s*\^?([0-9.]+)', multiLine: true)
            .firstMatch(spec);
    expect(line, isNotNull, reason: 'in_app_purchase is not a direct dependency');

    final List<int> parts =
        line!.group(1)!.split('.').map(int.parse).toList();
    expect(parts[0] > 3 || (parts[0] == 3 && parts[1] >= 3), isTrue,
        reason: 'the constraint is ^${line.group(1)}, and in_app_purchase '
            'below 3.3.0 depends on in_app_purchase_android ^0.4.0, which is '
            'billing 7');
  });
}
