import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/utils/cloze.dart';

/// Building a fill-in-the-blank prompt out of a saved sentence.
///
/// Everything that can go wrong here goes wrong quietly. A blank in the wrong
/// place, or the answer still sitting somewhere else in the line, turns a
/// recall exercise into a reading exercise — and the card still looks perfectly
/// fine. So the tests are mostly about refusing.
void main() {
  test('the word is replaced by a gap', () {
    expect(
      Cloze.build('They lived underneath a fir-tree.', 'underneath')?.blanked,
      'They lived _____ a fir-tree.',
    );
  });

  test('a word the sentence does not contain produces no card at all', () {
    // Words saved by hand often carry an example that does not use them. A
    // sentence with nothing blanked out asks the learner to recall something
    // it never took away, which is not a question.
    expect(Cloze.build('The garden was locked.', 'underneath'), isNull);
  });

  test('every occurrence goes, not just the first', () {
    // Leaving the second one visible hands over the answer. This is the
    // failure that looks most like success: there is a blank, the card renders,
    // and the exercise is gone.
    expect(
      Cloze.build('Run along, and run fast.', 'run')?.blanked,
      '_____ along, and _____ fast.',
    );
  });

  test('punctuation attached to the word survives', () {
    // Blanking "gate!" to "_____" would quietly delete the exclamation mark the
    // sentence was written with.
    expect(
      Cloze.build('He squeezed under the gate!', 'gate')?.blanked,
      'He squeezed under the _____!',
    );
  });

  test('case does not hide the word', () {
    expect(
      Cloze.build('Underneath the root it was dark.', 'underneath')?.blanked,
      '_____ the root it was dark.',
    );
  });

  test('a close inflection is still the word', () {
    // The same rule the dictionary highlight uses: delay/delayed yes, a/delay
    // no. A learner asked for "delay" who is shown "delayed" in the line has
    // been given the answer.
    expect(
      Cloze.build('The train was delayed again.', 'delay')?.blanked,
      'The train was _____ again.',
    );
  });

  test('a short word does not blank half the sentence', () {
    // "a" must not match "along", "and", "at". The prefix rule has a floor for
    // exactly this, and it is worth pinning: without it the most common words
    // in English blank everything around them.
    expect(Cloze.build('A rabbit ran along and ate.', 'a')?.blanked,
        '_____ rabbit ran along and ate.');
  });

  test('an empty word or sentence is refused rather than guessed at', () {
    expect(Cloze.build('Some sentence here.', ''), isNull);
    expect(Cloze.build('   ', 'word'), isNull);
  });

  test('the answer comes back with the sentence it belongs in', () {
    // Revealing used to swap the whole sentence for the bare word, which puts
    // the answer somewhere the reader is not looking. The gap is where their
    // eye is, so the filled line comes back with the word marked in place.
    final ClozePrompt? prompt =
        Cloze.build('They lived underneath a fir-tree.', 'underneath');

    expect(prompt, isNotNull);
    expect(prompt!.filled, 'They lived underneath a fir-tree.');
    expect(prompt.answers, hasLength(1));
    expect(
      prompt.filled.substring(
          prompt.answers.single.start, prompt.answers.single.end),
      'underneath',
    );
  });

  test('a sentence using the word twice marks both places', () {
    final ClozePrompt prompt =
        Cloze.build('Run along, and run fast.', 'run')!;

    expect(prompt.filled, 'Run along, and run fast.');
    expect(
      prompt.answers
          .map((r) => prompt.filled.substring(r.start, r.end))
          .toList(),
      <String>['Run', 'run'],
    );
  });
}
