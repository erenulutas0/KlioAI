import '../models/exam_models.dart';
import '../models/writing_practice_models.dart';
import 'api_service.dart';

/// All AI features are proxied via backend so daily token quota (50k/user/day)
/// and rate limits can be enforced centrally.
///
/// Historical name kept to avoid touching many call sites.
class GroqService {
  static final ApiService _api = ApiService();

  /// Kelime anlamlarını, bağlamlarını ve örnek cümleleri getirir
  static Future<Map<String, dynamic>?> lookupWord(String word) async {
    return await _api.chatbotDictionaryLookup(word: word);
  }

  /// Kelime anlamlarını DETAYLI olarak getirir - türler (n/v/adj/adv) ile birlikte
  static Future<Map<String, dynamic>> lookupWordDetailed(String word) async {
    return await _api.chatbotDictionaryLookupDetailed(word: word);
  }

  /// Belirli bir anlam için yeni örnek cümle üretir
  static Future<String> generateSpecificSentence({
    required String word,
    required String translation,
    required String context,
  }) async {
    try {
      final result = await _api.chatbotDictionaryGenerateSpecificSentence(
        word: word,
        translation: translation,
        context: context,
      );
      return result['sentence']?.toString() ?? 'Cümle oluşturulamadı.';
    } catch (_) {
      return 'Cümle oluşturulamadı.';
    }
  }

  /// Cümle içinde kelimenin anlamını açıklar
  static Future<String> explainWordInSentence(String word, String sentence) async {
    try {
      final result = await _api.chatbotDictionaryExplainWordInSentence(
        word: word,
        sentence: sentence,
      );
      return result['definition']?.toString() ?? 'Anlam bulunamadı.';
    } catch (_) {
      return 'Anlam bulunamadı.';
    }
  }

  /// Okuma parçası üretir (IELTS/TOEFL tarzı)
  static Future<Map<String, dynamic>> generateReadingPassage(String level) async {
    return await _api.chatbotGenerateReadingPassage(level: level);
  }

  /// Writing konusu üretir
  static Future<TopicData> generateWritingTopic(String level, String wordCount) async {
    final result = await _api.chatbotGenerateWritingTopic(
      level: level,
      wordCount: wordCount,
    );
    return TopicData.fromJson(result);
  }

  /// Writing değerlendirir
  static Future<EvaluationData> evaluateWriting(String text, String level, TopicData topic) async {
    final result = await _api.chatbotEvaluateWriting(
      text: text,
      level: level,
      topic: {
        'topic': topic.topic,
        'description': topic.description,
        'level': topic.level,
        'wordCount': topic.wordCount,
      },
    );
    return EvaluationData.fromJson(result);
  }

  /// YDS/YÖKDİL sınavı üretir
  static Future<ExamBundle> generateExamBundle({
    required String examType,
    required String mode,
    String? category,
    int questionCount = 10,
    String? track,
    String userLevel = "B2",
    String targetScore = "60-80",
  }) async {
    final result = await _api.chatbotGenerateExamBundle(
      examType: examType,
      mode: mode,
      category: category ?? 'grammar',
      track: track ?? 'general',
      questionCount: questionCount,
      userLevel: userLevel,
      targetScore: targetScore,
    );
    return ExamBundle.fromJson(result);
  }
}

