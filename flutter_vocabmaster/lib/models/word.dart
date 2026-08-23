import 'word_meaning.dart';

export 'word_meaning.dart';

class Word {
  final int id;
  final String englishWord;
  final String turkishMeaning;
  String get sourceMeaning => turkishMeaning;

  /// The senses of this word, in server order. Empty against a backend that does not
  /// send them yet; [turkishMeaning] remains the denormalised copy either way.
  final List<WordMeaning> meanings;

  /// The language profile this word belongs to. Null from an older backend.
  final int? languageProfileId;

  /// Where the word came from: 'daily_words' or 'manual'. Null from an older backend,
  /// in which case the marker inside [turkishMeaning] still answers the question.
  final String? origin;

  /// Was this word added from Daily Words?
  ///
  /// That fact is stored by prefixing the translation itself with a star, so the meaning
  /// field carries both the meaning and where it came from. Every screen that shows a
  /// translation therefore has to know to strip it, and the review card — the screen a
  /// learner sees most — did not: a word added from Daily Words was displayed as
  /// "⭐ içgörü", star and all.
  ///
  /// Reading it here means no caller has to remember. [displayMeaning] is what belongs on
  /// screen and in anything read aloud; this flag is what belongs behind a star icon.
  ///
  /// The server now stores provenance as [origin]; when it is present it wins over the
  /// marker, so a word whose meaning was edited clean keeps its star.
  bool get isFromDailyWords {
    final source = origin?.trim();
    if (source != null && source.isNotEmpty) {
      return source == 'daily_words';
    }
    return turkishMeaning.contains('⭐') || turkishMeaning.contains('★');
  }

  /// The translation with the provenance marker removed, safe to show or speak.
  ///
  /// Built from [meanings] when the server sent them, so an edit through the meaning
  /// endpoints shows up even if the joined string lags; otherwise the stripped
  /// [turkishMeaning].
  String get displayMeaning {
    final fromMeanings = meanings
        .map((m) => m.translation.trim())
        .where((t) => t.isNotEmpty)
        .join(', ');
    if (fromMeanings.isNotEmpty) return fromMeanings;
    return turkishMeaning.replaceAll('⭐', '').replaceAll('★', '').trim();
  }

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
    this.meanings = const [],
    this.languageProfileId,
    this.origin,
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

    int? parseNullableInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString());
    }

    final rawOrigin = json['origin']?.toString().trim();

    return Word(
      id: wordId,
      englishWord: json['englishWord'] as String? ?? '',
      turkishMeaning:
          (json['sourceMeaning'] ?? json['turkishMeaning'])?.toString() ?? '',
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
      meanings: (json['meanings'] as List<dynamic>?)
              ?.map((m) {
                try {
                  return WordMeaning.fromJson(m as Map<String, dynamic>);
                } catch (e) {
                  return null;
                }
              })
              .whereType<WordMeaning>()
              .toList() ??
          [],
      languageProfileId: parseNullableInt(json['languageProfileId']),
      origin: (rawOrigin == null || rawOrigin.isEmpty) ? null : rawOrigin,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'englishWord': englishWord,
      'turkishMeaning': turkishMeaning,
      'sourceMeaning': sourceMeaning,
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
      'meanings': meanings.map((m) => m.toJson()).toList(),
      if (languageProfileId != null) 'languageProfileId': languageProfileId,
      if (origin != null) 'origin': origin,
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

  /// The meaning this sentence illustrates. Null means "unassigned": the server does
  /// not know which sense it was written for, and the UI treats it as all of them.
  final int? meaningId;

  Sentence({
    required this.id,
    required this.sentence,
    required this.translation,
    required this.wordId,
    this.difficulty,
    this.createdAt,
    this.meaningId,
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

    int? meaningId;
    final meaningIdRaw = json['meaningId'];
    if (meaningIdRaw is int) {
      meaningId = meaningIdRaw;
    } else if (meaningIdRaw is num) {
      meaningId = meaningIdRaw.toInt();
    } else if (meaningIdRaw != null) {
      meaningId = int.tryParse(meaningIdRaw.toString());
    }

    return Sentence(
      id: (json['id'] is int) ? json['id'] as int : (json['id'] as num).toInt(),
      sentence: json['sentence'] as String? ?? '',
      translation:
          (json['sourceTranslation'] ?? json['translation'])?.toString() ?? '',
      wordId: wordId,
      difficulty: json['difficulty'] as String?,
      createdAt: createdAt,
      meaningId: meaningId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sentence': sentence,
      'translation': translation,
      'sourceTranslation': translation,
      'wordId': wordId,
      'difficulty': difficulty,
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      if (meaningId != null) 'meaningId': meaningId,
    };
  }
}
