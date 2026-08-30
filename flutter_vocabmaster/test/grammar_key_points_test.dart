import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/data/grammar_data.dart';
import 'package:vocabmaster/data/grammar_formula_language.dart';
import 'package:vocabmaster/data/grammar_repository.dart';

/// The key points, in the reader's language.
///
/// These were the one part of the guide where the assumption held: 244 of the
/// 297 lines really were Turkish, unlike the mistake lists, where only 32 of
/// 209 were. Measuring first is why one of those took a morning and the other
/// took twenty minutes.
///
/// The screen no longer gates them on the reader being Turkish. It gates them
/// on there being something written in the reader's own language, which is a
/// different question and the right one.
void main() {
  late List<GrammarSubtopic> subtopics;

  setUp(() {
    subtopics = <GrammarSubtopic>[
      for (final topic in GrammarRepository.getAllTopics()) ...topic.subtopics,
    ];
    expect(subtopics.length, greaterThan(50));
  });

  test('a subtopic with Turkish key points has English ones too', () {
    final missing = subtopics
        .where((s) => (s.keyPoints ?? const <String>[]).isNotEmpty)
        .where((s) => (s.keyPointsEn ?? const <String>[]).isEmpty)
        .map((s) => s.id)
        .toList();

    expect(missing, isEmpty,
        reason: 'These show their key points to Turkish readers and nothing '
            'to anyone else: ${missing.join(", ")}');
  });

  test('no reader of another language is shown Turkish here', () {
    final offenders = <String>[];
    var lines = 0;

    for (final GrammarSubtopic subtopic in subtopics) {
      for (final String code in <String>['en', 'de', 'es', 'pt', 'it', 'fr']) {
        for (final String point in subtopic.keyPointsFor(code)) {
          lines++;
          if (!GrammarFormulaLanguage.isLanguageNeutral(point)) {
            offenders.add('  ${subtopic.id} ($code): $point');
          }
        }
      }
    }

    expect(lines, greaterThan(1000),
        reason: 'only $lines lines were read across six languages, which is '
            'far too few — the lists are not being reached');

    expect(offenders, isEmpty,
        reason: 'These put Turkish in front of a reader who has '
            'none:\n${offenders.join('\n')}');
  });

  test('nothing was lost in translation', () {
    // A short list is worse than the gate it replaced: one reader is given
    // four points and another two, with nothing to say which two went.
    final offenders = <String>[];
    for (final GrammarSubtopic subtopic in subtopics) {
      final int turkish = subtopic.keyPointsFor('tr').length;
      final int english = subtopic.keyPointsFor('en').length;
      if (turkish != english) {
        offenders.add('  ${subtopic.id}: $turkish in Turkish, $english in '
            'English');
      }
    }

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('Turkish readers keep the list written for them', () {
    for (final GrammarSubtopic subtopic in subtopics) {
      expect(subtopic.keyPointsFor('tr'), subtopic.keyPoints ?? const <String>[],
          reason: '${subtopic.id} showed a Turkish reader something else');
    }
  });
}
