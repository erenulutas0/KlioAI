import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/utils/word_family.dart';

/// The cases that decide whether a mark on the page is right or wrong.
///
/// Every "matches" case is a word a learner could plausibly have saved beside a
/// form a book could plausibly print. Every "does not match" case is a pair
/// that looks related to a naive prefix rule and is not — those are the ones
/// that put a wrong mark in front of someone learning the language.
void main() {
  group('regular inflections reach the word that was saved', () {
    const Map<String, String> pairs = <String, String>{
      'flights': 'flight',
      'watches': 'watch',
      'studies': 'study',
      'tried': 'try',
      'used': 'use',
      'liked': 'like',
      'stopped': 'stop',
      'running': 'run',
      'making': 'make',
      'writing': 'write',
      'walked': 'walk',
      'reading': 'read',
    };

    pairs.forEach((String surface, String saved) {
      test('$surface -> $saved', () {
        expect(WordFamily.matches(surface, saved), isTrue);
      });
    });
  });

  group('a word is always a form of itself', () {
    for (final String word in <String>['flight', 'class', 'sing', 'is']) {
      test(word, () {
        expect(WordFamily.matches(word, word), isTrue);
      });
    }
  });

  group('unrelated words are left alone', () {
    const Map<String, String> pairs = <String, String>{
      // The ending is most of the word: a floor, not a stem.
      'sing': 's',
      'ties': 't',
      'bed': 'b',
      // Not a plural, however much it looks like one.
      'class': 'clas',
      'miss': 'mis',
      // Shares a prefix and nothing else. A prefix rule would say yes.
      'delay': 'del',
      'flight': 'fly',
      'reader': 'read',
    };

    pairs.forEach((String surface, String saved) {
      test('$surface is not a form of $saved', () {
        expect(WordFamily.matches(surface, saved), isFalse);
      });
    });
  });

  test('case and surrounding space do not matter', () {
    expect(WordFamily.matches('Flights', ' flight '), isTrue);
    expect(WordFamily.matches('  RUNNING', 'Run'), isTrue);
  });

  test('an empty word matches nothing, including itself', () {
    expect(WordFamily.matches('', ''), isFalse);
    expect(WordFamily.matches('flight', ''), isFalse);
    expect(WordFamily.baseForms(''), isEmpty);
  });
}
