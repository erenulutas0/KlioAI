import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/models/tutor_correction.dart';

/// A correction is drawn struck through, under "Say it like this", attached to
/// the learner's own turn. Nothing verified that it was about that turn.
///
/// The prompt asks the model to correct only what the learner said and never
/// to invent a mistake, and that request was the whole enforcement. When it
/// failed, the app showed somebody words they had never spoken and crossed
/// them out — the fastest way to lose trust in the one feature that justifies
/// the speaking tab, and impossible for a learner to diagnose: they cannot
/// tell "the app misheard me" from "I said it wrong".
///
/// The check is word overlap rather than string distance because the two texts
/// come from different places — one from Whisper, one echoed back by the model
/// — and disagree about punctuation, casing and the odd filler word.
void main() {
  TutorCorrection fix(String said, String better) =>
      TutorCorrection(said: said, better: better);

  group('a correction about the sentence is kept', () {
    test('an exact quote', () {
      expect(
        fix('I go to school yesterday', 'I went to school yesterday')
            .isAbout('I go to school yesterday'),
        isTrue,
      );
    });

    test('punctuation and casing drift', () {
      // Whisper writes one way, the model echoes another. Neither is wrong.
      expect(
        fix('i go to school yesterday.', 'I went to school yesterday.')
            .isAbout('I go to school yesterday'),
        isTrue,
      );
    });

    test('the model trims a filler', () {
      expect(
        fix('I want a coffee', "I'd like a coffee")
            .isAbout('Um, I want a coffee please'),
        isTrue,
      );
    });

    test('a single word', () {
      expect(fix('goed', 'went').isAbout('goed'), isTrue);
    });
  });

  group('a correction about something else is dropped', () {
    test('a wholly invented sentence', () {
      expect(
        fix('The weather is very nice today', 'The weather is lovely today')
            .isAbout('I go to school yesterday'),
        isFalse,
      );
    });

    test('a sentence from an earlier turn', () {
      // The real shape of this failure: the model corrects something said two
      // turns ago and it lands on the newest turn, which is a different
      // sentence entirely.
      expect(
        fix('I have twenty five years', 'I am twenty five years old')
            .isAbout('Can I have a coffee please'),
        isFalse,
      );
    });

    test('nothing to compare against', () {
      expect(fix('I go to school', 'I went to school').isAbout(''), isFalse);
      expect(fix('', 'I went to school').isAbout('I go to school'), isFalse);
    });
  });

  group('a correction that changes nothing is not a correction', () {
    test('identical', () {
      expect(
        TutorCorrection.fromJson(<String, String>{
          'said': 'I went to school',
          'better': 'I went to school',
        }),
        isNull,
      );
    });

    test('differs only in case', () {
      expect(
        TutorCorrection.fromJson(<String, String>{
          'said': 'i went to school',
          'better': 'I went to school',
        }),
        isNull,
      );
    });

    test('differs only in punctuation', () {
      // The one that shipped. The model is asked to reproduce "their exact
      // words" and drifts by a full stop; a lowercase-only comparison let it
      // through and drew a chip whose two lines were visibly identical.
      expect(
        TutorCorrection.fromJson(<String, String>{
          'said': 'I went to school.',
          'better': 'I went to school',
        }),
        isNull,
      );
      expect(
        TutorCorrection.fromJson(<String, String>{
          'said': 'I went to school ',
          'better': 'I  went to school!',
        }),
        isNull,
      );
    });

    test('a real difference still survives', () {
      // The guard above must not be so keen that it eats the feature.
      final TutorCorrection? kept = TutorCorrection.fromJson(<String, String>{
        'said': 'I go to school yesterday.',
        'better': 'I went to school yesterday.',
      });
      expect(kept, isNotNull);
      expect(kept!.better, 'I went to school yesterday.');
    });
  });
}
