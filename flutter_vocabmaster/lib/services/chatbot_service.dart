import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'groq_api_client.dart';

/// Chatbot servisi
/// - Core AI flows (chat/translation/sentence generation/speaking) go through backend to enforce quotas.
/// - Some legacy generators still call Groq directly (BYOK) until backend endpoints are added.
class ChatbotService {
  final ApiService _api = ApiService();

  /// Kelime için pratik cümleleri üretir (BACKEND - kota uygulanır)
  Future<Map<String, dynamic>> generateSentences({
    required String word,
    List<String> levels = const ['B1'],
    List<String> lengths = const ['medium'],
    bool checkGrammar = false,
    bool fresh = false,
  }) async {
    try {
      return await _api.chatbotGenerateSentences(
        word: word,
        levels: levels,
        lengths: lengths,
        checkGrammar: checkGrammar,
        fresh: fresh,
      );
    } catch (e) {
      debugPrint('ChatbotService.generateSentences error: $e');
      rethrow;
    }
  }

  /// Kullanıcının çevirisini kontrol eder (BACKEND - kota uygulanır)
  Future<Map<String, dynamic>> checkTranslation({
    required String originalSentence,
    required String userTranslation,
    required String direction, // 'EN_TO_TR' or 'TR_TO_EN'
    String? referenceSentence,
  }) async {
    try {
      if (direction == 'TR_TO_EN') {
        return await _api.chatbotCheckTranslation(
          direction: direction,
          userTranslation: userTranslation,
          turkishSentence: originalSentence,
          referenceEnglishSentence: referenceSentence,
        );
      }

      return await _api.chatbotCheckTranslation(
        direction: direction,
        userTranslation: userTranslation,
        englishSentence: originalSentence,
      );
    } catch (e) {
      debugPrint('ChatbotService.checkTranslation error: $e');
      rethrow;
    }
  }

  /// AI Bot ile sohbet (BACKEND - kota uygulanır)
  /// [scenario] parametresi ile profesyonel senaryolar desteklenir
  /// [scenarioContext] ile senaryoya özel bağlam (örn: pozisyon adı, sunum konusu) eklenir
  Future<String> chat(String message, {String? scenario, String? scenarioContext}) async {
    try {
      return await _api.chatbotChat(
        message: message,
        scenario: scenario,
        scenarioContext: scenarioContext,
      );
    } catch (e) {
      debugPrint('ChatbotService.chat error: $e');
      rethrow;
    }
  }

  /// Kelimeyi bugüne kaydet - BACKEND API (kelime kaydetme işlemi için)
  Future<Map<String, dynamic>> saveWordToToday({
    required String englishWord,
    List<String> meanings = const [],
    List<String> sentences = const [],
  }) async {
    try {
      return await _api.chatbotSaveWordToToday(
        englishWord: englishWord,
        meanings: meanings,
        sentences: sentences,
      );
    } catch (e) {
      debugPrint('ChatbotService.saveWordToToday error: $e');
      rethrow;
    }
  }

  /// IELTS/TOEFL Speaking test soruları oluştur (BACKEND - kota uygulanır)
  Future<Map<String, dynamic>> generateSpeakingTestQuestions({
    required String testType, // 'IELTS' or 'TOEFL'
    required String part,
  }) async {
    try {
      final result = await _api.chatbotGenerateSpeakingTestQuestions(
        testType: testType,
        part: part,
      );

      // UI compatibility: ensure `question` exists.
      if (!result.containsKey('question') &&
          result['questions'] is List &&
          (result['questions'] as List).isNotEmpty) {
        result['question'] = (result['questions'] as List).first.toString();
      }

      return result;
    } catch (e) {
      debugPrint('ChatbotService.generateSpeakingTestQuestions error: $e');
      rethrow;
    }
  }

