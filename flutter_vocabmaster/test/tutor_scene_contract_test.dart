import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/frontend_newest/screens/nf_tutor_page.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';
import 'package:vocabmaster/models/voice_model.dart';

/// The agreement between the scene rail and the server that plays the scene.
///
/// A scene is only ever a string. The chip sends `cafe_order`, the server
/// looks it up, and if the two ever disagree the mismatch is completely
/// silent: the learner taps "Ordering coffee", the server finds no match and
/// falls back to ordinary chat, and a friendly conversation partner asks how
/// their week has been. Nothing errors, nothing logs, and the feature is dead
/// in a way only a person can notice.
///
/// That is not hypothetical. These prompts sat on the server for months while
/// the only screen that sent a scenario had been cut out of the app -- working
/// code that nothing reached. This test is the wire between the two halves.
/// The server's half is the scenario catalog now, so that is what it reads.
void main() {
  final File catalogFile = File(
    '../backend/src/main/resources/scenarios/catalog.json',
  );

  late List<Map<String, dynamic>> serverScenes;

  setUpAll(() {
    // Loudly, not skipped. A contract test that quietly passes when it cannot
    // find the other side of the contract is worse than no test: it reports
    // agreement it never checked.
    expect(catalogFile.existsSync(), isTrue,
        reason: 'cannot find ${catalogFile.path}; this test compares the '
            'client scene list against the server catalog and has nothing to '
            'compare against');
    final Map<String, dynamic> decoded =
        jsonDecode(catalogFile.readAsStringSync()) as Map<String, dynamic>;
    serverScenes =
        (decoded['scenes'] as List<dynamic>).cast<Map<String, dynamic>>();
  });

  Map<String, dynamic>? serverScene(String id) {
    for (final Map<String, dynamic> scene in serverScenes) {
      if (scene['id'] == id) {
        return scene;
      }
    }
    return null;
  }

  final String l10n = File('lib/l10n/app_localizations.dart').readAsStringSync();

  Set<String> keysFor(String language) {
    final RegExpMatch? block = RegExp("^    '$language': \\{(.*?)^    \\},",
            multiLine: true, dotAll: true)
        .firstMatch(l10n);
    expect(block, isNotNull, reason: 'no translation block for $language');
    return RegExp(r"^\s+'([^']+)':", multiLine: true)
        .allMatches(block!.group(1)!)
        .map((RegExpMatch m) => m.group(1)!)
        .toSet();
  }

  test('the scene rail is not empty', () {
    // Every assertion below is a loop over this list, so an empty list would
    // make all of them pass.
    expect(NfScene.all.length, greaterThanOrEqualTo(6));
  });

  test('every scene the app offers is a scene the server can play', () {
    final List<String> missing = <String>[
      for (final NfScene scene in NfScene.all)
        if (serverScene(scene.id) == null) scene.id,
    ];
    expect(missing, isEmpty,
        reason: 'these ids reach the server and match no scene, so they '
            'silently become ordinary chat: ${missing.join(', ')}');
  });

  test('the header names the character the server is told to be', () {
    // The screen shows scene.character while the model is told who it is by the
    // server catalog. If those drift, the header says Emma and the voice
    // introduces itself as someone else -- and the learner concludes the app
    // does not know what it is doing.
    final List<String> wrong = <String>[];
    for (final NfScene scene in NfScene.all) {
      final Object? character = serverScene(scene.id)?['character'];
      if (character != scene.character) {
        wrong.add('${scene.id}: app says ${scene.character}, server $character');
      }
    }
    expect(wrong, isEmpty,
        reason: 'the server plays a different character: ${wrong.join(', ')}');
  });

  test('a built-in scene speaks in the voice the catalog gives it', () {
    // Offline the rail falls back to these; the character must not change
    // voice depending on whether the catalog happened to load.
    final List<String> wrong = <String>[
      for (final NfScene scene in NfScene.all)
        if (scene.voice != serverScene(scene.id)?['voice'])
          '${scene.id}: app ${scene.voice}, server ${serverScene(scene.id)?['voice']}',
    ];
    expect(wrong, isEmpty, reason: wrong.join(', '));
  });

  test('every character speaks in a voice the app can play', () {
    final Set<String> voices =
        VoiceModel.availableVoices.map((VoiceModel v) => v.piperVoice).toSet();
    final List<String> wrong = <String>[
      for (final Map<String, dynamic> scene in serverScenes)
        if (!voices.contains(scene['voice'])) '${scene['id']}: ${scene['voice']}',
    ];
    expect(wrong, isEmpty,
        reason: 'the app has no voice by these names and would fall back to '
            "the tutor's: ${wrong.join(', ')}");
  });

  test('every scene has a name in every language', () {
    // The rail builds its key as `tutor.scene.$id`, which is interpolated -- so
    // the coverage test that walks `context.tr('literal')` calls cannot see any
    // of these. Without this, a new scene ships with a chip labelled
    // "tutor.scene.hotel_checkin".
    final List<String> missing = <String>[];
    for (final Locale locale in AppLocalizations.supportedLocales) {
      final Set<String> keys = keysFor(locale.languageCode);
      for (final String key in <String>[
        'tutor.scene.free',
        ...NfScene.all.map((NfScene s) => 'tutor.scene.${s.id}'),
      ]) {
        if (!keys.contains(key)) {
          missing.add('${locale.languageCode}: $key');
        }
      }
    }
    expect(missing, isEmpty,
        reason: 'these would render as their own key on a chip: '
            '${missing.join(', ')}');
  });

  test('every kind of scene in the catalog has a name in every language', () {
    // Interpolated as `tutor.scene.cat.$kind`, like the scene names above.
    final Set<String> kinds = <String>{
      for (final Map<String, dynamic> scene in serverScenes)
        scene['category'] as String,
    };
    final List<String> missing = <String>[
      for (final Locale locale in AppLocalizations.supportedLocales)
        for (final String kind in kinds)
          if (!keysFor(locale.languageCode).contains('tutor.scene.cat.$kind'))
            '${locale.languageCode}: tutor.scene.cat.$kind',
    ];
    expect(missing, isEmpty,
        reason: 'the picker would head these with their bare id: '
            '${missing.join(', ')}');
  });

  test('no scene opens on silence', () {
    // The opening line is what makes a scene start rather than sit there. It is
    // written in the client so that choosing a scene costs nothing from the
    // daily AI quota, which also means nothing on the server would notice it
    // missing.
    for (final NfScene scene in NfScene.all) {
      expect(scene.opening.trim(), isNotEmpty, reason: scene.id);
      expect(scene.opening.length, greaterThan(15), reason: scene.id);
    }
  });

  test('scene ids are unique', () {
    final Set<String> ids = NfScene.all.map((NfScene s) => s.id).toSet();
    expect(ids.length, NfScene.all.length);
  });
}
