class Word {
  final int id;
  final String englishWord;
  final String turkishMeaning;
  final DateTime learnedDate;
  final String? notes;
  final String difficulty;
  final List<Sentence> sentences;

  Word({
    required this.id,
    required this.englishWord,
    required this.turkishMeaning,
    required this.learnedDate,
    this.notes,
    required this.difficulty,
    this.sentences = const [],
  });

  factory Word.fromJson(Map<String, dynamic> json) {
    // Null-safe parsing
    final id = json['id'];
    final wordId = (id is int) ? id : (id is num) ? id.toInt() : 0;
    
    return Word(
      id: wordId,
      englishWord: json['englishWord'] as String? ?? '',
      turkishMeaning: json['turkishMeaning'] as String? ?? '',
      learnedDate: json['learnedDate'] != null 
          ? DateTime.parse(json['learnedDate'].toString())
          : DateTime.now(),
      notes: json['notes'] as String?,
      difficulty: json['difficulty'] as String? ?? 'easy',
      sentences: (json['sentences'] as List<dynamic>?)
          ?.map((s) {
            try {
              return Sentence.fromJson(s as Map<String, dynamic>);
            } catch (e) {
              // Hatalı sentence'ı atla
              return null;
            }
          })
          .whereType<Sentence>()
          .toList() ?? [],
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
    // wordId'yi word objesinden veya direkt wordId alanından al
    int wordId = 0;
    if (json['wordId'] != null) {
      final wordIdValue = json['wordId'];
      wordId = (wordIdValue is int) ? wordIdValue : (wordIdValue is num) ? wordIdValue.toInt() : 0;
    } else if (json['word'] != null && json['word'] is Map) {
      final wordData = json['word'] as Map<String, dynamic>;
      final wordIdValue = wordData['id'];
      wordId = (wordIdValue is int) ? wordIdValue : (wordIdValue is num) ? wordIdValue.toInt() : 0;
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
