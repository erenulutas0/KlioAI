package com.ingilizce.calismaapp.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Server-side Groq proxy for app features that used to call Groq directly from Flutter.
 * Keeps prompts server-controlled so quotas/rate limits can be enforced reliably.
 */
@Service
public class AiProxyService {

    private static final Logger logger = LoggerFactory.getLogger(AiProxyService.class);
    private final AiCompletionProvider aiCompletionProvider;
    private final ObjectMapper objectMapper = new ObjectMapper();
    @Autowired(required = false)
    private AiModelRoutingService aiModelRoutingService;

    public AiProxyService(AiCompletionProvider aiCompletionProvider) {
        this.aiCompletionProvider = aiCompletionProvider;
    }

    public record AiJsonResult(Map<String, Object> json,
                               int totalTokens,
                               int promptTokens,
                               int completionTokens) {
    }

    public AiJsonResult dictionaryLookup(String word) {
        LearningLanguageProfile profile = LearningLanguageProfile.defaultProfile();
        String system = """
%s

You are a comprehensive %s dictionary. When given a %s word, provide a refined list of its different meanings in %s (up to 5). For EACH meaning, strictly provide:
1. The %s translation ('translation')
2. The context/nuance ('context') (e.g. literal, metaphorical, legal)
3. A %s example sentence using that specific meaning ('example')

You must respond with valid JSON only. Do not include markdown formatting.
Format: { "word": "input_word", "type": "noun/verb/adj", "meanings": [ { "translation": "...", "context": "...", "example": "..." }, ... ] }
""".formatted(
                profile.toPromptPolicyBlock(),
                profile.targetToSourceLabel(),
                profile.targetLanguage(),
                profile.sourceLanguage(),
                profile.sourceLanguage(),
                profile.targetLanguage()
        );
        return callJson(system, word, 700, 0.3, "dictionary-lookup");
    }

    public AiJsonResult dictionaryLookupDetailed(String word) {
        LearningLanguageProfile profile = LearningLanguageProfile.defaultProfile();
        String prompt = """
%s

Look up the %s word/phrase "%s" and provide ALL its different meanings with word types.

For EACH meaning, provide:
1. "type" - Word type (n = noun, v = verb, adj = adjective, adv = adverb, phr = phrasal verb, idiom = idiom)
2. "turkishMeaning" - %s translation for this specific meaning
3. "englishDefinition" - Brief %s definition
4. "example" - A %s example sentence using the word in this specific meaning
5. "exampleTranslation" - %s translation of the example sentence

Return ONLY valid JSON in this exact format:
{
  "word": "%s",
  "phonetic": "/phonetic transcription/",
  "meanings": [
    {
      "type": "v",
      "turkishMeaning": "neden olmak, yol açmak",
      "englishDefinition": "to cause something to happen",
      "example": "The new policy will bring about significant changes.",
      "exampleTranslation": "Yeni politika önemli değişikliklere yol açacak."
    }
  ]
}

Be comprehensive - include ALL common meanings and word types for "%s".
""".formatted(
                profile.toPromptPolicyBlock(),
                profile.targetLanguage(),
                word,
                profile.sourceLanguage(),
                profile.targetLanguage(),
                profile.targetLanguage(),
                profile.sourceLanguage(),
                word,
                word
        );

        String system = "You are a comprehensive %s dictionary for %s. Always return valid JSON. Be thorough and include all word types and meanings."
                .formatted(profile.targetToSourceLabel(), "English learning");
        return callJson(system, prompt, 900, 0.3, "dictionary-lookup-detailed");
    }

    public AiJsonResult dictionaryGenerateSpecificSentence(String word, String translation, String context) {
        LearningLanguageProfile profile = LearningLanguageProfile.defaultProfile();
        String prompt = "Generate a new, simple %s sentence using the word '%s' specifically in the sense of '%s' (%s). Return valid JSON: { \"sentence\": \"...\" }"
                .formatted(profile.targetLanguage(), word, translation, context);
        String system = "You are a helper generating specific example sentences. Return valid JSON only.";
        return callJson(system, prompt, 200, 0.7, "dictionary-specific-sentence");
    }

