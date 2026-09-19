import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// How the manifest hosts the activities the Play libraries add to it.
///
/// MainActivity declared `android:taskAffinity=""` from the first commit, which
/// put it in a different task from SignInHubActivity and ProxyBillingActivity,
/// whose default affinity is the applicationId. It was removed on 9 September
/// on the belief that Android was restoring that other task and rebuilding
/// those activities without the extras they were handed. Sharing the task is
/// still right, and it stays. But the belief was wrong: build 475, made after
/// the change, crashed exactly as before. A restored ProxyBillingActivity takes
/// its savedInstanceState branch and never reads the PendingIntent at all.
///
/// The crashes were both activities started by name, with an empty intent, by a
/// device farm -- OnePlus and Huawei phones, all Android 11, under a second into
/// the session. PlayActivityLaunchGuard handles that launch, and KlioApplication
/// registers it before any activity exists. It is covered against the real
/// library classes in android/app/src/test; what is checked here is that the
/// manifest still wires it up, since an application class that is not named
/// there does nothing and every test would stay green.
void main() {
  final File manifest =
      File('android/app/src/main/AndroidManifest.xml');

  test('the manifest is where the test thinks it is', () {
    expect(manifest.existsSync(), isTrue,
        reason: 'the path moved; this test is now checking nothing');
  });

  /// The manifest with its comments removed.
  ///
  /// The element carries a comment explaining why the attribute is absent, and
  /// that comment names the attribute. A plain substring search finds its own
  /// explanation and fails.
  String declarations() => manifest
      .readAsStringSync()
      .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

  test('MainActivity shares a task with the activities it starts', () {
    expect(
      declarations().contains('android:taskAffinity'),
      isFalse,
      reason: 'MainActivity must keep the default affinity - the applicationId '
          '- so that SignInHubActivity and ProxyBillingActivity are hosted in '
          'the same task instead of one Android can restore without them.',
    );
  });

  test('and is still the launcher entry, singleTop, exported', () {
    // The attributes around the one that was removed, so a future edit to this
    // element has to have meant it.
    final String xml = declarations();

    expect(xml, contains('android:name=".MainActivity"'));
    expect(xml, contains('android:launchMode="singleTop"'));
    expect(xml, contains('android:exported="true"'));
    expect(xml, contains('android.intent.category.LAUNCHER'));
  });

  test('the application class that registers the launch guard is the one in use', () {
    expect(declarations(), contains('android:name=".KlioApplication"'),
        reason: 'without it PlayActivityLaunchGuard is never registered, and a '
            'bare launch of the billing or sign-in screen crashes again');

    final File app = File(
        'android/app/src/main/kotlin/com/example/flutter_vocabmaster/KlioApplication.kt');
    expect(app.readAsStringSync(),
        contains('registerActivityLifecycleCallbacks(PlayActivityLaunchGuard)'));
  });

  test('Android does not restore this app onto a new install', () {
    // Automatic backup is on unless a manifest says otherwise, and it restores
    // the preferences and the database while leaving the encrypted store with
    // the session behind. On a reinstall the first guest account therefore
    // opened onto the previous account's word list and its conversations with
    // the tutor. Everything a learner keeps is on the server and comes back
    // when they sign in.
    final String xml = declarations();

    expect(xml, contains('android:allowBackup="false"'));
    expect(xml, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
    expect(
        File('android/app/src/main/res/xml/data_extraction_rules.xml').existsSync(),
        isTrue,
        reason: 'the manifest points at rules that are not there, so the build '
            'fails -- or worse, a later edit removes the pointer instead');
  });

  test('the empty answer the billing screen is given is declared, and private', () {
    final RegExpMatch? element = RegExp(
      r'<activity[^>]*android:name="\.EmptyLaunchActivity"[^>]*>',
      dotAll: true,
    ).firstMatch(declarations());

    expect(element, isNotNull,
        reason: 'an activity missing from the manifest cannot be started, so the '
            'billing screen would crash on the PendingIntent it was given instead');
    expect(element!.group(0), contains('android:exported="false"'));
  });
}
