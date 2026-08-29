/// Whether a grammar formula can be shown to someone who does not read
/// Turkish.
///
/// The subtopic guides are Turkish data. The screen already knows that: the
/// long `explanation` is shown only to Turkish readers, and so are the key
/// points, the common mistakes and the exam tip. The formula was assumed to be
/// language-neutral notation and was shown to everyone.
///
/// It is not. Forty-five of the eighty-three carry Turkish — thirty-one with
/// Turkish letters in a rule line, the rest with Turkish words inside English
/// notation: `Olumlu / Olumsuz / Soru` as labels, `HAVE + NESNE + V3`,
/// `(to yok)`, `(Could/Might da gelebilir)`. A Spanish reader opening Present
/// Simple was handed
///
///     ➕ Olumlu: Subject + V1 (he/she/it için +s/es)
///     ⚠️ 3. tekil şahıs kuralları:
///
/// The other thirty-eight are pure notation — `Subject + get/got + V3` — and are as
/// readable in Madrid as in Ankara. Those keep being shown; the rest
/// are withheld from the locales that cannot read them, exactly as the
/// explanation already is.
///
/// Withholding rather than translating is the smaller claim. Rewriting the
/// forty-five in English would take something away from the readers this app
/// actually has to give it to the ones it hopes for; translating them into six
/// languages is a content project, not a fix. Both remain open; neither has to
/// happen before a Spanish reader stops being shown Turkish.
library;

class GrammarFormulaLanguage {
  const GrammarFormulaLanguage._();

  /// Letters that exist in Turkish and not in English.
  ///
  /// `ö` and `ü` are also German, and `ç` is also French — which is the point:
  /// a formula holding one of them was written for a reader of some language,
  /// and the only language this data was written in is Turkish.
  static final RegExp _turkishLetters = RegExp('[çğıöşüÇĞİÖŞÜ]');

  /// The Turkish words that appear in formulas written in plain ASCII.
  ///
  /// A list, and lists are what this codebase keeps getting wrong. Two
  /// attempts to make it check itself against a dictionary of known Turkish
  /// both failed — see `grammar_formula_language_test` — so all eighty-three
  /// formulas were read instead. That reading is what found NESNE, "to yok",
  /// "opsiyonel" and "de/da gelebilir": five English-looking formulas with
  /// Turkish buried in them, which no letter-based rule can see. The test
  /// pins the result of that reading rather than pretending to re-derive it.
  static final RegExp _turkishWords = RegExp(
    r'\b(Olumlu|Olumsuz|Soru|Kural|Yapi|Zaman|Cumle|Ornek|Nesne|yok|opsiyonel|gelebilir|olur|olmaz)\b',
    caseSensitive: false,
  );

  /// True when the formula is notation any learner can read.
  static bool isLanguageNeutral(String formula) {
    return !_turkishLetters.hasMatch(formula) &&
        !_turkishWords.hasMatch(formula);
  }

  /// Whether this formula should be drawn for a reader of [languageCode].
  ///
  /// Turkish readers see every formula; everyone else sees the ones that carry
  /// no Turkish.
  static bool showTo(String languageCode, String formula) {
    return languageCode == 'tr' || isLanguageNeutral(formula);
  }
}
