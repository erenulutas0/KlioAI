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
    // Any leading whitespace, not exactly six spaces. Six was what `dart format`
    // happened to produce, so a re-indent made 18 real keys invisible to this
    // scanner and the reverse-lookup test below reported them as missing. A
    // guard that a formatter can blind is not a guard.
    return RegExp(r"^\s+'([^']+)':", multiLine: true)
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
    // `lib/frontend_newest` is in this list because it was not, and that was the
    // whole app: the new frontend is every screen a learner sees, and it sat
    // outside the only check that looks at widget source at all.
    for (final dir in ['lib/screens', 'lib/widgets', 'lib/frontend_newest']) {
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

  test('every key the app asks for is a key the app has', () {
    // The check the other three were missing, and the reason a run could be
    // green while the sign-in screen greeted people with the literal text
    // "auth.tagline". Key PARITY between locales passed perfectly - tr and de
    // mirrored en with no gaps - because all three were equally missing the 312
    // keys the new frontend had started calling. `AppLocalizations.t` ends in
    // `?? key`, so an unknown key is not an error anywhere: it is rendered.
    final english = keysFor('en');
    final call = RegExp(r"""(?:context\.tr|l10n\.t)\(\s*(['"])([a-zA-Z0-9_.]+)\1""");

    final missing = <String, Set<String>>{};
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      for (final m in call.allMatches(file.readAsStringSync())) {
        final key = m.group(2)!;
        if (!english.contains(key)) {
          (missing[file.path.replaceAll(r'\', '/')] ??= <String>{}).add(key);
        }
      }
    }

    expect(
      missing,
      isEmpty,
      reason: 'These keys are asked for in code but defined nowhere, so they '
          'render as their own name on screen:\n'
          '${missing.entries.map((e) => '  ${e.key}: ${e.value.join(', ')}').join('\n')}',
    );
  });

  test('the key scanner actually finds calls', () {
    // Without this, the assertion above would pass just as happily if the regex
    // stopped matching - the one failure mode a guard cannot report on itself.
    final call = RegExp(r"""(?:context\.tr|l10n\.t)\(\s*(['"])([a-zA-Z0-9_.]+)\1""");
    var found = 0;
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      found += call.allMatches(file.readAsStringSync()).length;
    }
    expect(found, greaterThan(200));
  });

  test('no placeholder ships as its own source text', () {
    // Writing `replaceAll('{n}', '\${widget.count}')` compiles, runs, and puts
    // the characters ${widget.count} on the screen: the backslash makes Dart
    // treat the interpolation as literal text. The Words tab's review row read
    // "Tekrar zamanı gelen ${widget.count}" on a real phone and nothing failed
    // — not the analyzer, not a test, not the build.
    //
    // An escaped `${` is essentially never what anyone wants here. A lone
    // escaped `$` still is (prices, currency), so only the interpolation form
    // is caught.
    final escaped = RegExp(r'\\\$\{');

    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final lines = file.readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (escaped.hasMatch(lines[i])) {
          final where = file.path.replaceAll(r'\', '/');
          offenders.add('$where:${i + 1}  ${lines[i].trim()}');
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'These put Dart source on screen instead of a value:\n'
            '${offenders.join('\n')}');
  });
}
