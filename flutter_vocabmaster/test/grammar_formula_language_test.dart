import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/data/grammar_data.dart';
import 'package:vocabmaster/data/grammar_formula_language.dart';
import 'package:vocabmaster/data/grammar_repository.dart';

/// Which grammar formulas may be shown to a reader who has no Turkish.
///
/// The classifier is Turkish letters plus a list of Turkish words that turn up
/// in otherwise-ASCII formulas, and a list is exactly what this codebase keeps
/// getting wrong. Two attempts at making the list check itself failed before
/// this file settled:
///
/// The first read the Turkish half of the localisation map as a dictionary of
/// known Turkish. Removing "Olumlu" and "Soru" from the classifier — the exact
/// mistake it existed to catch — left it passing, because neither word appears
/// anywhere in nine hundred interface strings.
///
/// The second added the Turkish `explanation` blocks to that
/// dictionary. Those blocks explain English grammar in Turkish, so they are
/// full of Gerund, Infinitive, Subject, Object, Passive and Modal, and it
/// reported eighteen perfectly English formulas as Turkish.
///
/// So the formulas were read instead, one at a time. That reading
/// found five the classifier had wrongly passed — NESNE in
/// have_something_done and get_something_done, "to yok" and "opsiyonel" in
/// let_make_help, "de/da
/// gelebilir" in the first and second conditionals — and the words behind them
/// are now in the list. The thirty-eight that remain were read in full and
/// are notation: "Subject + get/got + V3", "Only + Time/Condition + Auxiliary
/// + Subject + Verb".
///
/// Counting them also turned up `advancedClausesTopic` — three subtopics that
/// are declared in grammar_content_advanced_clauses.dart and never listed in
/// GrammarRepository, so the app has never shown them. They are a coarser
/// early version of the relative-clause, noun-clause and conjunction topics
/// that each shipped separately, which is why the first count of the formulas
/// said eighty-six and the app has eighty-three.
///
/// What is pinned below is that reading. The count is not a threshold anyone
/// tuned; it is the number of formulas a person confirmed, on 29 August 2026,
/// contain no Turkish. If the data changes the count changes, this fails, and
/// the new ones want the same treatment — which is the whole of what a test
/// can honestly promise here.
void main() {
  /// Read individually and confirmed free of Turkish.
  const int neutralFormulas = 38;

  /// Withheld from readers of the other six languages.
  const int turkishFormulas = 45;

  late List<GrammarSubtopic> subtopics;

  setUp(() {
    subtopics = <GrammarSubtopic>[
      for (final topic in GrammarRepository.getAllTopics()) ...topic.subtopics,
    ];
  });

  test('the split is the one a person checked', () {
    final int neutral = subtopics
        .where((s) => GrammarFormulaLanguage.isLanguageNeutral(s.formula))
        .length;

    expect(subtopics.length, neutralFormulas + turkishFormulas,
        reason: 'there are ${subtopics.length} subtopics now, not '
            '${neutralFormulas + turkishFormulas}. The formulas of whatever '
            'was added or removed have not been read.');
    expect(neutral, neutralFormulas,
        reason: '$neutral formulas are being shown to every language, and '
            '$neutralFormulas were read and confirmed free of Turkish. '
            'Whatever changed, read it before trusting this.');
  });

  test('the classifier fires, and does not fire on everything', () {
    // Both directions matter and neither is implied by the count above once
    // the data changes: all-neutral means a Spanish reader still gets Turkish,
    // all-Turkish means every other language quietly lost its formulas.
    final int neutral = subtopics
        .where((s) => GrammarFormulaLanguage.isLanguageNeutral(s.formula))
        .length;
    expect(neutral, greaterThan(20));
    expect(subtopics.length - neutral, greaterThan(20));
  });

  test('the five that were nearly missed stay classified as Turkish', () {
    // Named, because these are the evidence that reading beat the rule. Each
    // is an English formula with one or two Turkish words buried in it, which
    // is the shape a letter-based check cannot see.
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
          reason: '$id holds Turkish inside an English formula and is being '
              'shown to readers who cannot read it: "${subtopic.formula}"');
    }
  });

  test('Turkish readers keep every formula', () {
    for (final GrammarSubtopic subtopic in subtopics) {
      expect(GrammarFormulaLanguage.showTo('tr', subtopic.formula), isTrue,
          reason: '${subtopic.id} was withheld from a Turkish reader, who is '
              'who this data was written for');
    }
  });
}
