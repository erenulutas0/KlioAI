
class TopicData {
  final String topic;
  final String description;
  final String level;
  final String wordCount;
  
  TopicData({
    required this.topic,
    required this.description,
    required this.level,
    required this.wordCount,
  });

  factory TopicData.fromJson(Map<String, dynamic> json) {
    return TopicData(
      topic: (json['topic'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      level: (json['level'] ?? '').toString(),
      wordCount: (json['wordCount'] ?? '').toString(),
    );
  }
}

class EvaluationData {
  final int score;
  final List<String> strengths;
  final List<String> improvements;
  final String grammar;
  final String vocabulary;
  final String coherence;
  final String overall;
  final String contextRelevance;

  /// True when the backend could not evaluate the writing and answered with its stand-in
  /// payload. That payload carries score 0, which is not a judgement of the learner's text
  /// — it is the absence of one. The flag was already being sent and simply never read, so
  /// a transient AI failure wrote a permanent zero into the user's writing history and
  /// showed it to them as "your score out of 100".
  final bool isFallback;

  EvaluationData({
    required this.score,
    required this.strengths,
    required this.improvements,
    required this.grammar,
    required this.vocabulary,
    required this.coherence,
    required this.overall,
    required this.contextRelevance,
    this.isFallback = false,
  });

  factory EvaluationData.fromJson(Map<String, dynamic> json) {
    return EvaluationData(
      isFallback: json['fallback'] == true,
      score: json['score'] ?? 0,
      strengths: List<String>.from(json['strengths'] ?? []),
      improvements: List<String>.from(json['improvements'] ?? []),
      grammar: json['grammar'] ?? '',
      vocabulary: json['vocabulary'] ?? '',
      coherence: json['coherence'] ?? '',
      overall: json['overall'] ?? '',
      contextRelevance: json['contextRelevance'] ?? '',
    );
  }
}
