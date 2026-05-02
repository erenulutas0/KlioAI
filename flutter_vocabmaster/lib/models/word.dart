class Word {
  final int id;
  final String englishWord;
  final String turkishMeaning;
  final DateTime learnedDate;
  final String? notes;
  final String difficulty;
  final DateTime? nextReviewDate;
  final int reviewCount;
  final double? easeFactor;
  final DateTime? lastReviewDate;
  final List<Sentence> sentences;

  Word({
    required this.id,
    required this.englishWord,
    required this.turkishMeaning,
    required this.learnedDate,
    this.notes,
    required this.difficulty,
    this.nextReviewDate,
    this.reviewCount = 0,
    this.easeFactor,
    this.lastReviewDate,
    this.sentences = const [],
  });

  factory Word.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final wordId = (id is int)
        ? id
        : (id is num)
            ? id.toInt()
            : 0;

    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      return DateTime.tryParse(value.toString());
    }

    int parseInt(dynamic value, {int fallback = 0}) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? fallback;
    }

    double? parseDouble(dynamic value) {
      if (value == null) return null;
      if (value is double) return value;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString());
    }

    return Word(
      id: wordId,
      englishWord: json['englishWord'] as String? ?? '',
      turkishMeaning: json['turkishMeaning'] as String? ?? '',
      learnedDate: json['learnedDate'] != null
          ? DateTime.parse(json['learnedDate'].toString())
          : DateTime.now(),
      notes: json['notes'] as String?,
      difficulty: json['difficulty'] as String? ?? 'easy',
      nextReviewDate: parseDate(json['nextReviewDate']),
      reviewCount: parseInt(json['reviewCount']),
      easeFactor: parseDouble(json['easeFactor']),
      lastReviewDate: parseDate(json['lastReviewDate']),
      sentences: (json['sentences'] as List<dynamic>?)
              ?.map((s) {
                try {
                  return Sentence.fromJson(s as Map<String, dynamic>);
                } catch (e) {
                  return null;
                }
              })
              .whereType<Sentence>()
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'englishWord': englishWord,
      'turkishMeaning': turkishMeaning,
      'learnedDate': learnedDate.toIso8601String().split('T')[0],
      'notes': notes,
      'difficulty': difficulty,
      if (nextReviewDate != null)
        'nextReviewDate': nextReviewDate!.toIso8601String().split('T')[0],
      'reviewCount': reviewCount,
      if (easeFactor != null) 'easeFactor': easeFactor,
      if (lastReviewDate != null)
        'lastReviewDate': lastReviewDate!.toIso8601String().split('T')[0],
      'sentences': sentences.map((s) => s.toJson()).toList(),
    };
  }
}

class Sentence {
  final int id;
  final String sentence;
  final String translation;
  final int wordId;
  final String? difficulty;
  final DateTime? createdAt;

  Sentence({
    required this.id,
    required this.sentence,
    required this.translation,
    required this.wordId,
    this.difficulty,
    this.createdAt,
  });

  factory Sentence.fromJson(Map<String, dynamic> json) {
    int wordId = 0;
    if (json['wordId'] != null) {
      final wordIdValue = json['wordId'];
      wordId = (wordIdValue is int)
          ? wordIdValue
          : (wordIdValue is num)
              ? wordIdValue.toInt()
              : 0;
    } else if (json['word'] != null && json['word'] is Map) {
      final wordData = json['word'] as Map<String, dynamic>;
      final wordIdValue = wordData['id'];
      wordId = (wordIdValue is int)
          ? wordIdValue
          : (wordIdValue is num)
              ? wordIdValue.toInt()
              : 0;
    }

    DateTime? createdAt;
    final createdAtRaw = json['createdAt'];
    if (createdAtRaw != null) {
      createdAt = DateTime.tryParse(createdAtRaw.toString());
    }

    return Sentence(
      id: (json['id'] is int) ? json['id'] as int : (json['id'] as num).toInt(),
      sentence: json['sentence'] as String? ?? '',
      translation: json['translation'] as String? ?? '',
      wordId: wordId,
      difficulty: json['difficulty'] as String?,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sentence': sentence,
      'translation': translation,
      'wordId': wordId,
      'difficulty': difficulty,
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    };
  }
}
