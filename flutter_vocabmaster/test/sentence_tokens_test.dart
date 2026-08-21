import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/utils/sentence_tokens.dart';

/// The quick dictionary's example sentence is its primary content: every word is tappable
/// and the searched one is highlighted. All three of these were wrong on screen.
void main() {
  group('split', () {
    test('keeps the spaces between words', () {
      // `split(RegExp(r'(\s+)'))` is a JavaScript idiom - Dart does not re-insert captured
      // separators - so every example sentence rendered as "Shehasabeautiful voice."
      expect(SentenceTokens.split('She has a voice.'),
          equals(['She', ' ', 'has', ' ', 'a', ' ', 'voice.']));
    });

    test('rejoins to exactly the original sentence', () {
      const sentence = 'The  flight was  delayed by rain.';
      expect(SentenceTokens.split(sentence).join(), equals(sentence));
    });

    test('an empty sentence produces no tokens', () {
      expect(SentenceTokens.split(''), isEmpty);
    });
  });

  group('word', () {
    test('strips punctuation from the ends', () {
      expect(SentenceTokens.word('voice.'), equals('voice'));
      expect(SentenceTokens.word('"Hello,"'), equals('hello'));
    });

    test('keeps apostrophes and hyphens inside the word', () {
      // Stripping these turned "It's" into "its" and "well-known" into "wellknown". The
      // backend was then asked to explain a word the sentence does not contain, and the
      // dialog was titled with the mangled form.
      expect(SentenceTokens.word("It's"), equals("it's"));
      expect(SentenceTokens.word('well-known'), equals('well-known'));
      expect(SentenceTokens.word("John's."), equals("john's"));
    });
  });

  group('isSearched', () {
    test('matches the word itself and its ordinary inflections', () {
      expect(SentenceTokens.isSearched('delay', 'delay'), isTrue);
      expect(SentenceTokens.isSearched('delayed', 'delay'), isTrue);
      expect(SentenceTokens.isSearched('delaying', 'delay'), isTrue);
    });

    test('does not paint short function words', () {
      // Two substring checks meant searching "delay" highlighted every "a" in the sentence -
      // and highlighted tokens are not tappable, so the words a learner is most likely to
      // want defined were the ones they could not tap.
      expect(SentenceTokens.isSearched('a', 'delay'), isFalse);
      expect(SentenceTokens.isSearched('the', 'delay'), isFalse);
      expect(SentenceTokens.isSearched('by', 'delay'), isFalse);
    });

    test('does not match an unrelated longer word that merely contains it', () {
      expect(SentenceTokens.isSearched('resilience', 'resilient'), isFalse);
      expect(SentenceTokens.isSearched('understanding', 'stand'), isFalse);
    });

    test('an empty token is never the searched word', () {
      expect(SentenceTokens.isSearched('', 'delay'), isFalse);
      expect(SentenceTokens.isSearched('delay', ''), isFalse);
    });
  });
}
