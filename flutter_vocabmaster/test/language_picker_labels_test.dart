import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';

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
}
