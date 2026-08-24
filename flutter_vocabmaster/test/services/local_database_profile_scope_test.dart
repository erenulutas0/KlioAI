import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/models/word.dart';
import 'package:vocabmaster/services/local_database_service.dart';

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
}
