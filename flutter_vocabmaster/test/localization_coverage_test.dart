import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';

/// Two ways a learner ends up reading a language they did not choose.
///
/// A key can be added to English and forgotten in the others, and `t()` quietly falls back —
/// so a German user sees English and nothing anywhere says so. Or a string is written into a
/// widget directly, which is worse: the fallback cannot help, and a German user reads
/// Turkish. Four files were doing the second when this test was written.
void main() {
  final source = File('lib/l10n/app_localizations.dart').readAsStringSync();

  Set<String> keysFor(String language) {
    final block = RegExp("^    '$language': \{(.*?)^    \},",
            multiLine: true, dotAll: true)
        .firstMatch(source);
    expect(block, isNotNull, reason: 'no translation block for $language');
    return RegExp(r"^      '([^']+)':", multiLine: true)
        .allMatches(block!.group(1)!)
        .map((m) => m.group(1)!)
        .toSet();
  }

  test('every supported locale carries every key', () {
    final english = keysFor('en');
    expect(english, isNotEmpty);

    for (final locale in AppLocalizations.supportedLocales) {
      if (locale.languageCode == 'en') continue;
      final missing = english.difference(keysFor(locale.languageCode));
      expect(missing, isEmpty,
          reason: '${locale.languageCode} is missing: ${missing.take(10).join(', ')}');
    }
  });

  test('no supported locale carries a key English does not', () {
    // A stray key is a string nobody can reach, or an English one that was renamed and
    // left behind in the translations.
    final english = keysFor('en');
    for (final locale in AppLocalizations.supportedLocales) {
      if (locale.languageCode == 'en') continue;
      final extra = keysFor(locale.languageCode).difference(english);
      expect(extra, isEmpty,
          reason: '${locale.languageCode} has orphans: ${extra.take(10).join(', ')}');
    }
  });

  test('no screen or widget hardcodes Turkish text', () {
    // Turkish-specific letters are the giveaway. A file may use either mechanism - the
    // l10n keys or a local tr/en helper - but a bare literal reaches every user whatever
    // language they picked.
    final turkish = RegExp(r"'[^']*[çğıöşüÇĞİÖŞÜ][^']*'");
    final localized = RegExp(r"context\.tr\(|l10n\.t\(|_text\(|_t\(|LocaleTextService");

    final offenders = <String>[];
    for (final dir in ['lib/screens', 'lib/widgets']) {
      for (final file in Directory(dir).listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final content = file.readAsStringSync();
        if (turkish.hasMatch(content) && !localized.hasMatch(content)) {
          offenders.add(file.path);
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'Turkish strings with no way to translate them:\n${offenders.join('\n')}');
  });
}
