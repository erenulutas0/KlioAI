import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/models/word.dart';
import 'package:vocabmaster/services/local_database_service.dart';
import 'package:vocabmaster/services/offline_sync_service.dart';

import '../test_helper.dart';

/// The local cache had no idea which language a word belonged to, which is
/// fine while there is one language and wrong the moment there are two: every
/// screen reads its deck from here, so a German profile would have shown the
/// English words and back again.
///
/// These pin the two halves of that: words are scoped to their profile, and an
/// upgrading learner — whose rows predate the column and are therefore NULL —
/// does not watch their whole deck disappear.
void main() {
  setUpAll(setupTestEnv);

  late LocalDatabaseService db;

  setUp(() async {
    await clearDatabase();
    db = LocalDatabaseService();
  });

  Word word(int id, String english, {int? profile}) => Word(
        id: id,
        englishWord: english,
        turkishMeaning: '$english-tr',
        learnedDate: DateTime(2026, 1, 1),
        difficulty: 'easy',
        languageProfileId: profile,
      );

  test('a profile sees its own words and not the other language', () async {
    await db.saveWord(word(1, 'insight', profile: 10));
    await db.saveWord(word(2, 'einsicht', profile: 20));

    final english = await db.getAllWords(languageProfileId: 10);
    final german = await db.getAllWords(languageProfileId: 20);

    expect(english.map((Word w) => w.englishWord), <String>['insight']);
    expect(german.map((Word w) => w.englishWord), <String>['einsicht']);
  });

  test('asking for no profile still returns everything', () async {
    await db.saveWord(word(1, 'insight', profile: 10));
    await db.saveWord(word(2, 'einsicht', profile: 20));

    expect((await db.getAllWords()).length, 2);
  });

  test('rows written before the column existed belong to whoever asks',
      () async {
    // What an upgrading install has: real words, no profile stamped on them.
    // Excluding these would empty a learner's deck until a sync completed,
    // which is indistinguishable from losing it.
    await db.saveWord(word(1, 'legacy'));

    expect(
      (await db.getAllWords(languageProfileId: 10))
          .map((Word w) => w.englishWord),
      <String>['legacy'],
    );
  });

  test('the profile survives a round trip through the cache', () async {
    // If the read dropped it, the next save would write NULL back and the stamp
    // would be undone on every refresh.
    await db.saveWord(word(1, 'insight', profile: 10));

    final Word fromCache = (await db.getAllWords()).single;
    expect(fromCache.languageProfileId, 10);

    await db.saveWord(fromCache);
    expect((await db.getAllWords(languageProfileId: 10)).length, 1);
    expect((await db.getAllWords(languageProfileId: 20)), isEmpty);
  });
  group('the bulk sync path', () {
    // Every existing test above uses saveWord. The path production actually
    // takes on almost every app open is saveAllWords, and it was silently
    // undoing them: its insert map omitted languageProfileId while passing
    // ConflictAlgorithm.replace, so INSERT OR REPLACE deleted each row and
    // wrote a fresh one with the column back at its default of NULL.
    //
    // The filter above could never have matched a thing, and the four tests
    // that "covered" it would have gone on passing for as long as anyone
    // cared to look.

    test('a synced word keeps the profile it was saved with', () async {
      await db.saveAllWords(<Word>[word(1, 'insight', profile: 10)]);

      final scoped = await db.getAllWords(languageProfileId: 10);
      expect(scoped.single.englishWord, 'insight');
      expect(scoped.single.languageProfileId, 10);
    });

    test('a sync over an already-stamped word does not launder the stamp',
        () async {
      // The real sequence: a word is saved, then the background sync writes
      // the server's copy of it over the top. This is the one that failed.
      await db.saveWord(word(1, 'insight', profile: 10));
      await db.saveAllWords(<Word>[word(1, 'insight', profile: 10)]);

      final all = await db.getAllWords();
      expect(all.single.languageProfileId, 10);
      expect(await db.getAllWords(languageProfileId: 20), isEmpty);
    });

    test('a synced deck stays split by profile', () async {
      await db.saveAllWords(<Word>[
        word(1, 'insight', profile: 10),
        word(2, 'einsicht', profile: 20),
      ]);

      expect((await db.getAllWords(languageProfileId: 10)).single.englishWord,
          'insight');
      expect((await db.getAllWords(languageProfileId: 20)).single.englishWord,
          'einsicht');
      expect(await db.getAllWords(), hasLength(2));
    });

    test('an unstamped word belongs to every profile', () async {
      // The escape hatch the live install depends on: rows that predate the
      // column are NULL, and they must keep showing up under any profile. If
      // someone ever tightens that WHERE clause to a plain equality, this is
      // the test that should stop them.
      await db.saveAllWords(<Word>[word(1, 'insight')]);

      expect(await db.getAllWords(languageProfileId: 10), hasLength(1));
      expect(await db.getAllWords(languageProfileId: 99), hasLength(1));
      expect(await db.getAllWords(), hasLength(1));
    });
  });

  group('the sync service passes it through', () {
    // One layer up, because the parameter existing is not the same as anything
    // handing it an id — which is exactly the state this whole change found:
    // a filter written, tested, and reachable by nobody.
    //
    // Driven at this level rather than through AppStateProvider, because
    // OfflineSyncService._syncWordsInBackground returns immediately under
    // FLUTTER_TEST. A test that went through the provider would never touch
    // the sync path at all and would pass whatever the code did.

    test('a profile gets its own deck, and no id gets all of it', () async {
      final OfflineSyncService sync = OfflineSyncService();
      await db.saveAllWords(<Word>[
        word(1, 'insight', profile: 10),
        word(2, 'einsicht', profile: 20),
      ]);

      expect((await sync.getLocalWords(languageProfileId: 10)).single.englishWord,
          'insight');
      expect(await sync.getLocalWords(), hasLength(2));
    });

    test('a learner whose profile has not loaded still sees everything',
        () async {
      // The cold-start case, and the one the live install takes: profiles
      // arrive over the network after the deck is first read, so the id is
      // null and every word has to come back.
      final OfflineSyncService sync = OfflineSyncService();
      await db.saveAllWords(<Word>[word(1, 'insight', profile: 10)]);

      expect(await sync.getLocalWords(languageProfileId: null), hasLength(1));
    });
  });

}
