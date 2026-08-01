import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/models/word.dart';
import 'package:vocabmaster/screens/translation_practice_page.dart';

/// A checked translation is now fed to the review scheduler, which means the round has to
/// know which word each sentence was actually drilling.
///
/// Index alignment was the tempting shortcut — five words, five sentences — but if the
/// model reorders, skips or merges a target the wrong word gets graded, and a wrong SRS
/// grade is worse than none: it reschedules a word the learner never saw.

Word _word(int id, String english) => Word(
      id: id,
      englishWord: english,
      turkishMeaning: 'anlam-$id',
      learnedDate: DateTime(2026, 8, 1),
      difficulty: 'medium',
    );

void main() {
  final recover = _word(1, 'recover');
  final symptom = _word(2, 'symptom');
  final delay = _word(3, 'delay');
  final round = [recover, symptom, delay];

  test('the word the sentence actually contains is the one credited', () {
    expect(
      wordDrilledBySentence('She noticed a new symptom after the flu.', round)?.id,
      symptom.id,
    );
    expect(
      wordDrilledBySentence('The delay pushed our meeting to Friday.', round)?.id,
      delay.id,
    );
  });

  test('position in the round does not decide the credit', () {
    // The failure this guards against: crediting by index would have graded "recover"
    // here, because it is first in the list.
    final sentence = 'A short delay gave us time for coffee.';
    expect(wordDrilledBySentence(sentence, round)?.id, delay.id);
    expect(wordDrilledBySentence(sentence, round)?.id, isNot(recover.id));
  });

  test('an inflected form still credits its word', () {
    expect(
      wordDrilledBySentence('He recovered quickly after a few days.', round)?.id,
      recover.id,
    );
    expect(
      wordDrilledBySentence('Two symptoms appeared overnight.', round)?.id,
      symptom.id,
    );
  });

  test('a short word does not match inside a longer one', () {
    final cat = _word(9, 'cat');
    expect(
      wordDrilledBySentence('Concatenate the two lists.', [cat, delay]),
      isNull,
      reason: '"cat" inside "Concatenate" must not schedule the word cat',
    );
  });

  test('matching ignores case', () {
    expect(
      wordDrilledBySentence('Recovered items go back on the shelf.', round)?.id,
      recover.id,
    );
  });

  test('a multi-word round with no match credits nothing', () {
    // Guessing would grade a word the learner did not practise.
    expect(
      wordDrilledBySentence('The weather turned cold this evening.', round),
      isNull,
    );
  });

  test('a single-word round is unambiguous even without a textual match', () {
    // The model sometimes drops the target from the sentence. With one candidate there is
    // still only one thing the learner was practising.
    expect(
      wordDrilledBySentence('The weather turned cold this evening.', [delay])?.id,
      delay.id,
    );
  });

  test('an empty round credits nothing', () {
    expect(wordDrilledBySentence('Anything at all.', const []), isNull);
  });
}
