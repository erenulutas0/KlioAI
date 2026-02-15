class SentencePractice {
  final String id;
  final String englishSentence;
  final String turkishTranslation;
  final String difficulty;
  final DateTime? createdDate;
  final String source;
  final String? word;
  final String? wordTranslation;

  SentencePractice({
    required this.id,
    required this.englishSentence,
    required this.turkishTranslation,
    required this.difficulty,
    this.createdDate,
    required this.source,
    this.word,
    this.wordTranslation,
  });

  factory SentencePractice.fromJson(Map<String, dynamic> json) {
    String id;
    if (json['id'] is String) {
      id = json['id'] as String;
    } else {
      id = '${json['source'] ?? 'practice'}_${json['id']}';
    }

    final englishSentence =
        (json['englishSentence'] ?? json['sentence'])?.toString() ?? '';
    final turkishTranslation =
        (json['turkishTranslation'] ?? json['translation'])?.toString() ?? '';
    final difficulty = json['difficulty']?.toString() ?? 'easy';
    final source = json['source']?.toString() ?? 'practice';
    DateTime? createdDate;
    final rawCreatedDate = json['createdDate'];
    if (rawCreatedDate != null) {
      try {
        createdDate = DateTime.parse(rawCreatedDate.toString());
      } catch (_) {
        createdDate = null;
      }
    }

    return SentencePractice(
      id: id,
      englishSentence: englishSentence,
      turkishTranslation: turkishTranslation,
      difficulty: difficulty,
      createdDate: createdDate,
      source: source,
      word: json['word']?.toString(),
      wordTranslation: json['wordTranslation']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'englishSentence': englishSentence,
      'turkishTranslation': turkishTranslation,
      'difficulty': difficulty,
      'createdDate': createdDate?.toIso8601String().split('T')[0],
      'source': source,
      'word': word,
      'wordTranslation': wordTranslation,
    };
  }

  int get numericId {
    try {
      return int.parse(id.split('_').last);
    } catch (e) {
      return 0;
    }
  }
}
