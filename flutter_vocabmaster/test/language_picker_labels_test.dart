import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';
import 'package:vocabmaster/services/learning_language_service.dart';

/// The language picker has to name every language it offers.
///
/// Both shipping pickers — the onboarding step and the settings sheet —
/// enumerate `supportedLocales`, so a new locale gets a row for free. Neither
/// one named it. Each had its own label helper shaped like
///
///     switch (code) {
///       case 'tr': ...
///       case 'de': ...
///       default:   return English;
///     }
///
/// so the day Spanish, Portuguese, Italian and French were added the picker
/// drew five selectable rows all labelled "English". Everything compiled,
/// every test passed, and the only person who could see it was a learner who
/// had opened the picker precisely because they could not read the interface.
void main() {
  test('every supported locale is named, and named only once', () {
    final Map<String, String> names = <String, String>{
      for (final locale in AppLocalizations.supportedLocales)
        locale.languageCode: AppLocalizations.languageName(locale.languageCode),
    };

    expect(names.length, greaterThan(1),
        reason: 'the scanner found one locale or none, so it is measuring '
            'nothing — check supportedLocales before trusting a pass');

    for (final MapEntry<String, String> entry in names.entries) {
      expect(entry.value, isNotEmpty, reason: '${entry.key} has no name');
      expect(entry.value, isNot(entry.key.toUpperCase()),
          reason: '${entry.key} falls through to the unknown-code branch: '
              'add onboarding.lang.name.${entry.key} to the map');
    }

    final Set<String> distinct = names.values.toSet();
    expect(distinct.length, names.length,
        reason: 'two locales share a label, so the picker offers rows a '
            'learner cannot tell apart: $names');
  });

  test('the shipping pickers take their labels from the shared name', () {
    // The distinctness above is an invariant of `languageName`. It says
    // nothing about whether a screen asks it — and the bug was exactly a
    // screen that did not. Both files are read for the call.
    const List<String> pickers = <String>[
      'lib/frontend_newest/screens/nf_onboarding_page.dart',
      'lib/frontend_newest/screens/nf_settings_page.dart',
    ];

    for (final String path in pickers) {
      final File file = File(path);
      expect(file.existsSync(), isTrue,
          reason: 'run this from the flutter_vocabmaster directory');

      final String code = file.readAsStringSync();
      expect(code.contains('AppLocalizations.languageName('), isTrue,
          reason: '$path labels its language rows some other way; a local '
              'helper with a default branch is how they all became English');
    }
  });

  test('every language the profile offers has a name in every locale', () {
    // The same mapping was written out four times -- the onboarding native
    // language step, the settings sheet, the translation screen's direction
    // labels and the Today card -- as four switches over the same seven names,
    // each with its own default. Adding Italian found three of them at once:
    // the picker offered "Italian" and the label said "English".
    for (final String language
        in LearningLanguageService.supportedSourceLanguages) {
      final String? key = AppLocalizations.languageNameKey(language);
      expect(key, isNotNull,
          reason: 'the profile offers $language and the app cannot name it: '
              'add language.${language.toLowerCase()} to every block');

      final Set<String> named = <String>{};
      for (final Locale locale in AppLocalizations.supportedLocales) {
        final String name = AppLocalizations(locale).t(key!);
        expect(name, isNot(key),
            reason: '${locale.languageCode} has no value for $key, so the '
                'screen shows the key itself');
        expect(name.trim(), isNotEmpty);
        named.add(name);
      }
      expect(named, isNotEmpty);
    }
  });

  test('no screen names a language on its own', () {
    // A switch mapping language names to l10n keys inside a screen is how
    // there came to be four of them. The names live in one place now, and a
    // screen reaching for language.turkish or language.french directly is
    // that mistake coming back. language.changed and language.label are not
    // names and are left alone.
    final Set<String> nameKeys = <String>{
      for (final String language
          in LearningLanguageService.supportedSourceLanguages)
        "'${AppLocalizations.languageNameKey(language)}'",
    };

    final offenders = <String>[];
    for (final file
        in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final String path = file.path.replaceAll('\\', '/');
      if (!path.endsWith('.dart')) continue;
      // The map itself, and the retired design, which is kept on disk but
      // unreachable.
      if (path.contains('/l10n/') || path.contains('lib/screens/')) continue;

      final List<String> lines = file.readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        for (final String key in nameKeys) {
          if (lines[i].contains(key)) {
            offenders.add('$path:${i + 1}  ${lines[i].trim()}');
          }
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'These name a language themselves instead of asking '
            'AppLocalizations.languageNameKey:\n'
            '${offenders.join('\n')}');
  });
}
