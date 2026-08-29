/// Whether a grammar formula was written in Turkish.
///
/// The subtopic guides are Turkish data. The screen has always known that: the
/// long `explanation`, the key points, the common mistakes and the exam tip
/// are shown to Turkish readers only. The formula was assumed to be
/// language-neutral notation and was shown to everyone.
///
/// It is not. Forty-five of the eighty-three carry Turkish — Turkish letters
/// in a rule line, or Turkish words inside English notation: `Olumlu /
/// Olumsuz / Soru` as labels, `HAVE + NESNE + V3`, `(to yok)`,
/// `(Could/Might da gelebilir)`. A Spanish reader opening Present Simple was
/// handed
///
///     ➕ Olumlu: Subject + V1 (he/she/it için +s/es)
///     ⚠️ 3. tekil şahıs kuralları:
///
/// Each of those forty-five now carries a `formulaEn` beside it, and
/// `GrammarSubtopic.formulaFor` picks by language: Turkish readers keep the
/// Turkish, everyone else gets the English. Nothing is withheld.
///
/// So this class no longer decides what to draw. Its only job is to answer
/// "was this written in Turkish", which is the question
/// `grammar_formula_language_test` asks of every subtopic: a Turkish formula
/// with no English beside it fails, so a subtopic added later cannot quietly
/// put Turkish back in front of the other six languages.
library;

class GrammarFormulaLanguage {
  const GrammarFormulaLanguage._();

  /// Letters that exist in Turkish and not in English.
  ///
  /// `ö` and `ü` are also German and `ç` is also French — which is the point:
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
  /// Turkish buried in them, which no letter-based rule can see.
  static final RegExp _turkishWords = RegExp(
    r'\b(Olumlu|Olumsuz|Soru|Kural|Yapi|Zaman|Cumle|Ornek|Nesne|yok'
    r'|opsiyonel|gelebilir|olur|olmaz)\b',
    caseSensitive: false,
  );

  /// True when the formula is notation any learner can read.
  static bool isLanguageNeutral(String formula) {
    return !_turkishLetters.hasMatch(formula) &&
        !_turkishWords.hasMatch(formula);
  }
}
