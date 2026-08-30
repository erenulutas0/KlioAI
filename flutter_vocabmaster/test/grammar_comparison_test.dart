import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/data/grammar_data.dart';
import 'package:vocabmaster/data/grammar_formula_language.dart';
import 'package:vocabmaster/data/grammar_repository.dart';

/// The comparison block, in the reader's language.
///
/// This is the last of the four. The guide is now written in English wherever
/// it was written in Turkish — formula, explanation, common mistakes, key
/// points and this. What stays Turkish is the exam tip, which is about YDS and
/// YÖKDİL and belongs to Turkish readers by its nature.
void main() {
  late List<GrammarSubtopic> subtopics;

  setUp(() {
    subtopics = <GrammarSubtopic>[
      for (final topic in GrammarRepository.getAllTopics()) ...topic.subtopics,
    ];
    expect(subtopics.length, greaterThan(50));
  });

  test('a subtopic with a Turkish comparison has an English one', () {
    final missing = subtopics
        .where((s) => (s.comparison ?? '').trim().isNotEmpty)
        .where((s) => (s.comparisonEn ?? '').trim().isEmpty)
        .map((s) => s.id)
        .toList();

    expect(missing, isEmpty,
        reason: 'These compare confusable topics for Turkish readers and say '
            'nothing to anyone else: ${missing.join(", ")}');
  });

  test('no reader of another language is shown Turkish here', () {
    final offenders = <String>[];
    var shown = 0;

    for (final GrammarSubtopic subtopic in subtopics) {
      for (final String code in <String>['en', 'de', 'es', 'pt', 'it', 'fr']) {
        final String? text = subtopic.comparisonFor(code);
        if (text == null) continue;
        shown++;
        if (!GrammarFormulaLanguage.isLanguageNeutral(text)) {
          offenders.add('  ${subtopic.id} ($code)');
        }
      }
    }

    expect(shown, greaterThan(100),
        reason: 'only $shown comparisons were reached across six languages, '
            'which is far too few');

    expect(offenders, isEmpty,
        reason: 'These put Turkish in front of a reader who has '
            'none:\n${offenders.join('\n')}');
  });

  test('the English is not a copy of the Turkish', () {
    for (final GrammarSubtopic subtopic in subtopics) {
      if (subtopic.comparisonEn == null) continue;
      expect(subtopic.comparisonEn!.trim(), isNot(subtopic.comparison?.trim()),
          reason: '${subtopic.id} has an English comparison identical to the '
              'Turkish one');
    }
  });

  test('Turkish readers keep the comparison written for them', () {
    for (final GrammarSubtopic subtopic in subtopics) {
      expect(subtopic.comparisonFor('tr'), subtopic.comparison,
          reason: '${subtopic.id} showed a Turkish reader something else');
    }
  });

  test('nothing in the guide is Turkish-only except the exam tip', () {
    // The whole point of the last four commits, asked once, plainly. If a new
    // subtopic arrives with Turkish prose and no English beside it, this is
    // the test that says so regardless of which field it landed in.
    final offenders = <String>[];
    for (final GrammarSubtopic s in subtopics) {
      if ((s.explanationEn ?? '').trim().isEmpty) {
        offenders.add('  ${s.id}: explanation');
      }
      if ((s.keyPoints ?? const <String>[]).isNotEmpty &&
          (s.keyPointsEn ?? const <String>[]).isEmpty) {
        offenders.add('  ${s.id}: keyPoints');
      }
      if ((s.comparison ?? '').trim().isNotEmpty &&
          (s.comparisonEn ?? '').trim().isEmpty) {
        offenders.add('  ${s.id}: comparison');
      }
      for (final String m in s.commonMistakesFor('en')) {
        if (!GrammarFormulaLanguage.isLanguageNeutral(m)) {
          offenders.add('  ${s.id}: commonMistakes');
          break;
        }
      }
      if (!GrammarFormulaLanguage.isLanguageNeutral(s.formulaFor('en'))) {
        offenders.add('  ${s.id}: formula');
      }
    }

    expect(offenders, isEmpty,
        reason: 'These parts of the guide reach only Turkish '
            'readers:\n${offenders.join('\n')}');
  });
}
