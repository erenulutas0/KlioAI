import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/models/word.dart';
import 'package:vocabmaster/models/word_meaning.dart';
import 'package:vocabmaster/providers/app_state_provider.dart';
import 'package:vocabmaster/services/local_database_service.dart';

import '../test_helper.dart';

/// A word created straight on the server has to be written into the local
/// cache, because that cache is what the app actually reads.
///
/// `OfflineSyncService.getAllWords` returns the local rows the moment there are
/// any and syncs behind them, so a server-only word stays invisible until some
/// later sync lands. On a real phone that meant saving "bank" with two
/// meanings, being told "Kelime bugüne eklendi!", opening the word list and
/// finding nothing there.
void main() {
  setUpAll(setupTestEnv);

  late LocalDatabaseService db;

  setUp(() async {
    await clearDatabase();
    db = LocalDatabaseService();
  });

  Word bank() => Word(
        id: 4242,
        englishWord: 'bank',
        turkishMeaning: 'banka, kıyı',
        learnedDate: DateTime(2026, 8, 24),
        difficulty: 'medium',
        meanings: const <WordMeaning>[
          WordMeaning(id: 1, translation: 'banka', position: 0),
          WordMeaning(id: 2, translation: 'kıyı', position: 1),
        ],
      );

  test('a server-created word lands in the cache the app reads', () async {
    expect(await db.getAllWords(), isEmpty);

    await AppStateProvider().adoptServerWord(bank());

    final cached = await db.getAllWords();
    expect(cached.map((Word w) => w.englishWord), <String>['bank']);
  });

  test('it also lands in the list on screen, without waiting for a sync',
      () async {
    final provider = AppStateProvider();
    expect(provider.allWords, isEmpty);

    await provider.adoptServerWord(bank());

    expect(provider.allWords.single.englishWord, 'bank');
  });

  test('adopting the same word twice does not duplicate it', () async {
    final provider = AppStateProvider();
    await provider.adoptServerWord(bank());
    await provider.adoptServerWord(bank());

    expect(provider.allWords.length, 1);
    expect((await db.getAllWords()).length, 1);
  });
}
