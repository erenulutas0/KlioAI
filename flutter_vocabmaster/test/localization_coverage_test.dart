import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';

/// Turkish's own casing rules, applied before comparing. Without these, "YENİ"
/// and "Yeni" look like a contradiction when they are simply the same word
/// cased two ways: in Turkish, i uppercases to İ and I lowercases to ı. A guard
/// that failed on those would be reporting correct spelling as an error, and a
/// guard that cries wolf gets switched off.
String turkishLower(String s) =>
    s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();

/// The same word with its Turkish marks removed, so "çöz" and "coz" can be
/// recognised as two spellings of one word.
String foldDiacritics(String s) {
  const from = 'çğıöşüÇĞİÖŞÜ';
  const to = 'cgiosuCGIOSU';
  final buffer = StringBuffer();
  for (final rune in s.runes) {
    final char = String.fromCharCode(rune);
    final at = from.indexOf(char);
    buffer.write(at < 0 ? char : to[at]);
  }
  return buffer.toString();
}

/// Two ways a learner ends up reading a language they did not choose.
///
/// A key can be added to English and forgotten in the others, and `t()` quietly falls back —
/// so a German user sees English and nothing anywhere says so. Or a string is written into a
/// widget directly, which is worse: the fallback cannot help, and a German user reads
/// Turkish. Four files were doing the second when this test was written.
/// Words that fold to the same spelling and are not the same word.
///
/// Every spelling check in this file rests on one assumption: that a folded
/// form belongs to a single word, so two spellings of it mean one is wrong.
/// Turkish has pairs where the mark carries the whole meaning, and for those
/// the assumption is simply false — both spellings are correct and mean
/// different things.
///
/// This list exists because the settings screen said "Uygulama Türü",
/// application TYPE, for a guided tour, and every rule here called it correct,
/// since it is. These are the errors the guards are structurally worst at: a
/// screen test that pins the actual label is the only thing that can catch one.
const homographs = <String, String>{
  'turu': 'tur (a tour) / tür (a kind)',
  'soyle': 'şöyle (like this) / söyle (say it)',
  'sik': 'şikâyet (a complaint) / sık (frequent)',
};

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

  test('no locale string ships a backslash to the screen', () {
    // A translation carrying a real line break has to reach Dart as \n. The
    // script that writes these blocks escaped the backslash first and the line
    // break second, so Spanish and Portuguese shipped \\n on session.empty:
    // Dart reads that as an escaped backslash and paints the two characters
    // \n in the middle of the sentence. It compiles, it runs, and only a
    // reader of that language would ever notice.
    //
    // Nothing this app says to a user contains a backslash. No file paths, no
    // regexes, no code -- so any escaped one in the map is this mistake.
    final source = File('lib/l10n/app_localizations.dart').readAsStringSync();
    final offenders = <String>[];
    final lines = source.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].contains('\\\\')) {
        offenders.add('app_localizations.dart:${i + 1}  ${lines[i].trim()}');
      }
    }

    expect(offenders, isEmpty,
        reason: 'These paint a backslash instead of a line break:\n'
            '${offenders.join('\n')}');
  });

  test('Turkish spells each word one way', () {
    // Turkish readers are the entire audience, and to them a missing ö or ş
    // does not read as a typo — it reads as a machine wrote it.
    //
    // This used to be a hand-written list of thirty stripped words. That guard
    // only ever caught what someone had remembered to enumerate: it passed
    // while the file carried "Giris" beside "giriş", "Gunun" beside "Günün",
    // "Turkce" beside "Türkçe" — forty-odd words spelled both ways at once.
    //
    // So it asks a question the file can answer about itself instead. If the
    // same word appears with its diacritics somewhere and without them
    // somewhere else, one of the two is wrong, and no dictionary is needed to
    // know that. It cannot catch a word that is stripped everywhere — nothing
    // short of a dictionary can — but it makes the file's own inconsistency
    // impossible to reintroduce.
    final block = RegExp("^    'tr': \\{(.*?)^    \\},",
            multiLine: true, dotAll: true)
        .firstMatch(source);
    expect(block, isNotNull);

    // Turkish's own casing rules, applied before comparing. Without these,
    // "YENİ" and "Yeni" look like a contradiction when they are simply the
    // same word cased two ways: in Turkish, i uppercases to İ and I lowercases
    // to ı. A guard that failed on those would be reporting correct spelling
    // as an error, and a guard that cries wolf gets switched off.

    // Every piece of Turkish the app can put on screen, not just the map.
    //
    // The guard used to read app_localizations.dart and stop there, while
    // `LocaleTextService.pick('<turkish>', '<english>')` writes user-facing
    // Turkish straight into services and screens. Eight strings in the AI error
    // formatter sat stripped of their diacritics for as long as this test has
    // existed, because the test could not see the file they were in.
    //
    // Pooling them matters in both directions: the map is large and mostly
    // right, so it exposes a stripped word in a service file, and a correctly
    // spelled service string exposes a stripped one in the map. Two of the
    // seven found this way were in the map itself.
    final List<MapEntry<String, String>> turkishStrings =
        <MapEntry<String, String>>[];

    // The space between the colon and the value is `\s*`, not a literal space,
    // so an entry whose value sits on the next line is read too. 103 of the
    // Turkish entries are wrapped that way -- an eighth of the corpus -- and
    // every spelling check in this file had been blind to all of them. The
    // settings screen said "Pratigi Ingilizce odaginda tutarken AI icin" in
    // front of a Turkish user while these tests ran green.
    final entry =
        RegExp(r"^\s+'([^']+)':\s*'([^']*)'", multiLine: true, dotAll: true);
    for (final m in entry.allMatches(block!.group(1)!)) {
      turkishStrings.add(MapEntry<String, String>(m.group(1)!, m.group(2)!));
    }

    // The Turkish argument comes first in both bilingual helpers: the shared
    // LocaleTextService.pick, and the per-file `String _text(String tr, String
    // en)` that the older screens declare for themselves. The second is by far
    // the larger corpus -- 497 calls across 24 files against pick()'s 42 -- and
    // was the last place user-facing Turkish could go unread.
    final helpers = <String, RegExp>{
      'pick': RegExp(r"LocaleTextService\.pick\(\s*'([^']*)'", dotAll: true),
      '_text': RegExp(r"_text\(\s*'([^']*)'", dotAll: true),
    };
    final found = <String, int>{'l10n': turkishStrings.length};
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final code = file.readAsStringSync();
      for (final MapEntry<String, RegExp> helper in helpers.entries) {
        for (final m in helper.value.allMatches(code)) {
          turkishStrings.add(MapEntry<String, String>(file.path, m.group(1)!));
          found[helper.key] = (found[helper.key] ?? 0) + 1;
        }
      }
    }

    // Per source, not one total. A single number hides the failure that
    // matters: one of the three stops matching -- a renamed helper, a
    // reformatted map, a screen switching to double quotes -- and the total
    // still looks healthy because the other two carry it. That is how 497
    // strings went unread for as long as they did, and a combined count of 794
    // was misread as proof they were covered while the new scanner found none
    // of them.
    const floors = <String, int>{'l10n': 200, 'pick': 20, '_text': 300};
    for (final MapEntry<String, int> floor in floors.entries) {
      expect(found[floor.key] ?? 0, greaterThan(floor.value),
          reason: 'the ${floor.key} scanner has gone blind: it found '
              '${found[floor.key] ?? 0}, so that whole corpus is unchecked');
    }

    // folded spelling -> the distinct Turkish-lowercased forms seen for it,
    // each with an example source so a failure names somewhere to look.
    final spellings = <String, Map<String, String>>{};
    for (final m in turkishStrings) {
      final key = m.key;
      for (final token
          in m.value.split(RegExp(r'[^A-Za-zçğıöşüÇĞİÖŞÜ]+'))) {
        // Two letters and under is mostly abbreviations and roman numerals,
        // where a stripped form is not evidence of anything.
        if (token.length < 3) continue;
        final folded = foldDiacritics(token).toLowerCase();
        (spellings[folded] ??= <String, String>{})
            .putIfAbsent(turkishLower(token), () => key);
      }
    }

    final offenders = <String>[];
    for (final MapEntry<String, Map<String, String>> e in spellings.entries) {
      if (e.value.length < 2) continue;
      // Two spellings, two words. Not a contradiction to report.
      if (homographs.containsKey(e.key)) continue;
      final variants = e.value.entries
          .map((v) => '"${v.key}" (${v.value})')
          .join('  vs  ');
      offenders.add('  ${e.key}: $variants');
    }

    expect(offenders, isEmpty,
        reason: 'The same Turkish word is spelled more than one way:\n'
            '${offenders.join('\n')}');

    // A stricter second question, because the check above has a blind spot it
    // cannot report on itself: it only sees a word spelled BOTH ways inside
    // the pool. A word stripped in every user-facing string looks perfectly
    // consistent. One was -- "olustu" appeared in every place a learner could
    // read it, and a sweep meant to add diacritics quietly removed one more.
    //
    // But the app ships thousands of lines of Turkish grammar prose, and that
    // prose is spelled properly. So the rest of lib/ is the dictionary: if a
    // bare word in a user-facing string has an accented twin somewhere in the
    // source, and exactly one such twin, the bare one is the mistake. This
    // found 90 stripped words the pool alone could not see.
    final dictionary = <String, Set<String>>{};
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      for (final token in file.readAsStringSync().split(RegExp(r'[^A-Za-zçğıöşüÇĞİÖŞÜ]+'))) {
        if (token.length < 4) continue;
        if (foldDiacritics(token) == token) continue;
        (dictionary[foldDiacritics(token).toLowerCase()] ??= <String>{})
            .add(turkishLower(token));
      }
    }

    // The one thing this check cannot work out for itself: that two spellings
    // are two words. It assumes a folded form belongs to a single word, and
    // Turkish has pairs where the mark carries the whole meaning -- tur is a
    // tour and tür is a kind, so "uygulama turu" and "uygulama türü" are both
    // correct Turkish and mean different things. Listed by folded form, with
    // the pair written out, because a bare entry here would look like an
    // excuse rather than a fact about the language.
    //
    // These are also the errors the guards are worst at: this list exists
    // because the settings screen said "Uygulama Türü" -- application TYPE --
    // for a guided tour, and every spelling rule in this file called it
    // correct, since it is.
    final stripped = <String>{};
    for (final m in turkishStrings) {
      for (final token in m.value.split(RegExp(r'[^A-Za-zçğıöşüÇĞİÖŞÜ]+'))) {
        if (token.length < 4) continue;
        if (foldDiacritics(token) != token) continue;
        if (homographs.containsKey(token.toLowerCase())) continue;
        final twins = dictionary[token.toLowerCase()];
        if (twins == null || twins.length != 1) continue;
        if (twins.contains(turkishLower(token))) continue;
        stripped.add(
            '  ${turkishLower(token)} -> ${twins.first}   (${m.key})');
      }
    }

    expect(stripped, isEmpty,
        reason: 'Spelled bare here, spelled properly elsewhere in the same '
            'app:\n${stripped.join('\n')}');
  });

  test('no Turkish word quietly breaks vowel harmony', () {
    // The last rule that can find a stripped word with no correct twin to
    // compare it against -- and there is no dictionary here to do it any other
    // way.
    //
    // Turkish vowels come in two sets, and a native word uses one or the
    // other. Stripping diacritics moves vowels across that line: ı becomes i,
    // ö becomes o, ü becomes u. So a word that mixes the sets, and that could
    // be un-mixed by putting the marks back, is almost always a word someone
    // typed without them. "calismasi" and "yukleyin" were found exactly this
    // way -- 60 of them, in sentences the two comparison guards read as
    // perfectly consistent because every copy was equally bare.
    //
    // Turkish also borrows freely, and a loanword answers to no harmony:
    // "kitap", "sohbet", "profil", "tarih". Those are listed below. The list
    // is the exceptions, NOT the words this test knows about -- a new bare
    // word fails here by default, and passing it means either fixing it or
    // saying in writing why it is allowed. That direction is the whole point:
    // the enumerated list this file used to rely on could only ever catch what
    // somebody had remembered to write down.
    const back = 'aıou';
    const front = 'eiöü';
    const known = <String>{
      'aktif', 'analitik', 'analiz', 'biraz', 'birazdan', 'diyaloglar',
      'ipucu', 'kompozisyonlar', 'motivasyonunuzu',
      'buildde', 'cihaz', 'dahil', 'dakika', 'telefon', 
      'endonezce', 'galaksisi', 'hangi', 'harika',
      'haziran', 'iptal', 'ispanyolca', 'italyanca',
      'kitap', 'kitaplar', 'klasik', 'memnuniyet', 'mevcut',
      'mikrofon', 'mobil', 'modeli', 'modeller', 'navigasyon',
      // Stems only. Inflected borrowings are handled by withoutBorrowedStem
      // below, so 'otel' covers otele, oteli and otelden without any of them
      // being written here -- and without excusing a word that merely starts
      // the same way.
      'nisan', 'otel', 'otomatik', 'portekizce', 'pratik', 'profesyonel',
      'profil', 'profili', 'profiller', 'rozetler', 'sakin',
      'senkron', 'senkronu', 'sohbet', 'sohbete', 'sohbeti',
      'sonraki', 'soyisim', 'takibi', 'takip', 'takviminiz',
      'tarih', 'temmuz', 'tempo', 'tokeni', 
      
    };

    String strip(String s) => s
        .replaceAll(RegExp(r'\$\{[^}]*\}'), ' ')
        .replaceAll(RegExp(r'\$[A-Za-z_][A-Za-z0-9_.]*'), ' ');
    final splitter = RegExp(r'[^A-Za-zçğıöşüÇĞİÖŞÜ]+');

    // English is the other half of every bilingual pair, so the app can say
    // which of its own words are not Turkish without being told.
    final english = <String>{};
    final turkish = <MapEntry<String, String>>[];
    final pair = RegExp(
        r"^\s+'[^']+':\s*'([^']*)'", multiLine: true, dotAll: true);
    for (final code in <String>['tr', 'en']) {
      final block = RegExp("^    '$code': "+r"\{(.*?)^    \},",
              multiLine: true, dotAll: true)
          .firstMatch(source);
      for (final m in pair.allMatches(block!.group(1)!)) {
        if (code == 'tr') {
          turkish.add(MapEntry<String, String>('l10n', m.group(1)!));
        } else {
          english.addAll(strip(m.group(1)!).split(splitter).map((w) => w.toLowerCase()));
        }
      }
    }
    final helpers = <RegExp>[
      RegExp(r"LocaleTextService\.pick\(\s*'([^']*)'\s*,\s*'([^']*)'", dotAll: true),
      RegExp(r"_text\(\s*'([^']*)'\s*,\s*'([^']*)'", dotAll: true),
    ];
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final code = file.readAsStringSync();
      for (final helper in helpers) {
        for (final m in helper.allMatches(code)) {
          turkish.add(MapEntry<String, String>(file.path, m.group(1)!));
          english.addAll(strip(m.group(2)!).split(splitter).map((w) => w.toLowerCase()));
        }
      }
    }

    // A borrowing keeps breaking harmony once it takes a suffix: "sohbet" is
    // excused, and so "sohbetlere" arrives asking to be excused again. Listing
    // every inflection would grow without end, and simply excusing anything
    // that starts with a listed word gives up too much -- "kitaplari" starts
    // with "kitap" and is genuinely missing its ı.
    //
    // So the stem is excused and its suffixes are not. Turkish suffixes agree
    // with the last vowel of the word they attach to, borrowed or not, which is
    // the actual rule: check from that vowel onward. "sohbetlere" is judged on
    // "etlere" and passes; "kitaplari" on "aplari" and still fails.
    // The present-tense -Iyor carries an invariant o, and everything after it
    // agrees with that o rather than with the stem: gerekiyor, istiyorsunuz.
    // Judging the part before it is the only way to read the stem's own
    // harmony -- and it keeps "araniyor" caught, which is genuinely missing an
    // ı, while excusing the forms that are simply how Turkish conjugates.
    //
    // This rule already existed on the server side of the same guard and was
    // never brought here, so eight -Iyor forms had been added to `known` one at
    // a time instead. A list growing where a rule belongs is the thing this
    // file keeps being written to avoid.
    String beforePresentTense(String word) {
      final int at = word.indexOf('yor');
      return at > 0 ? word.substring(0, at) : word;
    }

    // -abil-/-ebil- is "bilmek" fused onto another verb, and the seam is a real
    // break in harmony: "yazabilirsin" is spelled exactly like that.
    //
    // The part BEFORE it, for the same reason as -Iyor and not by excusing the
    // whole word: "artirabilirsin" is genuinely missing its ı, and a rule that
    // waved through anything containing -abil- would have hidden it. Judged on
    // "artir" it still fails; "yazabilirsin" judged on "yaz" passes.
    String beforeAbility(String word) {
      for (final suffix in <String>['abil', 'ebil']) {
        final int at = word.indexOf(suffix);
        if (at > 0) return word.substring(0, at);
      }
      return word;
    }

    String withoutBorrowedStem(String word) {
      String longest = '';
      for (final stem in known) {
        if (word.length > stem.length &&
            word.startsWith(stem) &&
            stem.length > longest.length) {
          longest = stem;
        }
      }
      if (longest.isEmpty) return word;
      final int lastVowel = longest
          .split('')
          .lastIndexWhere((c) => back.contains(c) || front.contains(c));
      if (lastVowel < 0) return word;
      return word.substring(lastVowel);
    }

    final offenders = <String>{};
    for (final entry in turkish) {
      for (final token in strip(entry.value).split(splitter)) {
        final word = turkishLower(token);
        if (word.length < 5 || known.contains(word)) continue;
        if (english.contains(word)) continue;
        if (foldDiacritics(word) != word) continue;
        final judged =
            beforeAbility(beforePresentTense(withoutBorrowedStem(word)));
        final vowels =
            judged.split('').where((c) => back.contains(c) || front.contains(c)).toList();
        if (vowels.length < 2) continue;
        final mixed = vowels.any(back.contains) && vowels.any(front.contains);
        if (!mixed) continue;
        // Only a/e are stuck where they are; i, o and u each have a partner on
        // the other side, so a word holding both an a and an e cannot be
        // repaired by adding marks and is simply a borrowing.
        if (vowels.contains('a') && vowels.contains('e')) continue;
        offenders.add('  $word   (${entry.key})');
      }
    }

    expect(offenders, isEmpty,
        reason: 'These mix Turkish back and front vowels, which usually means '
            'the diacritics were left out. Fix the word, or add it to `known` '
            'if it is a borrowing:\n${offenders.join('\n')}');
  });

  test('German spells its umlauts, not their ASCII stand-ins', () {
    // German is the third interface language and its block was written half
    // one way and half the other: "Woerter" beside "Wörter", "fuer" beside
    // "für", "zurueck" beside "zurück", "Menue" beside a menu. Thirty-one
    // words appeared in the same file spelled both ways at once. To a German
    // reader "Woerter" reads exactly the way "Turkce" reads to a Turkish one.
    //
    // The Turkish guards can ask the file about itself because stripping a
    // diacritic leaves the letters in place. German expands: ä becomes ae, ß
    // becomes ss. That expansion collides with ordinary words -- neue,
    // zuerst, dasselbe, Aussprache, Flussufer, Kontoeinstellungen -- so a
    // rewrite rule cannot be trusted and neither can a bare "contains ue".
    //
    // So the small side is enumerated instead: the words that legitimately
    // carry one of those pairs. That list is bounded by the vocabulary this
    // app actually uses, a false positive costs one line, and the failure it
    // is here to prevent -- a transliteration nobody notices -- cannot pass.
    final block = RegExp("^    'de': " + r"\{(.*?)^    \},",
            multiLine: true, dotAll: true)
        .firstMatch(source);
    expect(block, isNotNull, reason: 'the German block is gone');

    // ae, oe, ue and ss all belong to these words. Everything else that holds
    // one is an umlaut or an eszett someone typed out.
    const legitimate = <String>{
      'abgeschlossen', 'aktivitätsstatus', 'aktuelle', 'anpassen',
      'assistenten', 'ausgangssprache', 'aussprache', 'aussprachetraining',
      'aussprechen', 'dasselbe', 'erfasst', 'flüssiger', 'flüssigkeit',
      'flussufer', 'fokussieren', 'fokussiert', 'gesprächsfluss', 'gewusst',
      'kontoeinstellungen', 'lassen', 'lässt', 'loslassen', 'manuell',
      'modellaussprache', 'neue', 'neuer', 'neues', 'neueste', 'passen', 'passend',
      'passenden', 'passiert', 'passt', 'passwort', 'passwörter', 'professionelle',
      'schreibassistent', 'sprechassistenten', 'tagesserie', 'tagesset',
      'tagessitzung', 'übersetzungsset', 'übungssprache', 'verbessere',
      'verbessern', 'verbessert', 'vergessen', 'vergisst', 'verpasst',
      'visuellen', 'wissen', 'wochenzusammenfassung', 'zuerst',
    };

    final entry =
        RegExp(r"^\s+'([^']+)':\s*'([^']*)'", multiLine: true, dotAll: true);
    final splitter = RegExp(r'[^A-Za-zäöüÄÖÜß]+');
    final digraph = RegExp('ae|oe|ue|ss');

    var read = 0;
    final offenders = <String>{};
    for (final m in entry.allMatches(block!.group(1)!)) {
      for (final token in m.group(2)!.split(splitter)) {
        if (token.isEmpty) continue;
        read++;
        final word = token.toLowerCase();
        if (!digraph.hasMatch(word)) continue;
        if (legitimate.contains(word)) continue;
        offenders.add('  $word   (${m.group(1)})');
      }
    }

    // A count, because a regex that reads nothing passes every check made of
    // what it read. The German block carries roughly six thousand words.
    expect(read, greaterThan(3000),
        reason: 'the scanner read $read words out of the German block, which '
            'is far too few — it is measuring nothing');

    expect(offenders, isEmpty,
        reason: 'These write out an umlaut or an eszett in ASCII. Fix the '
            'word, or add it to `legitimate` if the pair really belongs to '
            'it:\n${offenders.join('\n')}');
  });

  test('every locale keeps the placeholders its English original has', () {
    // A translation that loses its {n} produces a sentence with the number
    // missing — "Review words" where "Review 7 words" was meant — and every
    // other guard in this file passes it: the key is present, the value is a
    // string, nothing is empty. With four locales translated in one evening
    // and no native reader for any of them, this is the failure most likely
    // to have happened and least likely to be noticed.
    //
    // Reads both quote styles. `login.noAccount` is written with double
    // quotes because its English carries an apostrophe, and a single-quote
    // scanner skips it in silence — which is how 103 wrapped entries went
    // unread by the spelling checks, and how the first draft of this test
    // reported 888 of 889 as clean.
    final entry = RegExp(
        r"""^\s+'([^']+)':\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")""",
        multiLine: true);
    final placeholder = RegExp(r'\{[a-zA-Z]+\}');

    Map<String, String> valuesFor(String language) {
      final block = RegExp("^    '$language': " + r"\{(.*?)^    \},",
              multiLine: true, dotAll: true)
          .firstMatch(source);
      expect(block, isNotNull, reason: 'no translation block for $language');
      final values = <String, String>{};
      for (final m in entry.allMatches(block!.group(1)!)) {
        values[m.group(1)!] = m.group(2) ?? m.group(3) ?? '';
      }
      // Every key, not most of them. A scanner that quietly skips the entries
      // it cannot parse reports the ones it could read as the whole corpus.
      final unread = keysFor(language).difference(values.keys.toSet());
      expect(unread, isEmpty,
          reason: 'these $language values are shaped in a way this scanner '
              'cannot read, so nothing below checked them: $unread');
      return values;
    }

    final english = valuesFor('en');
    final offenders = <String>[];
    for (final locale in AppLocalizations.supportedLocales) {
      if (locale.languageCode == 'en') continue;
      final values = valuesFor(locale.languageCode);
      for (final MapEntry<String, String> e in english.entries) {
        final want = placeholder.allMatches(e.value).map((m) => m[0]!).toSet();
        final got =
            placeholder.allMatches(values[e.key] ?? '').map((m) => m[0]!).toSet();
        if (want.difference(got).isNotEmpty || got.difference(want).isNotEmpty) {
          offenders.add('  ${locale.languageCode}  ${e.key}\n'
              '      en: ${e.value}\n'
              '      ${locale.languageCode}: ${values[e.key]}');
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'These carry different placeholders from their English '
            'original, so the value they stand for goes missing or a raw '
            '{brace} reaches the screen:\n${offenders.join('\n')}');
  });
}