  /// Speaking test cevabını değerlendir (BACKEND - kota uygulanır)
  Future<Map<String, dynamic>> evaluateSpeakingTest({
    required String testType,
    required String question,
    required String response,
  }) async {
    try {
      final server = await _api.chatbotEvaluateSpeakingTest(
        testType: testType,
        question: question,
        responseText: response,
      );

      // Normalize backend schema to older UI expectations.
      final normalized = Map<String, dynamic>.from(server);
      final overall = normalized['overallScore'];
      if (!normalized.containsKey('score') && overall != null) {
        normalized['score'] = overall;
      }
      if (!normalized.containsKey('band') && overall != null) {
        normalized['band'] = overall.toString();
      }
      if (!normalized.containsKey('suggestions')) {
        final improvements = normalized['improvements'];
        if (improvements is List) {
          normalized['suggestions'] = improvements.map((e) => '- ${e.toString()}').join('\n');
        }
      }

      return normalized;
    } catch (e) {
      debugPrint('ChatbotService.evaluateSpeakingTest error: $e');
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // YÖKDİL / YDS SORU ÜRETİMİ
  // ═══════════════════════════════════════════════════════════════════════════

  /// YÖKDİL/YDS Grammar sorusu üret
  Future<Map<String, dynamic>> generateYokdilGrammarQuestion({
    String subType = 'tense_voice', // tense_voice, conjunctions, correlative
    int count = 1,
  }) async {
    final randomSeed = DateTime.now().millisecondsSinceEpoch;
    
    String subTypePrompt = '';
    switch (subType) {
      case 'tense_voice':
        subTypePrompt = '''
MUTLAKA İKİ BOŞLUKLU cümle üret! Her şık iki fiil içermeli (slash ile ayrılmış: "had been / was").

GERÇEK YÖKDİL GRAMMAR ÖRNEKLERİ (bunlara benzer üret):

Örnek 1:
"It ---- that life on Earth ---- about 4 billion years ago."
A) is believed / started
B) was believed / has started  
C) has been believed / was starting
D) is believed / had started
E) had been believed / starts
Doğru: A

Örnek 2:
"The experiment ---- successfully before the funding ----."
A) had been completed / was cut
B) has been completed / is cut
C) was completed / had been cut
D) is completed / will be cut
E) would be completed / has been cut
Doğru: A

Örnek 3:
"By the time the rescue team ----, most of the survivors ----."
A) arrived / had been found
B) has arrived / were found
C) arrives / have been found
D) had arrived / are found
E) would arrive / had found
Doğru: A

KRİTİK KURALLAR:
1. MUTLAKA İKİ BOŞLUK olacak (---- ve ----)
2. Şıklar "fiil1 / fiil2" formatında (örn: "had been completed / was cut")
3. Sadece BİR şık gramer açısından doğru olmalı
4. Diğer 4 şık tense uyumsuzluğu, voice hatası veya anlam bozukluğu içermeli
5. Cümle akademik/bilimsel konuda olmalı (fen, tıp, tarih, teknoloji vb.)
''';
        break;
      case 'conjunctions':
        subTypePrompt = '''
Bağlaç sorusu üret. Cümle başında VEYA ortasında tek boşluk olabilir.

GERÇEK YÖKDİL BAĞLAÇ ÖRNEKLERİ:

Örnek 1:
"---- astronomers have so far found no Earth-like planets, this does not mean that there are none."
A) While
B) As
C) Even though
D) As if
E) Unless
Doğru: C

Örnek 2:
"The effects of climate change ---- we take immediate action will be catastrophic."
A) although
B) unless
C) as if
D) so that
E) whereas
Doğru: B

KURALLAR:
1. 5 farklı bağlaç şık olarak sunulmalı
2. Sadece 1 bağlaç cümlenin anlamına uygun olmalı
3. Cümle akademik/bilimsel konuda olmalı
''';
        break;
      case 'correlative':
        subTypePrompt = '''
İkili bağlaç (Correlative Conjunction) sorusu üret.

GERÇEK YÖKDİL ÖRNEKLERİ:

Örnek 1:
"Products ---- diverse ---- rubber, tobacco, and coffee come from flowering plants."
A) as / as
B) too / than
C) both / and
D) either / or
E) not only / but also
Doğru: A

Örnek 2:
"The new vaccine is ---- effective ---- it can prevent the disease in 95% of cases."
A) such / that
B) so / that
C) more / than
D) as / as
E) neither / nor
Doğru: B

KURALLAR:
1. İKİ BOŞLUK olacak
2. Şıklar ikili bağlaç çiftleri olacak (slash ile ayrılmış)
3. Sadece 1 çift doğru olmalı
''';
        break;
    }

    final prompt = '''
YÖKDİL/YDS Grammar sorusu üret. Seviye: C1 (Advanced)

$subTypePrompt

Random seed: $randomSeed

JSON formatında döndür:
{
  "question": "Akademik cümle ---- birinci boşluk ---- ikinci boşluk.",
  "options": {
    "A": "fiil1 / fiil2",
    "B": "fiil1 / fiil2",
    "C": "fiil1 / fiil2",
    "D": "fiil1 / fiil2",
    "E": "fiil1 / fiil2"
  },
  "correct_answer": "B",
  "explanation": "Neden B doğru? Türkçe açıklama. Diğer şıkların neden yanlış olduğunu da açıkla.",
  "question_type": "grammar",
  "sub_type": "$subType"
}
''';

    try {
      return await GroqApiClient.getJsonResponse(
        messages: [
          {'role': 'system', 'content': 'Sen YÖKDİL/YDS sınavı için profesyonel soru üreten bir İngilizce dil uzmanısın. MUTLAKA iki boşluklu, akademik cümleler üret. SADECE geçerli JSON döndür.'},
          {'role': 'user', 'content': prompt}
        ],
        temperature: 0.7,
        timeout: const Duration(seconds: 30),
      );
    } catch (e) {
      debugPrint('ChatbotService.generateYokdilGrammarQuestion error: $e');
      rethrow;
    }
  }

  /// YÖKDİL/YDS Vocabulary sorusu üret
  Future<Map<String, dynamic>> generateYokdilVocabularyQuestion({
    String subType = 'phrasal_verb', // phrasal_verb, academic_word
  }) async {
    final randomSeed = DateTime.now().millisecondsSinceEpoch;
    
    String subTypePrompt = '';
    switch (subType) {
      case 'phrasal_verb':
        subTypePrompt = '''
CÜMLE İÇİNDE BOŞLUK DOLDURMA formatında Phrasal Verb sorusu üret.

GERÇEK YÖKDİL VOCABULARY ÖRNEKLERİ (bunlara benzer üret):

Örnek 1:
"The moon maps are incomplete but it is hoped that the 2008 lunar orbiter will ---- the gaps for us."
A) make up
B) fill in
C) lay out
D) put over
E) work out
Doğru: B (fill in = boşlukları doldurmak)

Örnek 2:
"By one account, the team ---- the desired compound in just three days."
A) drove through
B) turned over
C) came up with
D) put up with
E) made up for
Doğru: C (came up with = bulmak/üretmek)

Örnek 3:
"The government's nuclear adviser ---- that so far no radioactive contamination has been found outside the test site."
A) points out
B) puts out
C) sets up
D) takes over
E) gets in
Doğru: A (points out = belirtmek)

Örnek 4:
"Home heating, which ---- less than 7 per cent of all energy consumed in the US, has had a commendable efficiency record."
A) accounts for
B) comes with
C) joins in
D) picks up
E) brings out
Doğru: A (accounts for = oluşturmak)

KRİTİK KURALLAR:
1. Cümle içinde TEK BOŞLUK (----) olacak
2. Şıklar phrasal verb olacak (kelime + preposition)
3. 5 farklı phrasal verb şık olarak sunulacak
4. Sadece 1 phrasal verb cümlenin anlamına uygun olacak
5. Diğer 4 şık anlam olarak yakın ama yanlış olmalı
6. ASLA "...is called" veya tanım sorma formatı KULLANMA
''';
        break;
      case 'academic_word':
        subTypePrompt = '''
CÜMLE İÇİNDE BOŞLUK DOLDURMA formatında Akademik Kelime sorusu üret.

GERÇEK YÖKDİL VOCABULARY ÖRNEKLERİ:

Örnek 1:
"His efforts to ---- the threat of global warming with new forms of energy have been much appreciated."
A) excuse
B) counter
C) pursue
D) uphold
E) deliver
Doğru: B (counter = karşı koymak)

Örnek 2:
"It is hoped that these ---- projects will lead to a better understanding of typhoons and improve short-term weather forecasting."
A) defensive
B) excessive
C) comprehensive
D) regrettable
E) forceful
Doğru: C (comprehensive = kapsamlı)

Örnek 3:
"The Sun's gravitational pull on the moon is more than twice that ---- by the Earth."
A) attempted
B) undertaken
C) magnified
D) replaced
E) exerted
Doğru: E (exerted = uygulamak)

Örnek 4:
"At times during the last Ice Age the North Atlantic thermohaline circulation was ---- weaker than it is today."
A) pleasantly
B) rarely
C) considerably
D) directly
E) fully
Doğru: C (considerably = önemli ölçüde)

KRİTİK KURALLAR:
1. Cümle içinde TEK BOŞLUK (----) olacak
2. Şıklar tek kelime olacak (fiil, sıfat veya zarf)
3. 5 farklı kelime şık olarak sunulacak
4. Sadece 1 kelime cümlenin anlamına ve gramerine uygun olacak
5. Diğer 4 şık aynı kelime türünden ama anlam olarak yanlış olmalı
6. ASLA "...is called" veya tanım sorma formatı KULLANMA
''';
        break;
    }

    final prompt = '''
YÖKDİL/YDS Vocabulary sorusu üret. Seviye: C1

$subTypePrompt

Random seed: $randomSeed

JSON formatında döndür:
{
  "question": "Akademik cümle ---- boşluk içeren tam cümle.",
  "options": {
    "A": "kelime/phrasal verb",
    "B": "kelime/phrasal verb",
    "C": "kelime/phrasal verb",
    "D": "kelime/phrasal verb",
    "E": "kelime/phrasal verb"
  },
  "correct_answer": "B",
  "explanation": "Neden B doğru? Türkçe açıklama ve kelimenin anlamı.",
  "question_type": "vocabulary",
  "sub_type": "$subType"
}
''';

    try {
      return await GroqApiClient.getJsonResponse(
        messages: [
          {'role': 'system', 'content': 'Sen YÖKDİL sınavı için profesyonel vocabulary sorusu üreten bir uzman. MUTLAKA cümle içinde boşluk doldurma formatı kullan. ASLA tanım sorma formatı kullanma. SADECE geçerli JSON döndür.'},
          {'role': 'user', 'content': prompt}
        ],
        temperature: 0.7,
        timeout: const Duration(seconds: 30),
      );
    } catch (e) {
      debugPrint('ChatbotService.generateYokdilVocabularyQuestion error: $e');
      rethrow;
    }
  }

  /// YÖKDİL/YDS Preposition sorusu üret
  Future<Map<String, dynamic>> generateYokdilPrepositionQuestion() async {
    final randomSeed = DateTime.now().millisecondsSinceEpoch;
    
    final prompt = '''
YÖKDİL/YDS Preposition (Edat) sorusu üret. Seviye: C1

İKİ boşluklu cümle olmalı.
Yaygın kalıplar: from/to (range), in/at/on (location), by/with (agent/means), about/for (purpose)

Random seed: $randomSeed

Örnek format:
"The temperature ranges ---- 80° ---- 350° centigrade."

JSON formatında döndür:
{
  "question": "Cümle ---- boşluk ---- boşluk",
  "options": {"A": "from / to", "B": "between / of", "C": "among / at", "D": "within / over", "E": "under / off"},
  "correct_answer": "A",
  "explanation": "Türkçe açıklama",
  "question_type": "preposition"
}
''';

    try {
      return await GroqApiClient.getJsonResponse(
        messages: [
          {'role': 'system', 'content': 'Sen YÖKDİL sınavı için profesyonel soru üreten bir uzman. SADECE geçerli JSON döndür.'},
          {'role': 'user', 'content': prompt}
        ],
        temperature: 0.8,
        timeout: const Duration(seconds: 30),
      );
    } catch (e) {
      debugPrint('ChatbotService.generateYokdilPrepositionQuestion error: $e');
      rethrow;
    }
  }

  /// YÖKDİL/YDS Cloze Test üret (5 soruluk paragraf)
  Future<Map<String, dynamic>> generateYokdilClozeTest() async {
    final randomSeed = DateTime.now().millisecondsSinceEpoch;
    
    final prompt = '''
YÖKDİL/YDS Cloze Test üret. 

BİR paragraf ve 5 numaralı boşluk olacak.
Her boşluk için 5 şık (A-E).

Boşluk tipleri karışık olmalı:
- Tense/Voice
- Conjunction
- Preposition
- Noun/Adjective
- Pronoun/Determiner

Random seed: $randomSeed

JSON formatında döndür:
{
  "paragraph": "Paragraf metni (1)---- ilk boşluk (2)---- ikinci boşluk ... (5)----",
  "questions": [
    {
      "blank_number": 1,
      "options": {"A": "...", "B": "...", "C": "...", "D": "...", "E": "..."},
      "correct_answer": "B",
      "explanation": "Açıklama"
    },
    ... (5 soru)
  ],
  "question_type": "cloze_test"
}
''';

    try {
      return await GroqApiClient.getJsonResponse(
        messages: [
          {'role': 'system', 'content': 'Sen YÖKDİL sınavı için profesyonel soru üreten bir uzman. SADECE geçerli JSON döndür.'},
          {'role': 'user', 'content': prompt}
        ],
        temperature: 0.7,
        timeout: const Duration(seconds: 45),
      );
    } catch (e) {
      debugPrint('ChatbotService.generateYokdilClozeTest error: $e');
      rethrow;
    }
  }

  /// YÖKDİL/YDS Sentence Completion sorusu üret
  Future<Map<String, dynamic>> generateYokdilSentenceCompletion() async {
    final randomSeed = DateTime.now().millisecondsSinceEpoch;
    
    final prompt = '''
YÖKDİL/YDS Sentence Completion (Cümle Tamamlama) sorusu üret.

Yarım cümle ver, 5 tam cümle şık olarak sun.
Bağlaç sinyalleri kullan: Although, If, Since, Unless, ----, which

Random seed: $randomSeed

Örnek:
"Although scientists have made significant progress in cancer research, ----."

JSON formatında döndür:
{
  "question": "Yarım cümle ----.",
  "options": {
    "A": "tam cümle şık A",
    "B": "tam cümle şık B",
    "C": "tam cümle şık C", 
    "D": "tam cümle şık D",
    "E": "tam cümle şık E"
  },
  "correct_answer": "C",
  "explanation": "Türkçe açıklama",
  "question_type": "sentence_completion"
}
''';

    try {
      return await GroqApiClient.getJsonResponse(
        messages: [
          {'role': 'system', 'content': 'Sen YÖKDİL sınavı için profesyonel soru üreten bir uzman. SADECE geçerli JSON döndür.'},
          {'role': 'user', 'content': prompt}
        ],
        temperature: 0.8,
        timeout: const Duration(seconds: 30),
      );
    } catch (e) {
      debugPrint('ChatbotService.generateYokdilSentenceCompletion error: $e');
      rethrow;
    }
  }

  /// YÖKDİL/YDS Translation sorusu üret
  Future<Map<String, dynamic>> generateYokdilTranslation({
    String direction = 'en_to_tr', // en_to_tr veya tr_to_en
  }) async {
    final randomSeed = DateTime.now().millisecondsSinceEpoch;
    
    String directionPrompt = direction == 'en_to_tr' 
      ? 'İngilizce cümle ver, 5 Türkçe çeviri şık sun.'
      : 'Türkçe cümle ver, 5 İngilizce çeviri şık sun.';

    final prompt = '''
YÖKDİL/YDS Translation (Çeviri) sorusu üret.

$directionPrompt

Random seed: $randomSeed

KURALLAR:
1. Cümle akademik/bilimsel olmalı
2. Şıklar ince anlam farkları içermeli
3. Yanlış şıklar: zaman hatası, edilgen/etken karışıklık, anlam kaydırması

JSON formatında döndür:
{
  "source_sentence": "Kaynak cümle",
  "direction": "$direction",
  "options": {
    "A": "Çeviri şık A",
    "B": "Çeviri şık B",
    "C": "Çeviri şık C",
    "D": "Çeviri şık D",
    "E": "Çeviri şık E"
  },
  "correct_answer": "B",
  "explanation": "Neden B doğru, diğerleri neden yanlış",
  "question_type": "translation"
}
''';

    try {
      return await GroqApiClient.getJsonResponse(
        messages: [
          {'role': 'system', 'content': 'Sen YÖKDİL sınavı için profesyonel çeviri sorusu üreten bir uzman. SADECE geçerli JSON döndür.'},
          {'role': 'user', 'content': prompt}
        ],
        temperature: 0.7,
        timeout: const Duration(seconds: 30),
      );
    } catch (e) {
      debugPrint('ChatbotService.generateYokdilTranslation error: $e');
      rethrow;
    }
  }

  /// YÖKDİL/YDS Paragraph Completion sorusu üret
  Future<Map<String, dynamic>> generateYokdilParagraphCompletion() async {
    final randomSeed = DateTime.now().millisecondsSinceEpoch;
    
    final prompt = '''
YÖKDİL/YDS Paragraph Completion (Paragraf Tamamlama) sorusu üret.

4-5 cümlelik paragraf ver, ortada veya sonda ---- boşluk bırak.
5 tam cümle şık olarak sun.

Random seed: $randomSeed

Bağlantı sinyalleri kullan: Further, However, For instance vb.

JSON formatında döndür:
{
  "paragraph": "Paragraf metni. ---- Boşluk. Devam eden cümle.",
  "options": {
    "A": "Şık A cümlesi",
    "B": "Şık B cümlesi",
    "C": "Şık C cümlesi",
    "D": "Şık D cümlesi",
    "E": "Şık E cümlesi"
  },
  "correct_answer": "D",
  "explanation": "Türkçe açıklama",
  "question_type": "paragraph_completion"
}
''';

    try {
      return await GroqApiClient.getJsonResponse(
        messages: [
          {'role': 'system', 'content': 'Sen YÖKDİL sınavı için profesyonel soru üreten bir uzman. SADECE geçerli JSON döndür.'},
          {'role': 'user', 'content': prompt}
        ],
        temperature: 0.7,
        timeout: const Duration(seconds: 30),
      );
    } catch (e) {
      debugPrint('ChatbotService.generateYokdilParagraphCompletion error: $e');
      rethrow;
    }
  }

  /// YÖKDİL/YDS Irrelevant Sentence sorusu üret
  Future<Map<String, dynamic>> generateYokdilIrrelevantSentence() async {
    final randomSeed = DateTime.now().millisecondsSinceEpoch;
    
    final prompt = '''
YÖKDİL/YDS Irrelevant Sentence (Anlam Bütünlüğünü Bozan Cümle) sorusu üret.

5 numaralı cümle (I, II, III, IV, V) ver.
BİR cümle konu dışı olmalı.

Random seed: $randomSeed

Konu dışı cümle açıkça farklı olmamalı, ince fark olmalı.

JSON formatında döndür:
{
  "sentences": {
    "I": "Birinci cümle",
    "II": "İkinci cümle",
    "III": "Üçüncü cümle",
    "IV": "Dördüncü cümle",
    "V": "Beşinci cümle"
  },
  "options": {"A": "I", "B": "II", "C": "III", "D": "IV", "E": "V"},
  "correct_answer": "B",
  "explanation": "II. cümle neden konu dışı? Türkçe açıklama",
  "question_type": "irrelevant_sentence"
}
''';

    try {
      return await GroqApiClient.getJsonResponse(
        messages: [
          {'role': 'system', 'content': 'Sen YÖKDİL sınavı için profesyonel soru üreten bir uzman. SADECE geçerli JSON döndür.'},
          {'role': 'user', 'content': prompt}
        ],
        temperature: 0.7,
        timeout: const Duration(seconds: 30),
      );
    } catch (e) {
      debugPrint('ChatbotService.generateYokdilIrrelevantSentence error: $e');
      rethrow;
    }
  }

  /// YÖKDİL/YDS Reading Passage soruları üret (1 paragraf + 3 soru)
  Future<Map<String, dynamic>> generateYokdilReadingPassage() async {
    final randomSeed = DateTime.now().millisecondsSinceEpoch;
    
    final prompt = '''
YÖKDİL/YDS Reading Passage (Okuma Parçası) üret.

1 uzun paragraf (8-12 cümle) ve 3 soru üret.

Random seed: $randomSeed

Soru kalıpları:
- "According to the passage, ..."
- "We understand from the passage that ..."
- "It is clear from the passage that ..."

JSON formatında döndür:
{
  "passage": "Uzun paragraf metni...",
  "questions": [
    {
      "question": "According to the passage, ----.",
      "options": {"A": "...", "B": "...", "C": "...", "D": "...", "E": "..."},
      "correct_answer": "C",
      "explanation": "Açıklama"
    },
    {
      "question": "We understand from the passage that ----.",
      "options": {"A": "...", "B": "...", "C": "...", "D": "...", "E": "..."},
      "correct_answer": "A",
      "explanation": "Açıklama"
    },
    {
      "question": "It is pointed out in the passage that ----.",
      "options": {"A": "...", "B": "...", "C": "...", "D": "...", "E": "..."},
      "correct_answer": "E",
      "explanation": "Açıklama"
    }
  ],
  "question_type": "reading_passage"
}
''';

    try {
      return await GroqApiClient.getJsonResponse(
        messages: [
          {'role': 'system', 'content': 'Sen YÖKDİL sınavı için profesyonel okuma parçası ve soru üreten bir uzman. SADECE geçerli JSON döndür.'},
          {'role': 'user', 'content': prompt}
        ],
        temperature: 0.7,
        timeout: const Duration(seconds: 60),
      );
    } catch (e) {
      debugPrint('ChatbotService.generateYokdilReadingPassage error: $e');
      rethrow;
    }
  }

  /// Tam YÖKDİL Deneme Sınavı üret (mini versiyon - test amaçlı)
  Future<Map<String, dynamic>> generateYokdilMiniTest({
    int grammarCount = 3,
    int vocabCount = 2,
    int sentenceCount = 2,
  }) async {
    final questions = <Map<String, dynamic>>[];
    
    // Grammar soruları
    for (int i = 0; i < grammarCount; i++) {
      final subTypes = ['tense_voice', 'conjunctions', 'relative_clause'];
      final q = await generateYokdilGrammarQuestion(subType: subTypes[i % 3]);
      questions.add(q);
    }
    
    // Vocabulary soruları
    for (int i = 0; i < vocabCount; i++) {
      final subTypes = ['phrasal_verb', 'academic_word'];
      final q = await generateYokdilVocabularyQuestion(subType: subTypes[i % 2]);
      questions.add(q);
    }
    
    // Sentence Completion soruları
    for (int i = 0; i < sentenceCount; i++) {
      final q = await generateYokdilSentenceCompletion();
      questions.add(q);
    }
    
    return {
      'test_type': 'yokdil_mini',
      'total_questions': questions.length,
      'questions': questions,
      'generated_at': DateTime.now().toIso8601String(),
    };
  }
}