    public AiJsonResult dictionaryExplainWordInSentence(String word, String sentence) {
        LearningLanguageProfile profile = LearningLanguageProfile.defaultProfile();
        String prompt = "Explain the meaning of the word '%s' inside this specific sentence: '%s'. Provide the definition in %s, keeping it very short/concise (max 15 words). Return ONLY valid JSON. Format: { \"definition\": \"...\" }"
                .formatted(word, sentence, profile.sourceLanguage());
        String system = "You are a dictionary helper. Return valid JSON.";
        return callJson(system, prompt, 120, 0.3, "dictionary-explain");
    }

    public AiJsonResult generateReadingPassage(String level) {
        Map<String, Map<String, String>> levelConfig = new HashMap<>();
        levelConfig.put("A1", Map.of(
                "wordCount", "80-120",
                "sentences", "very short and simple sentences (5-8 words)",
                "vocabulary", "basic everyday words, no idioms",
                "topics", "daily life (family, food, hobbies)",
                "grammar", "present simple tense only",
                "questionDifficulty", "direct, answer explicitly in text"
        ));
        levelConfig.put("A2", Map.of(
                "wordCount", "120-160",
                "sentences", "short sentences with basic conjunctions (and, but, because)",
                "vocabulary", "common words, simple phrasal verbs",
                "topics", "travel, school, jobs, weather",
                "grammar", "present and past simple tenses",
                "questionDifficulty", "mostly direct, one inference question"
        ));
        levelConfig.put("B1", Map.of(
                "wordCount", "160-220",
                "sentences", "mix of simple and compound sentences",
                "vocabulary", "wider range, some topic-specific terms",
                "topics", "technology, health, environment, culture",
                "grammar", "various tenses, passive voice",
                "questionDifficulty", "mix of direct and inference questions"
        ));
        levelConfig.put("B2", Map.of(
                "wordCount", "220-280",
                "sentences", "complex sentences with subordinate clauses",
                "vocabulary", "academic vocabulary, idioms, collocations",
                "topics", "science, economics, social issues",
                "grammar", "conditionals, relative clauses, modal verbs",
                "questionDifficulty", "inference and analysis required"
        ));
        levelConfig.put("C1", Map.of(
                "wordCount", "280-350",
                "sentences", "sophisticated sentence structures, varied length",
                "vocabulary", "advanced academic and specialized terms",
                "topics", "policy, ethics, scientific communication",
                "grammar", "all tenses, subjunctive, inversions",
                "questionDifficulty", "critical thinking and synthesis required"
        ));
        levelConfig.put("C2", Map.of(
                "wordCount", "340-430",
                "sentences", "dense and nuanced discourse with abstract argumentation",
                "vocabulary", "near-native lexical range, discipline-specific terms, rhetorical markers",
                "topics", "philosophy of science, governance trade-offs, socio-technical systems",
                "grammar", "advanced clause embedding, inversion, concessive and counterfactual forms",
                "questionDifficulty", "multi-step inference, author stance, implication-level analysis"
        ));

        String normalizedLevel = normalizeReadingLevel(level);
        Map<String, String> config = levelConfig.getOrDefault(normalizedLevel, levelConfig.get("B1"));

String prompt = """
Generate a reading passage for English learners. Strictly follow these constraints:

LEVEL: %s
WORD COUNT: %s words (strictly within this range)
SENTENCE STYLE: %s
VOCABULARY: %s
TOPIC CATEGORY: %s
GRAMMAR FOCUS: %s
QUESTION STYLE: %s
DIFFERENTIATION RULE:
- Passage must be clearly level-specific for %s and not reusable as another CEFR level.
- Do not reuse generic "daily routine" style content for C1/C2.
- C2 must contain denser abstract argumentation than C1.

Topic: Choose a specific, interesting topic from the category above.
Include 3 multiple choice questions (with 4 options and 1 correct answer).
Return ONLY valid JSON. No markdown formatting, no extra text.

Format:
{
  "title": "Passage Title",
  "text": "Full passage text here...",
  "wordCount": <actual word count as integer>,
  "questions": [
    {
      "question": "Question 1?",
      "options": ["A", "B", "C", "D"],
      "correctAnswer": "A",
      "explanation": "Brief explanation of why A is correct.",
      "correctAnswerQuote": "Exact sentence or phrase from the text that proves the answer."
    }
  ]
}
""".formatted(
                normalizedLevel,
                config.get("wordCount"),
                config.get("sentences"),
                config.get("vocabulary"),
                config.get("topics"),
                config.get("grammar"),
                config.get("questionDifficulty"),
                normalizedLevel
        );

        String system = "You are a professional English exam preparation assistant. Generate content that EXACTLY matches the specified level constraints. Return strictly valid JSON with no markdown formatting.";
        return callJson(system, prompt, 1400, 0.7, "reading-generate");
    }

