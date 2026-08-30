import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/data/grammar_data.dart';
import 'package:vocabmaster/data/grammar_formula_language.dart';
import 'package:vocabmaster/data/grammar_repository.dart';

/// The common-mistake lists are for everyone, not only Turkish readers.
///
/// The screen used to gate them on Turkish along with the rest of the guide's
/// extras. That was worth checking rather than assuming: of 209 mistake lines
/// in this app, only 32 held any Turkish, and even those held it only in the
/// note at the end. The wrong-then-right pair itself — "❌ She studys hard. →
/// ✅ She studies hard." — was already English in every single one, and was
/// hidden from six languages for no reason at all.
///
/// So the gate is gone, twenty-three subtopics got an English list, and the
/// other forty-one show their originals to everyone.
void main() {
  late List<GrammarSubtopic> subtopics;

  setUp(() {
    subtopics = <GrammarSubtopic>[
      for (final topic in GrammarRepository.getAllTopics()) ...topic.subtopics,
    ];
    expect(subtopics.length, greaterThan(50));
  });

  test('no reader of another language is shown Turkish here', () {
    final offenders = <String>[];
    var lines = 0;

    for (final GrammarSubtopic subtopic in subtopics) {
      for (final String code in <String>['en', 'de', 'es', 'pt', 'it', 'fr']) {
        for (final String mistake in subtopic.commonMistakesFor(code)) {
          lines++;
          if (!GrammarFormulaLanguage.isLanguageNeutral(mistake)) {
            offenders.add('  ${subtopic.id} ($code): $mistake');
          }
        }
      }
    }

    // A count, because a loop over empty lists passes every assertion made
    // about what it looped over.
    expect(lines, greaterThan(500),
        reason: 'only $lines lines were read across six languages, which is '
            'far too few — the lists are not being reached');

    expect(offenders, isEmpty,
        reason: 'These put Turkish in front of a reader who has none:\n'
            '${offenders.join('\n')}');
  });

  test('nothing was lost in translation', () {
    // An English list that drops lines is worse than the gate it replaced:
    // the Turkish reader is warned about four mistakes and the Spanish one
    // about two, with nothing to say which two went missing.
    final offenders = <String>[];
    for (final GrammarSubtopic subtopic in subtopics) {
      final int turkish = subtopic.commonMistakes.length;
      final int english = subtopic.commonMistakesFor('en').length;
      if (english != turkish) {
        offenders.add('  ${subtopic.id}: $turkish in Turkish, $english in '
            'English');
      }
    }

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('Turkish readers keep the list written for them', () {
    for (final GrammarSubtopic subtopic in subtopics) {
      expect(subtopic.commonMistakesFor('tr'), subtopic.commonMistakes,
          reason: '${subtopic.id} showed a Turkish reader something else');
    }
  });

  test('an English list is not a copy of the Turkish one', () {
    // The point of writing one. A subtopic that needed an English list and
    // got a duplicate would pass the first test only by accident.
    for (final GrammarSubtopic subtopic in subtopics) {
      if (subtopic.commonMistakesEn == null) continue;
      expect(subtopic.commonMistakesEn, isNot(subtopic.commonMistakes),
          reason: '${subtopic.id} has an English list identical to the '
              'Turkish one, so it did not need one');
    }
  });
}
