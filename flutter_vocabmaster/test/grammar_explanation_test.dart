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
/// While the work was half done this pinned a count -- 12, then 23, 31, 37,
/// 45, 53, 69 -- so the gap stayed a number that had to come down rather than
/// a silence, and so that nothing could quietly disappear on the way. All
/// eighty-three are written now, so it asks the plain question instead.
void main() {

  late List<GrammarSubtopic> subtopics;

  setUp(() {
    subtopics = <GrammarSubtopic>[
      for (final topic in GrammarRepository.getAllTopics()) ...topic.subtopics,
    ];
    expect(subtopics.length, greaterThan(50),
        reason: 'only ${subtopics.length} subtopics were found');
  });

  test('every subtopic explains itself in English', () {
    final missing = subtopics
        .where((s) => (s.explanationEn ?? '').trim().isEmpty)
        .map((s) => s.id)
        .toList();

    expect(missing, isEmpty,
        reason: 'These would show a reader of the other six languages one '
            'generic sentence instead of the guide: ${missing.join(", ")}');
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

  test('no sentence is broken in half by a hard line break', () {
    // Found by looking at a phone, not by any test. The Present Simple guide
    // read "...general truths, habits, routines and / situations that do not
    // change", breaking after "and" no matter how wide the screen was --
    // because the text carried a newline there. I put it in while matching
    // the line width of the Turkish source, which is a shape that means
    // nothing once the words are different.
    //
    // A heuristic, and stated as one: a line ending in a word that cannot end
    // a thought. It is not a parser. `as_as_structures` legitimately has two
    // pattern lines in a row ("not as + adj + as" / "not so + adj + as") and
    // is not caught, which is the point of choosing the words rather than
    // flagging every lowercase line.
    const danglers = <String>[
      'and', 'or', 'the', 'a', 'an', 'of', 'in', 'to', 'for', 'with',
      'its', 'never', 'that', 'which', 'is', 'are', 'be', 'by', 'from',
    ];

    final offenders = <String>[];
    for (final GrammarSubtopic subtopic in subtopics) {
      final List<String> lines = (subtopic.explanationEn ?? '').split('\n');
      for (var i = 0; i + 1 < lines.length; i++) {
        final String here = lines[i].trimRight();
        if (here.isEmpty || lines[i + 1].trim().isEmpty) continue;
        // The next line must read as a continuation, not as a new item. A
        // bullet, an emoji or a capital starts something; a bare lowercase
        // word carries on.
        //
        // A line beginning with a quotation mark is left alone, and that is a
        // deliberate blind spot. It would catch one more real break in
        // passive_modals -- already fixed by hand -- at the cost of flagging
        // the quantifier lists, where a line of patterns is followed by a
        // line of quoted examples on purpose. A guard that cries wolf gets
        // switched off, and then it catches nothing at all.
        final String next = lines[i + 1].trim();
        if (!RegExp(r'^[a-z]').hasMatch(next)) continue;

        final String last = here.split(' ').last.toLowerCase();
        if (danglers.contains(last)) {
          offenders.add('  ${subtopic.id}: "...$last" / "$next..."');
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'These break a sentence where the screen would not:'
            '\n${offenders.join('\n')}');
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