    private String normalizeReadingLevel(String level) {
        if (level == null || level.isBlank()) {
            return "B1";
        }
        String raw = level.trim().toUpperCase(Locale.ROOT);
        return switch (raw) {
            case "BEGINNER" -> "A1";
            case "ELEMENTARY" -> "A2";
            case "INTERMEDIATE" -> "B1";
            case "UPPER-INTERMEDIATE", "UPPER_INTERMEDIATE" -> "B2";
            case "ADVANCED" -> "C1";
            case "A1", "A2", "B1", "B2", "C1", "C2" -> raw;
            default -> "B1";
        };
    }

    public AiJsonResult generateWritingTopic(String level, String wordCount) {
        long seed = System.currentTimeMillis();
        String prompt = """
Generate a UNIQUE and creative writing topic for %s level English learners. The topic should be engaging and appropriate for someone who needs to write %s words.
IMPORTANT: Avoid generic topics like "My Daily Routine" unless explicitly asked.
Try to be diverse (culture, science, abstract, storytelling, opinion, etc.).
seed: %d

Return JSON with:
topic, description, level, wordCount.
""".formatted(level, wordCount, seed);
        return callJson("Return valid JSON only.", prompt, 450, 0.9, "writing-topic");
    }

    public AiJsonResult evaluateWriting(String text, String level, Map<String, Object> topic) {
        String topicTitle = topic != null && topic.get("topic") != null ? topic.get("topic").toString() : "";
        String topicDesc = topic != null && topic.get("description") != null ? topic.get("description").toString() : "";

        String prompt = """
Evaluate this %s level English writing based on the following topic:

TOPIC: %s
DESCRIPTION: %s

USER WRITING:
"%s"

Provide detailed feedback in JSON format.
CRITICAL: You MUST check if the user wrote about the assigned topic.
If the writing is completely off-topic (e.g., user wrote about football when topic was space travel),
give a low score and mention it in "contextRelevance".

JSON Format:
{
  "score": number (0-100),
  "strengths": string[],
  "improvements": string[],
  "grammar": string,
  "vocabulary": string,
  "coherence": string,
  "overall": string,
  "contextRelevance": string
}
""".formatted(level, topicTitle, topicDesc, text);

        return callJson("Return valid JSON only.", prompt, 900, 0.5, "writing-evaluate");
    }

    public AiJsonResult generateExamBundle(Map<String, Object> request) {
        // Forward-compatible: keep the legacy Flutter prompt structure server-side.
        String examType = safeString(request.get("examType"), "YDS/YOKDIL");
        String category = safeString(request.get("category"), "grammar");
        int questionCount = safeInt(request.get("questionCount"), 10);
        String userLevel = safeString(request.get("userLevel"), "B2");
        String targetScore = safeString(request.get("targetScore"), "60-80");

        // Reuse the exact prompt style used in Flutter to keep output schema stable.
        long seed = System.currentTimeMillis();

        String systemContent = """
Sen profesyonel bir YDS/YÖKDİL sınav uzmanısın.
Görevin, belirtilen formatta tamamen ÖZGÜN, YENİ ve AKADEMİK sorular üretmektir.

KURALLAR:
1. DİL: Sorular, metinler ve şıklar TAMAMEN İNGİLİZCE olmalı. (Sadece 'Translation' kategorisi hariç).
2. ASLA Prompt içindeki örnek soruları çıktı olarak verme. Her seferinde sıfırdan düşün.
3. Her soru 5 şık (A, B, C, D, E) içermeli.
4. SADECE BİR doğru cevap olmalı.
5. Çeldiriciler güçlü olmalı.
6. Çıktı SADECE geçerli JSON olmalı.

Seviye: C1 (Advanced)
""";

        int timeLimitMinutes = questionCount * 2;

        String userContent = """
YDS/YÖKDİL Sınav Simülasyonu (%d Soru).
Random Seed: %d (Her seferinde farklı sorular üret)

SADECE "%s" kategorisinden %d adet YENİ ve ÖZGÜN soru üret.
ÖNEMLİ: Daha önce sorulmamış, özgün sorular üret. Sorular birbirini tekrar etmesin.

Kullanıcı Profili:
- Seviye: %s
- Hedef Puan: %s

JSON ÇIKTI FORMATI:
{
  "meta": {
    "exam": "%s",
    "mode": "category",
    "category": "%s",
    "track": "general",
    "user_level_cefr": "%s",
    "target_score_band": "%s",
    "time_limit_minutes": %d,
    "total_questions": %d
  },
  "sections": [
    {
      "name": "Generated Test",
      "items": [
        {
          "id": "q_%d_1",
          "type": "%s",
          "difficulty": "hard",
          "skill_tags": [],
          "stem": "Question text (ENGLISH)...",
          "passage": null,
          "options": {"A":"Answer A (ENGLISH)...","B":"...","C":"...","D":"...","E":"..."},
          "correct": "A",
          "explanation_tr": "Türkçe Açıklama",
          "explanation_en": "English Explanation"
        }
      ]
    }
  ]
}
""".formatted(
                questionCount,
                seed,
                category,
                questionCount,
                userLevel,
                targetScore,
                examType,
                category,
                userLevel,
                targetScore,
                timeLimitMinutes,
                questionCount,
                seed,
                category
        );

        // Exam generation is expensive; cap max tokens but allow long outputs.
        return callJson(systemContent, userContent, 4000, 0.85, "exam-generate");
    }

