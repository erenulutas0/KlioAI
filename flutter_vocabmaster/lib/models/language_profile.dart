/// A learner's (source language → target language) pairing with its level and goal.
///
/// A user has one or more of these and exactly one is active; every word belongs to
/// one. The server returns them from `GET /api/language-profiles`.
class LanguageProfile {
  final int id;
  final String sourceLanguage;
  final String targetLanguage;
  final String level;
  final String? learningGoal;
  final bool isActive;
  final DateTime? createdAt;

  const LanguageProfile({
    required this.id,
    required this.sourceLanguage,
    required this.targetLanguage,
    this.level = 'B1',
    this.learningGoal,
    this.isActive = false,
    this.createdAt,
  });

  factory LanguageProfile.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value, {int fallback = 0}) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? fallback;
    }

    bool parseBool(dynamic value) {
      if (value is bool) return value;
      if (value is num) return value != 0;
      final text = value?.toString().trim().toLowerCase();
      return text == 'true' || text == '1';
    }

    final level = json['level']?.toString().trim();
    final goal = json['learningGoal']?.toString().trim();

    return LanguageProfile(
      id: parseInt(json['id']),
      sourceLanguage: json['sourceLanguage']?.toString() ?? '',
      targetLanguage: json['targetLanguage']?.toString() ?? '',
      level: (level == null || level.isEmpty) ? 'B1' : level,
      learningGoal: (goal == null || goal.isEmpty) ? null : goal,
      isActive: parseBool(json['isActive']),
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.tryParse(json['createdAt'].toString()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sourceLanguage': sourceLanguage,
      'targetLanguage': targetLanguage,
      'level': level,
      'learningGoal': learningGoal,
      'isActive': isActive,
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    };
  }
}
