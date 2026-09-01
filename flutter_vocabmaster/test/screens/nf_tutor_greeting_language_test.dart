import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/frontend_newest/screens/nf_tutor_page.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';

/// The tutor speaks English, whatever language the interface is in.
///
/// This test used to assert the opposite. The opening line was translated, so
/// a Turkish learner opening the tab was greeted with "Selam, ben Ryan" —
/// correct-looking, and wrong the moment you pressed play on it, because the
/// bubble is read aloud by Piper using an English voice. An English voice
/// reading Turkish words sounds like a foreigner sounding them out one at a
/// time. Found by listening to it on a phone; no assertion about strings could
/// have caught it, because both strings were perfectly correct on their own.
///
/// The tutor is the one thing in this app that has to be a native speaker, so
/// its lines left the localisation map altogether. What stays translated is
/// the interface around it: the caption under the button still reads
/// "Konuşmak için basılı tut", so the instruction is available in the
/// learner's language without the tutor breaking character.
///
/// Everything below checks that separation holds in both directions.
void main() {
  test('the greeting is not in the localisation map at all', () {
    // A key that exists is a key someone will translate again. `t` returns the
    // key itself when there is no value, which is how absence is asserted.
    for (final locale in AppLocalizations.supportedLocales) {
      expect(AppLocalizations(locale).t('tutor.greeting'), 'tutor.greeting',
          reason: '${locale.languageCode} has a translated greeting again, so '
              'an English voice is reading it aloud');
    }
  });

  test('the greeting names the speaker and says something', () {
    expect(NfScene.freeChatOpening, contains('{name}'),
        reason: 'the placeholder is gone, so the tutor introduces nobody');
    expect(NfScene.freeChatOpening.length, greaterThan(40),
        reason: 'too short to be the opening line it replaced');
  });

  test('nothing the tutor says carries a non-English letter', () {
    // Every language this app ships an interface in has letters English does
    // not, so one rule catches a line pasted in from any of them. It cannot
    // catch an English-lettered translation -- Portuguese "Segure o botao" --
    // which is why the first test above checks the map is empty rather than
    // relying on this one.
    final spoken = <String, String>{
      'freeChatOpening': NfScene.freeChatOpening,
      for (final scene in NfScene.all) scene.id: scene.opening,
      for (final scene in NfScene.all) '${scene.id}.character': scene.character,
    };

    expect(spoken.length, greaterThan(8),
        reason: 'only ${spoken.length} lines were checked, which is too few '
            'for this to mean anything');

    final offenders = <String>[];
    for (final entry in spoken.entries) {
      final foreign = RegExp('[çğıöşüÇĞİÖŞÜäöüßÄÖÜáéíóúñ¿¡àèìòùâêîôûëïœãõ]')
          .allMatches(entry.value)
          .map((m) => m.group(0))
          .toSet();
      if (foreign.isNotEmpty) {
        offenders.add('  ${entry.key}: ${foreign.join(', ')} '
            'in "${entry.value}"');
      }
    }

    expect(offenders, isEmpty,
        reason: 'These lines are spoken aloud by an English voice and are not '
            'English:\n${offenders.join('\n')}');
  });

  test('the interface around the tutor is still translated', () {
    // The other half of the separation. If these ever stop differing by
    // locale, the fix above has been applied one screen too widely and a
    // Turkish learner is being told to hold a button in a language they came
    // here to learn.
    for (final key in <String>[
      'tutor.caption.hold',
      'tutor.caption.release',
      'tutor.correction.label',
    ]) {
      final values = <String>[
        for (final locale in AppLocalizations.supportedLocales)
          AppLocalizations(locale).t(key),
      ];
      // A missing key returns itself from every locale, which would otherwise
      // read as "translated identically" -- and did, when this test was first
      // written against a key name that does not exist.
      expect(values, isNot(contains(key)),
          reason: '$key is not in the map, so this checks nothing');
      expect(values.toSet().length, greaterThan(3),
          reason: '$key reads the same across locales, so the interface has '
              'stopped being translated: $values');
    }
  });
}