    private AiJsonResult callJson(String systemPrompt,
                                  String userPrompt,
                                  Integer maxTokens,
                                  Double temperature,
                                  String scope) {
        List<Map<String, String>> messages = new ArrayList<>();
        messages.add(Map.of("role", "system", "content", systemPrompt));
        messages.add(Map.of("role", "user", "content", userPrompt));

        AiCompletionProvider.CompletionResult completion = aiCompletionProvider.chatCompletionWithUsage(
                messages,
                true,
                maxTokens,
                temperature,
                resolveModelForScope(scope));
        String raw = completion != null ? completion.content() : null;
        String cleaned = normalizeJson(raw);
        int totalTokens = completion != null ? completion.totalTokens() : 0;
        int promptTokens = completion != null ? completion.promptTokens() : 0;
        int completionTokens = completion != null ? completion.completionTokens() : 0;

        Map<String, Object> parsed = tryParseJsonMap(cleaned);
        if (parsed != null && !parsed.isEmpty() && isValidScopeJson(scope, parsed)) {
            return new AiJsonResult(parsed, totalTokens, promptTokens, completionTokens);
        }
        if (parsed != null && !parsed.isEmpty()) {
            logger.warn("AI proxy JSON schema validation failed for scope={} keys={}", scope, parsed.keySet());
        }

        AiJsonResult rescue = tryRescueWithDefaultModel(
                messages,
                scope,
                maxTokens,
                temperature,
                totalTokens,
                promptTokens,
                completionTokens);
        if (rescue != null) {
            return rescue;
        }

        Map<String, Object> fallback = buildScopeFallback(scope, userPrompt, raw);
        logger.warn("AI proxy fallback payload used for scope={} (rawLength={})",
                scope, raw != null ? raw.length() : 0);
        return new AiJsonResult(fallback, totalTokens, promptTokens, completionTokens);
    }

    private Map<String, Object> tryParseJsonMap(String cleaned) {
        try {
            Object parsed = objectMapper.readValue(cleaned, Object.class);
            if (parsed instanceof Map<?, ?>) {
                return objectMapper.convertValue(parsed, new TypeReference<Map<String, Object>>() {
                });
            }
        } catch (Exception ignored) {
            // try direct map parse next
        }

        try {
            return objectMapper.readValue(cleaned, new TypeReference<Map<String, Object>>() {
            });
        } catch (Exception ignored) {
            return null;
        }
    }

