import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/models/word.dart';

/// Where a word came from is stored inside the word's meaning.
///
/// Adding a word from Daily Words prefixes its translation with a star, so one field
/// carries both the translation and its provenance. Every screen that shows a meaning then
/// has to know to strip it, and they did not agree: the review card — the screen a learner
/// sees most — printed it raw, so a word added from Daily Words read "⭐ içgörü". The words
/// list tried to strip it and stripped question marks instead, the emoji in that source line
/// having been mangled to '?' at some point. Practice and Word Galaxy each rolled their own.
///
/// The model now answers both questions, so no screen has to remember the rule.
Word wordWithMeaning(String meaning) => Word(
      id: 1,
      englishWord: 'insight',
      turkishMeaning: meaning,
      learnedDate: DateTime(2026, 8, 9),
      difficulty: 'easy',
    );

void main() {
  test('the marker never reaches the screen', () {
    expect(wordWithMeaning('⭐ içgörü').displayMeaning, 'içgörü');
    expect(wordWithMeaning('★ içgörü').displayMeaning, 'içgörü');
    expect(wordWithMeaning('⭐içgörü').displayMeaning, 'içgörü');
  });

  test('provenance is readable without parsing the meaning at the call site', () {
    expect(wordWithMeaning('⭐ içgörü').isFromDailyWords, isTrue);
    expect(wordWithMeaning('★ içgörü').isFromDailyWords, isTrue);
    expect(wordWithMeaning('içgörü').isFromDailyWords, isFalse);
  });

  test('a hand-typed meaning is passed through untouched', () {
    // Turkish text is full of characters a careless strip would eat. words_page was
    // deleting '?' from every meaning because of exactly that kind of accident.
    expect(wordWithMeaning('ayrıntılı bir şekilde açıklamak').displayMeaning,
        'ayrıntılı bir şekilde açıklamak');
    expect(wordWithMeaning('değerlendirmek').displayMeaning, 'değerlendirmek');
    expect(wordWithMeaning('ne? neden?').displayMeaning, 'ne? neden?');
  });
}
