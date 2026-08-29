import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/data/grammar_data.dart';
import 'package:vocabmaster/data/grammar_formula_language.dart';
import 'package:vocabmaster/data/grammar_repository.dart';

/// A Turkish formula must have an English one beside it.
///
/// The formula block was the last part of the grammar guide still shown to
/// every language as written, and forty-five of the eighty-three were written
/// in Turkish. A Spanish reader opening Present Simple got
/// "➕ Olumlu: Subject + V1 (he/she/it için +s/es)". They each have a
/// `formulaEn` now.
///
/// The classifier behind this is Turkish letters plus a word list, and a list
/// is exactly what this codebase keeps getting wrong. Two attempts to make it
/// check itself both failed:
///
/// The first read the Turkish half of the localisation map as a dictionary of
/// known Turkish. Deleting "Olumlu" and "Soru" from the classifier — the exact
/// mistake it existed to catch — left it passing, because neither word appears
/// anywhere in nine hundred interface strings.
///
/// The second added the Turkish `explanation` blocks to that dictionary. Those
/// explain English grammar in Turkish, so they are full of Gerund, Infinitive,
/// Subject, Object, Passive and Modal, and it reported eighteen perfectly
/// English formulas as Turkish.
///
/// So the formulas were read instead, one at a time. That reading found five
/// the classifier had wrongly passed — NESNE in have_something_done and
/// get_something_done, "to yok" and "opsiyonel" in let_make_help, "de/da
/// gelebilir" in the first and second conditionals — English formulas with
/// Turkish buried in them, which no letter rule can see.
///
/// Counting them also turned up `advancedClausesTopic`: three subtopics
/// declared in grammar_content_advanced_clauses.dart and never listed in
/// GrammarRepository, so the app has never shown them. They are a coarser
/// early version of three topics that each shipped separately, which is why
/// the files hold eighty-six formulas and the app has eighty-three.
void main() {
  late List<GrammarSubtopic> subtopics;

  setUp(() {
    subtopics = <GrammarSubtopic>[
      for (final topic in GrammarRepository.getAllTopics()) ...topic.subtopics,
    ];
    expect(subtopics.length, greaterThan(50),
        reason: 'only ${subtopics.length} subtopics were found, so the checks '
            'below are looking at almost nothing');
  });

  test('no Turkish formula reaches a reader without one in English', () {
    final offenders = <String>[];
    for (final GrammarSubtopic subtopic in subtopics) {
      if (GrammarFormulaLanguage.isLanguageNeutral(subtopic.formula)) continue;
      if (subtopic.formulaEn == null || subtopic.formulaEn!.trim().isEmpty) {
        offenders.add('  ${subtopic.id}: "${subtopic.formula.trim()}"');
      }
    }

    expect(offenders, isEmpty,
        reason: 'These formulas are Turkish and have no English beside them, '
            'so the six other interface languages are shown Turkish:\n'
            '${offenders.join('\n')}');
  });

  test('an English formula is not itself Turkish', () {
    // The point of the exercise, and cheap to get wrong by copying the
    // original into the new field.
    final offenders = <String>[];
    for (final GrammarSubtopic subtopic in subtopics) {
      final String? english = subtopic.formulaEn;
      if (english == null) continue;
      if (!GrammarFormulaLanguage.isLanguageNeutral(english)) {
        offenders.add('  ${subtopic.id}: "${english.trim()}"');
      }
      if (english.trim() == subtopic.formula.trim()) {
        offenders.add('  ${subtopic.id}: the English is a copy of the Turkish');
      }
    }

    expect(offenders, isEmpty,
        reason: 'These carry Turkish in the field meant to be free of '
            'it:\n${offenders.join('\n')}');
  });

  test('the classifier fires, and does not fire on everything', () {
    // Both directions matter. All-neutral means the guard above is vacuous and
    // a Spanish reader still gets Turkish; all-Turkish means it is rejecting
    // notation and demanding translations of "Subject + get/got + V3".
    final int turkish = subtopics
        .where((s) => !GrammarFormulaLanguage.isLanguageNeutral(s.formula))
        .length;
    expect(turkish, greaterThan(20),
        reason: 'only $turkish formulas were found to be Turkish, and there '
            'were forty-five when they were read — the classifier has gone '
            'blind');
    expect(subtopics.length - turkish, greaterThan(20),
        reason: 'almost every formula is being called Turkish, so the '
            'classifier is firing on English notation');
  });

  test('the five that were nearly missed are still caught', () {
    // Named, because they are the evidence that reading beat the rule.
    const nearlyMissed = <String>[
      'have_something_done',
      'get_something_done',
      'let_make_help',
      'first_conditional',
      'second_conditional',
    ];

    for (final String id in nearlyMissed) {
      final GrammarSubtopic subtopic =
          subtopics.firstWhere((s) => s.id == id, orElse: () {
        fail('$id is gone; it was one of the five, so check what replaced it');
      });
      expect(GrammarFormulaLanguage.isLanguageNeutral(subtopic.formula), isFalse,
          reason: '$id holds Turkish inside an English formula and would be '
              'shown as written: "${subtopic.formula}"');
      expect(subtopic.formulaEn, isNotNull);
    }
  });

  test('Turkish readers keep the Turkish formula', () {
    for (final GrammarSubtopic subtopic in subtopics) {
      expect(subtopic.formulaFor('tr'), subtopic.formula,
          reason: '${subtopic.id} showed a Turkish reader something other '
              'than the formula written for them');
    }
  });

  test('every other language gets English where there is Turkish', () {
    const others = <String>['en', 'de', 'es', 'pt', 'it', 'fr'];
    for (final GrammarSubtopic subtopic in subtopics) {
      for (final String code in others) {
        final String shown = subtopic.formulaFor(code);
        expect(GrammarFormulaLanguage.isLanguageNeutral(shown), isTrue,
            reason: '${subtopic.id} shows a $code reader Turkish: "$shown"');
      }
    }
  });
}