    private boolean isValidScopeJson(String scope, Map<String, Object> parsed) {
        if (parsed == null || parsed.isEmpty()) {
            return false;
        }
        return switch (scope) {
            case "dictionary-lookup", "dictionary-lookup-detailed" ->
                    hasNonBlank(parsed, "word") && hasList(parsed, "meanings");
            case "dictionary-specific-sentence" -> hasNonBlank(parsed, "sentence");
            case "dictionary-explain" -> hasNonBlank(parsed, "definition");
            case "reading-generate" ->
                    hasNonBlank(parsed, "title") && hasNonBlank(parsed, "text") && hasList(parsed, "questions");
            case "writing-topic" -> hasNonBlank(parsed, "topic") && hasNonBlank(parsed, "description");
            case "writing-evaluate" -> parsed.containsKey("score") && hasNonBlank(parsed, "overall");
            case "exam-generate" -> parsed.containsKey("meta") && hasList(parsed, "sections");
            default -> true;
        };
    }

    private boolean hasNonBlank(Map<String, Object> map, String key) {
        Object value = map.get(key);
        return value != null && !value.toString().trim().isBlank();
    }

    private boolean hasList(Map<String, Object> map, String key) {
        Object value = map.get(key);
        return value instanceof List<?> list && !list.isEmpty();
    }

    private Map<String, Object> buildScopeFallback(String scope, String userPrompt, String raw) {
        return switch (scope) {
            case "dictionary-lookup" -> buildDictionaryLookupFallback(userPrompt);
            case "dictionary-lookup-detailed" -> buildDictionaryLookupDetailedFallback(userPrompt);
            case "dictionary-specific-sentence" -> buildDictionarySpecificSentenceFallback(userPrompt);
            case "dictionary-explain" -> buildDictionaryExplainFallback();
            case "reading-generate" -> buildReadingFallback(raw);
            case "writing-topic" -> buildWritingTopicFallback();
            case "writing-evaluate" -> buildWritingEvaluateFallback();
            case "exam-generate" -> buildExamFallback();
            default -> {
                Map<String, Object> fallback = new HashMap<>();
                fallback.put("fallback", true);
                fallback.put("message", "AI yaniti gecici olarak islenemedi.");
                yield fallback;
            }
        };
    }

    private Map<String, Object> buildDictionaryLookupFallback(String userPrompt) {
        String word = extractWordHint(userPrompt);
        Map<String, Object> meaning = new HashMap<>();
        meaning.put("translation", "Anlam gecici olarak getirilemedi");
        meaning.put("context", "Lutfen bir kac saniye sonra tekrar deneyin.");
        meaning.put("example", word.isBlank()
                ? "Please try again in a moment."
                : "Please try searching \"" + word + "\" again in a moment.");

        Map<String, Object> fallback = new HashMap<>();
        fallback.put("word", word);
        fallback.put("type", "");
        fallback.put("meanings", List.of(meaning));
        fallback.put("fallback", true);
        return fallback;
    }

    private Map<String, Object> buildDictionaryLookupDetailedFallback(String userPrompt) {
        String word = extractWordHint(userPrompt);
        Map<String, Object> meaning = new HashMap<>();
        meaning.put("type", "n");
        meaning.put("turkishMeaning", "Anlam gecici olarak getirilemedi");
        meaning.put("englishDefinition", "AI response was temporarily unavailable.");
        meaning.put("example", word.isBlank()
                ? "Please try again in a moment."
                : "Please try searching \"" + word + "\" again in a moment.");
        meaning.put("exampleTranslation", "Lutfen biraz sonra tekrar deneyin.");

        Map<String, Object> fallback = new HashMap<>();
        fallback.put("word", word);
        fallback.put("phonetic", "");
        fallback.put("meanings", List.of(meaning));
        fallback.put("fallback", true);
        return fallback;
    }

    private Map<String, Object> buildDictionarySpecificSentenceFallback(String userPrompt) {
        String word = extractWordHint(userPrompt);
        String sentence = word.isBlank()
                ? "This is a practice sentence."
                : "This is a practice sentence with " + word + ".";

        Map<String, Object> fallback = new HashMap<>();
        fallback.put("sentence", sentence);
        fallback.put("fallback", true);
        return fallback;
    }

    private Map<String, Object> buildDictionaryExplainFallback() {
        Map<String, Object> fallback = new HashMap<>();
        fallback.put("definition", "Anlam gecici olarak olusturulamadi.");
        fallback.put("fallback", true);
        return fallback;
    }

