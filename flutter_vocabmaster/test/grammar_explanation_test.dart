import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/data/grammar_data.dart';
import 'package:vocabmaster/data/grammar_formula_language.dart';
import 'package:vocabmaster/data/grammar_repository.dart';

/// The grammar guides are being written in English, one subtopic at a time.
///
/// `explanation` is the body of each guide and it is Turkish. A reader of any
/// other language got a single generic sentence in its place — "Present Simple
/// is an English grammar pattern. Check the formula below, then study the
/// examples" — the same one on all eighty-three subtopics. The app offers
/// seven interface languages and taught in one.
///
/// This is a job in progress, so the test is written for a job in progress:
/// it pins how many are done rather than demanding they all are. The number
/// goes up as the work lands and can never go down by accident, which is the
/// only property that matters while the work is half finished. When it reaches
/// the total, this becomes an ordinary "every subtopic has one" check.
void main() {
  /// Raise this as explanations land. Never lower it.
  const int written = 45;

  late List<GrammarSubtopic> subtopics;

  setUp(() {
    subtopics = <GrammarSubtopic>[
      for (final topic in GrammarRepository.getAllTopics()) ...topic.subtopics,
    ];
    expect(subtopics.length, greaterThan(50),
        reason: 'only ${subtopics.length} subtopics were found');
  });

  test('the English explanations written so far are still there', () {
    final int have = subtopics
        .where((s) => (s.explanationEn ?? '').trim().isNotEmpty)
        .length;

    expect(have, greaterThanOrEqualTo(written),
        reason: '$have subtopics have an English explanation and $written had '
            'one when this was last updated. Something removed '
            '${written - have} of them.');

    if (have > written) {
      fail('$have subtopics now have an English explanation, up from '
          '$written. Raise `written` to $have — the count is the record of '
          'how far this has got, and it is only useful if it is current.');
    }
  });

  test('an English explanation is not the Turkish one', () {
    // Two ways to fill the field without doing the work: paste the Turkish in,
    // or paste the generic fallback sentence in.
    final offenders = <String>[];
    for (final GrammarSubtopic subtopic in subtopics) {
      final String? english = subtopic.explanationEn;
      if (english == null || english.trim().isEmpty) continue;

      if (english.trim() == subtopic.explanation.trim()) {
        offenders.add('  ${subtopic.id}: the English is a copy of the Turkish');
      }
      if (!GrammarFormulaLanguage.isLanguageNeutral(english)) {
        offenders.add('  ${subtopic.id}: the English holds Turkish');
      }
      // Shorter than a tweet is not an explanation of a grammar topic; the
      // generic sentence it replaces is already longer than that.
      if (english.trim().length < 200) {
        offenders.add('  ${subtopic.id}: ${english.trim().length} characters, '
            'which is shorter than the generic sentence it replaces');
      }
    }

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('Turkish readers keep the Turkish explanation', () {
    for (final GrammarSubtopic subtopic in subtopics) {
      expect(subtopic.explanationFor('tr'), subtopic.explanation,
          reason: '${subtopic.id} showed a Turkish reader something other '
              'than the explanation written for them');
    }
  });

  test('a subtopic with no English explanation shows none, not the Turkish',
      () {
    // The screen falls back to the generic sentence on null. Returning the
    // Turkish here would put it back in front of the readers this whole
    // exercise is for.
    for (final GrammarSubtopic subtopic in subtopics) {
      if (subtopic.explanationEn != null) continue;
      for (final String code in <String>['en', 'de', 'es', 'pt', 'it', 'fr']) {
        expect(subtopic.explanationFor(code), isNull,
            reason: '${subtopic.id} handed a $code reader Turkish prose');
      }
    }
  });
}
