
/// Returns [value] only when it is a positive number, otherwise [fallback].
///
/// Written for `time_limit_minutes`: the backend's stand-in exam payload sends 0, and a
/// plain `?? 180` accepts it because 0 is not null. That produced a timer of zero seconds
/// which ended the exam immediately, on an exam that had no questions in it either.
int _positiveOr(dynamic value, int fallback) {
  if (value is num && value > 0) {
    return value.toInt();
  }
  return fallback;
}

class ExamBundle {
  final ExamMeta meta;
  final List<ExamSection> sections;

  ExamBundle({required this.meta, required this.sections});

  factory ExamBundle.fromJson(Map<String, dynamic> json) {
    return ExamBundle(
      meta: ExamMeta.fromJson(json['meta']),
      sections: (json['sections'] as List)
          .map((e) => ExamSection.fromJson(e))
          .toList(),
    );
  }
}

class ExamMeta {
  final String exam; // YDS, YOKDIL
  final String mode; // full_exam, mini_test
  final String? track; // fen, saglik, sosyal
  final String? userLevelCefr;
  final String? targetScoreBand;
  final int timeLimitMinutes;
  final int totalQuestions;

  ExamMeta({
    required this.exam,
    required this.mode,
    this.track,
    this.userLevelCefr,
    this.targetScoreBand,
    required this.timeLimitMinutes,
    required this.totalQuestions,
  });

  factory ExamMeta.fromJson(Map<String, dynamic> json) {
    return ExamMeta(
      exam: json['exam'],
      mode: json['mode'],
      track: json['track'],
      userLevelCefr: json['user_level_cefr'],
      targetScoreBand: json['target_score_band'],
      // `??` only catches null. The backend's stand-in exam payload sends 0, which slipped
      // through and became a zero-length timer that ended the exam a second after it
      // started. Treat a non-positive limit as missing.
      timeLimitMinutes: _positiveOr(json['time_limit_minutes'], 180),
      totalQuestions: json['total_questions'] ?? 0,
    );
  }
}

class ExamSection {
  final String name; // vocab, grammar, reading...
  final List<ExamItem> items;

  ExamSection({required this.name, required this.items});

  factory ExamSection.fromJson(Map<String, dynamic> json) {
    return ExamSection(
      name: json['name'],
      items: (json['items'] as List)
          .map((e) => ExamItem.fromJson(e))
          .toList(),
    );
  }
}

class ExamItem {
  final String id;
  final String type;
  final String difficulty;
  final List<String> skillTags;
  final String stem;
  final String? passage; // Shared passage text for cloze/reading
  final Map<String, String> options;
  final String correct;
  final String? explanationTr;
  final String? explanationEn;

  ExamItem({
    required this.id,
    required this.type,
    required this.difficulty,
    required this.skillTags,
    required this.stem,
    this.passage,
    required this.options,
    required this.correct,
    this.explanationTr,
    this.explanationEn,
  });

  factory ExamItem.fromJson(Map<String, dynamic> json) {
    return ExamItem(
      id: json['id'] ?? '',
      type: json['type'] ?? '',
      difficulty: json['difficulty'] ?? 'medium',
      skillTags: (json['skill_tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
      stem: json['stem'] ?? '',
      passage: json['passage'],
      options: Map<String, String>.from(json['options'] ?? {}),
      correct: json['correct'] ?? '',
      explanationTr: json['explanation_tr'],
      explanationEn: json['explanation_en'],
    );
  }
}