    private Map<String, Object> buildReadingFallback(String raw) {
        String text = "Learning English takes regular practice. Read short texts every day, note new words, "
                + "and use them in your own sentences. Small daily steps build confidence and fluency over time.";

        List<Map<String, Object>> questions = List.of(
                Map.of(
                        "question", "What improves fluency over time?",
                        "options", List.of(
                                "Ignoring new words",
                                "Small daily practice steps",
                                "Reading once a month",
                                "Memorizing grammar rules only"
                        ),
                        "correctAnswer", "B",
                        "explanation", "The passage says small daily steps build confidence and fluency.",
                        "correctAnswerQuote", "Small daily steps build confidence and fluency over time."
                ),
                Map.of(
                        "question", "What should learners do with new words?",
                        "options", List.of(
                                "Avoid writing them down",
                                "Use them in their own sentences",
                                "Translate and forget",
                                "Only listen to them"
                        ),
                        "correctAnswer", "B",
                        "explanation", "The text advises using new words in your own sentences.",
                        "correctAnswerQuote", "use them in your own sentences"
                ),
                Map.of(
                        "question", "How often should learners read short texts?",
                        "options", List.of(
                                "Every day",
                                "Only weekends",
                                "Once a month",
                                "Only before exams"
                        ),
                        "correctAnswer", "A",
                        "explanation", "The passage recommends reading short texts every day.",
                        "correctAnswerQuote", "Read short texts every day"
                )
        );

        Map<String, Object> fallback = new HashMap<>();
        fallback.put("title", "Daily Reading Practice");
        fallback.put("text", text);
        fallback.put("wordCount", approximateWordCount(text));
        fallback.put("questions", questions);
        fallback.put("fallback", true);
        return fallback;
    }

    private Map<String, Object> buildWritingTopicFallback() {
        Map<String, Object> fallback = new HashMap<>();
        fallback.put("topic", "A Day I Learned Something New");
        fallback.put("description", "Write about a day when you learned an important lesson.");
        fallback.put("level", "Intermediate");
        fallback.put("wordCount", "120-160");
        fallback.put("fallback", true);
        return fallback;
    }

    private Map<String, Object> buildWritingEvaluateFallback() {
        Map<String, Object> fallback = new HashMap<>();
        fallback.put("score", 0);
        fallback.put("strengths", new ArrayList<>());
        fallback.put("improvements", List.of("AI degerlendirmesi gecici olarak olusturulamadi."));
        fallback.put("grammar", "");
        fallback.put("vocabulary", "");
        fallback.put("coherence", "");
        fallback.put("overall", "Lutfen yazinizi tekrar degerlendirin.");
        fallback.put("contextRelevance", "");
        fallback.put("fallback", true);
        return fallback;
    }

    private Map<String, Object> buildExamFallback() {
        Map<String, Object> meta = new HashMap<>();
        meta.put("exam", "YDS/YOKDIL");
        meta.put("mode", "category");
        meta.put("category", "grammar");
        meta.put("track", "general");
        meta.put("user_level_cefr", "B1");
        meta.put("target_score_band", "60-80");
        meta.put("time_limit_minutes", 0);
        meta.put("total_questions", 0);

        Map<String, Object> section = new HashMap<>();
        section.put("name", "Generated Test");
        section.put("items", new ArrayList<>());

        Map<String, Object> fallback = new HashMap<>();
        fallback.put("meta", meta);
        fallback.put("sections", List.of(section));
        fallback.put("fallback", true);
        return fallback;
    }

    private String extractWordHint(String prompt) {
        if (prompt == null || prompt.isBlank()) {
            return "";
        }

        Matcher doubleQuoted = Pattern.compile("\"([^\"]+)\"").matcher(prompt);
        if (doubleQuoted.find()) {
            return doubleQuoted.group(1).trim();
        }

        Matcher singleQuoted = Pattern.compile("'([^']+)'").matcher(prompt);
        if (singleQuoted.find()) {
            return singleQuoted.group(1).trim();
        }

        return prompt.trim();
    }

    private int approximateWordCount(String text) {
        if (text == null || text.isBlank()) {
            return 0;
        }
        return (int) java.util.Arrays.stream(text.trim().split("\\s+"))
                .filter(token -> token != null && !token.isBlank())
                .count();
    }

