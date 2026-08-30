import 'package:flutter/material.dart';

/// Grammar konu modeli
class GrammarTopic {
  final String id;
  final String title;
  final String titleTr;
  final String level; // 'core', 'advanced', 'exam', 'bonus'
  final IconData icon;
  final Color color;
  final List<GrammarSubtopic> subtopics;

  const GrammarTopic({
    required this.id,
    required this.title,
    required this.titleTr,
    required this.level,
    required this.icon,
    required this.color,
    required this.subtopics,
  });
}

/// Grammar alt konu modeli
class GrammarSubtopic {
  final String id;
  final String title;
  final String titleTr;
  final String explanation; // Türkçe açıklama

  /// The same explanation written in English, for the six interface languages
  /// that are not Turkish.
  ///
  /// [explanation] is the body of the guide and it is Turkish, so the screen
  /// has never shown it to anyone else. What they got instead was one generic
  /// sentence -- "Present Simple is an English grammar pattern. Check the
  /// formula below" -- identical on all eighty-three subtopics. The app offers
  /// seven interface languages and taught in one.
  ///
  /// Null means no English has been written yet, and the screen falls back to
  /// that generic sentence as before. `grammar_explanation_test` counts how
  /// many are still null, so the gap is a number that has to go down rather
  /// than a silence.
  final String? explanationEn;
  final String formula; // Yapı/formül

  /// The same formula written in English, for the six interface languages
  /// that are not Turkish.
  ///
  /// [formula] is Turkish data — forty-five of the eighty-three carry Turkish
  /// words, from "Olumlu / Olumsuz / Soru" as labels to whole rule lines like
  /// "Sessiz harf + y: y→ies". Those were shown to Spanish, Portuguese,
  /// Italian, French, German and English readers exactly as written.
  ///
  /// Null where the formula is already notation any learner can read
  /// ("Subject + get/got + V3"). `grammar_formula_language_test` fails on a
  /// Turkish formula that has no English beside it, so a new subtopic cannot
  /// quietly reintroduce the problem.
  final String? formulaEn;
  final List<GrammarExample> examples;
  final List<String> commonMistakes;

  /// The same mistakes in English, for the six interface languages that are
  /// not Turkish.
  ///
  /// Needed for far fewer subtopics than it looks. Of 209 entries only 32
  /// carry any Turkish: the rest are already wrong-then-right pairs in plain
  /// English -- "❌ She studys hard. → ✅ She studies hard." -- and were hidden
  /// from everyone but Turkish readers for no reason at all. Where this is
  /// null those originals are shown as they are.
  final List<String>? commonMistakesEn;
  final String? examTip;
  final String? comparison; // Karışabilecek konularla karşılaştırma
  final List<String>? keyPoints; // Can alıcı noktalar

  /// The same key points in English, for the six interface languages that are
  /// not Turkish.
  ///
  /// Unlike the common mistakes, these really are Turkish: 244 of 297 lines.
  /// They were worth measuring before assuming either way -- the mistake
  /// lists turned out to need almost nothing.
  final List<String>? keyPointsEn;

  /// The formula to put in front of a reader of [languageCode].
  ///
  /// Turkish readers get the Turkish one, which is what this data was written
  /// as. Everyone else gets the English one when there is one, and the
  /// original when there is not — which happens only where the original is
  /// already language-neutral notation.
  String formulaFor(String languageCode) =>
      languageCode == 'tr' ? formula : (formulaEn ?? formula);

  /// The explanation to put in front of a reader of [languageCode], or null
  /// when there is nothing to show them but the generic framing sentence.
  ///
  /// Turkish readers get the Turkish one, which is what this data was written
  /// as and what its whole audience reads today.
  String? explanationFor(String languageCode) =>
      languageCode == 'tr' ? explanation : explanationEn;

  /// The common mistakes to show a reader of [languageCode].
  ///
  /// Turkish readers get the originals. Everyone else gets the English list
  /// where one was needed, and the originals where they were already English.
  List<String> commonMistakesFor(String languageCode) =>
      languageCode == 'tr' ? commonMistakes : (commonMistakesEn ?? commonMistakes);

  /// The key points to show a reader of [languageCode], or an empty list when
  /// there is nothing written for them.
  List<String> keyPointsFor(String languageCode) => languageCode == 'tr'
      ? (keyPoints ?? const <String>[])
      : (keyPointsEn ?? const <String>[]);

  const GrammarSubtopic({
    required this.id,
    required this.title,
    required this.titleTr,
    required this.explanation,
    this.explanationEn,
    required this.formula,
    this.formulaEn,
    required this.examples,
    this.commonMistakes = const [],
    this.commonMistakesEn,
    this.examTip,
    this.comparison,
    this.keyPoints,
    this.keyPointsEn,
  });
}

/// Örnek cümle modeli
class GrammarExample {
  final String english;
  final String turkish;
  final bool isCorrect;
  final String? note;

  const GrammarExample({
    required this.english,
    required this.turkish,
    this.isCorrect = true,
    this.note,
  });
}

/// Seviye renkleri
class GrammarLevelColors {
  static const Color core = Color(0xFF22c55e);
  static const Color advanced = Color(0xFFf59e0b);
  static const Color exam = Color(0xFFef4444);
  static const Color bonus = Color(0xFF8b5cf6);
  
  static Color getColor(String level) {
    switch (level) {
      case 'core': return core;
      case 'advanced': return advanced;
      case 'exam': return exam;
      case 'bonus': return bonus;
      default: return core;
    }
  }
  
  static String getLabel(String level) {
    switch (level) {
      case 'core': return 'Temel';
      case 'advanced': return 'İleri';
      case 'exam': return 'Sınav';
      case 'bonus': return 'Bonus';
      default: return level;
    }
  }
}