    private AiJsonResult tryRescueWithDefaultModel(List<Map<String, String>> messages,
                                                   String scope,
                                                   Integer maxTokens,
                                                   Double temperature,
                                                   int totalTokens,
                                                   int promptTokens,
                                                   int completionTokens) {
        if (!shouldTryRescueModel(scope) || aiModelRoutingService == null) {
            return null;
        }

        String primaryModel = resolveModelForScope(scope);
        String rescueModel = sanitizeModel(aiModelRoutingService.defaultModel());
        if (rescueModel == null || equalsIgnoreCaseSafe(rescueModel, primaryModel)) {
            return null;
        }

        List<Map<String, String>> rescueMessages = buildRescueMessages(messages);
        AiCompletionProvider.CompletionResult rescue = aiCompletionProvider.chatCompletionWithUsage(
                rescueMessages,
                false,
                maxTokens,
                normalizeRescueTemperature(temperature),
                rescueModel);

        String rescueRaw = rescue != null ? rescue.content() : null;
        Map<String, Object> rescueParsed = tryParseJsonMap(normalizeJson(rescueRaw));
        if (rescueParsed == null || rescueParsed.isEmpty()) {
            return null;
        }

        int rescuePromptTokens = rescue != null ? rescue.promptTokens() : 0;
        int rescueCompletionTokens = rescue != null ? rescue.completionTokens() : 0;
        int rescueTotalTokens = rescue != null ? rescue.totalTokens() : 0;

        logger.warn("AI proxy rescue succeeded for scope={} primaryModel={} rescueModel={}",
                scope, primaryModel, rescueModel);

        return new AiJsonResult(
                rescueParsed,
                totalTokens + rescueTotalTokens,
                promptTokens + rescuePromptTokens,
                completionTokens + rescueCompletionTokens);
    }

    private boolean shouldTryRescueModel(String scope) {
        if (scope == null) {
            return false;
        }
        String normalized = scope.trim().toLowerCase(Locale.ROOT);
        return "dictionary-lookup".equals(normalized)
                || "dictionary-lookup-detailed".equals(normalized)
                || "reading-generate".equals(normalized);
    }

    private List<Map<String, String>> buildRescueMessages(List<Map<String, String>> messages) {
        List<Map<String, String>> copied = new ArrayList<>();
        if (messages != null) {
            for (Map<String, String> message : messages) {
                copied.add(message != null ? new HashMap<>(message) : new HashMap<>());
            }
        }

        String hint = "IMPORTANT: Return a single valid JSON object only. "
                + "No markdown, no code fences, no extra explanation.";
        for (int i = copied.size() - 1; i >= 0; i--) {
            Map<String, String> msg = copied.get(i);
            String role = msg.get("role");
            if (role != null && "user".equalsIgnoreCase(role)) {
                String content = msg.getOrDefault("content", "");
                msg.put("content", content + "\n\n" + hint);
                return copied;
            }
        }

        copied.add(new HashMap<>(Map.of("role", "user", "content", hint)));
        return copied;
    }

    private Double normalizeRescueTemperature(Double temperature) {
        if (temperature == null) {
            return 0.25;
        }
        return Math.max(0.0, Math.min(temperature, 0.25));
    }

    private boolean equalsIgnoreCaseSafe(String a, String b) {
        if (a == null || b == null) {
            return false;
        }
        return a.equalsIgnoreCase(b);
    }

    private String sanitizeModel(String model) {
        if (model == null) {
            return null;
        }
        String trimmed = model.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }

    private String normalizeJson(String raw) {
        if (raw == null || raw.isBlank()) {
            return "{}";
        }
        String cleaned = raw.trim()
                .replace("```json", "")
                .replace("```", "")
                .trim();
        int objStart = cleaned.indexOf('{');
        int objEnd = cleaned.lastIndexOf('}');
        if (objStart >= 0 && objEnd > objStart) {
            cleaned = cleaned.substring(objStart, objEnd + 1).trim();
        }
        return cleaned;
    }

    private String safeString(Object value, String fallback) {
        if (value == null) return fallback;
        String s = value.toString().trim();
        return s.isEmpty() ? fallback : s;
    }

    private int safeInt(Object value, int fallback) {
        if (value == null) return fallback;
        if (value instanceof Number) return ((Number) value).intValue();
        try {
            return Integer.parseInt(value.toString().trim());
        } catch (Exception ignored) {
            return fallback;
        }
    }

    private String resolveModelForScope(String scope) {
        if (aiModelRoutingService == null) {
            return null;
        }
        return aiModelRoutingService.resolveModelForScope(scope);
    }
}
