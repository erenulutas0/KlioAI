package com.ingilizce.calismaapp.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Server-side Groq proxy for app features that used to call Groq directly from Flutter.
 * Keeps prompts server-controlled so quotas/rate limits can be enforced reliably.
 */
@Service
public class AiProxyService {

    private final GroqService groqService;
    private final ObjectMapper objectMapper = new ObjectMapper();

    public AiProxyService(GroqService groqService) {
        this.groqService = groqService;
    }

    public record AiJsonResult(Map<String, Object> json,
                               int totalTokens,
                               int promptTokens,
                               int completionTokens) {
    }

    public AiJsonResult dictionaryLookup(String word) {
        String system = """
You are a comprehensive English-Turkish dictionary. When given an English word, provide a refined list of its different meanings in Turkish (up to 5). For EACH meaning, strictly provide:
1. The Turkish translation ('translation')
2. The context/nuance ('context') (e.g. literal, metaphorical, legal)
3. An English example sentence using that specific meaning ('example')

You must respond with valid JSON only. Do not include markdown formatting.
Format: { "word": "input_word", "type": "noun/verb/adj", "meanings": [ { "translation": "...", "context": "...", "example": "..." }, ... ] }
""";
        return callJson(system, word, 700, 0.3);
    }

    public AiJsonResult dictionaryLookupDetailed(String word) {
        String prompt = """
Look up the English word/phrase "%s" and provide ALL its different meanings with word types.

For EACH meaning, provide:
1. "type" - Word type (n = noun, v = verb, adj = adjective, adv = adverb, phr = phrasal verb, idiom = idiom)
2. "turkishMeaning" - Turkish translation for this specific meaning
3. "englishDefinition" - Brief English definition
4. "example" - An example sentence using the word in this specific meaning
5. "exampleTranslation" - Turkish translation of the example sentence

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
""".formatted(word, word, word);

        String system = "You are a comprehensive English-Turkish dictionary. Always return valid JSON. Be thorough and include all word types and meanings.";
        return callJson(system, prompt, 900, 0.3);
    }

    public AiJsonResult dictionaryGenerateSpecificSentence(String word, String translation, String context) {
        String prompt = "Generate a new, simple English sentence using the word '%s' specifically in the sense of '%s' (%s). Return valid JSON: { \"sentence\": \"...\" }"
                .formatted(word, translation, context);
        String system = "You are a helper generating specific example sentences. Return valid JSON only.";
        return callJson(system, prompt, 200, 0.7);
    }

    public AiJsonResult dictionaryExplainWordInSentence(String word, String sentence) {
        String prompt = "Explain the meaning of the word '%s' inside this specific sentence: '%s'. Provide the definition in Turkish, keeping it very short/concise (max 15 words). Return ONLY valid JSON. Format: { \"definition\": \"...\" }"
                .formatted(word, sentence);
        String system = "You are a dictionary helper. Return valid JSON.";
        return callJson(system, prompt, 120, 0.3);
    }

    public AiJsonResult generateReadingPassage(String level) {
        Map<String, Map<String, String>> levelConfig = new HashMap<>();
        levelConfig.put("Beginner", Map.of(
                "wordCount", "80-120",
                "sentences", "very short and simple sentences (5-8 words)",
                "vocabulary", "basic everyday words, no idioms",
                "topics", "daily life (family, food, hobbies)",
                "grammar", "present simple tense only",
                "questionDifficulty", "direct, answer explicitly in text"
        ));
        levelConfig.put("Elementary", Map.of(
                "wordCount", "120-160",
                "sentences", "short sentences with basic conjunctions (and, but, because)",
                "vocabulary", "common words, simple phrasal verbs",
                "topics", "travel, school, jobs, weather",
                "grammar", "present and past simple tenses",
                "questionDifficulty", "mostly direct, one inference question"
        ));
        levelConfig.put("Intermediate", Map.of(
                "wordCount", "160-220",
                "sentences", "mix of simple and compound sentences",
                "vocabulary", "wider range, some topic-specific terms",
                "topics", "technology, health, environment, culture",
                "grammar", "various tenses, passive voice",
                "questionDifficulty", "mix of direct and inference questions"
        ));
        levelConfig.put("Upper-Intermediate", Map.of(
                "wordCount", "220-280",
                "sentences", "complex sentences with subordinate clauses",
                "vocabulary", "academic vocabulary, idioms, collocations",
                "topics", "science, economics, social issues",
                "grammar", "conditionals, relative clauses, modal verbs",
                "questionDifficulty", "inference and analysis required"
        ));
        levelConfig.put("Advanced", Map.of(
                "wordCount", "280-350",
                "sentences", "sophisticated sentence structures, varied length",
                "vocabulary", "advanced academic and specialized terms",
                "topics", "philosophy, politics, scientific research",
                "grammar", "all tenses, subjunctive, inversions",
                "questionDifficulty", "critical thinking and synthesis required"
        ));
        Map<String, String> config = levelConfig.getOrDefault(level, levelConfig.get("Intermediate"));

        String prompt = """
Generate a reading passage for English learners. Strictly follow these constraints:

LEVEL: %s
WORD COUNT: %s words (strictly within this range)
SENTENCE STYLE: %s
VOCABULARY: %s
TOPIC CATEGORY: %s
GRAMMAR FOCUS: %s
QUESTION STYLE: %s

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
                level,
                config.get("wordCount"),
                config.get("sentences"),
                config.get("vocabulary"),
                config.get("topics"),
                config.get("grammar"),
                config.get("questionDifficulty")
        );

        String system = "You are a professional English exam preparation assistant. Generate content that EXACTLY matches the specified level constraints. Return strictly valid JSON with no markdown formatting.";
        return callJson(system, prompt, 1400, 0.7);
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
        return callJson("Return valid JSON only.", prompt, 450, 0.9);
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

        return callJson("Return valid JSON only.", prompt, 900, 0.5);
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
        return callJson(systemContent, userContent, 4000, 0.85);
    }

    private AiJsonResult callJson(String systemPrompt, String userPrompt, Integer maxTokens, Double temperature) {
        List<Map<String, String>> messages = new ArrayList<>();
        messages.add(Map.of("role", "system", "content", systemPrompt));
        messages.add(Map.of("role", "user", "content", userPrompt));

        GroqService.ChatCompletionResult completion = groqService.chatCompletionWithUsage(messages, true, maxTokens, temperature);
        String raw = completion != null ? completion.content() : null;
        String cleaned = normalizeJson(raw);

        try {
            Object parsed = objectMapper.readValue(cleaned, Object.class);
            if (!(parsed instanceof Map)) {
                throw new IllegalArgumentException("Expected JSON object");
            }
            @SuppressWarnings("unchecked")
            Map<String, Object> map = (Map<String, Object>) parsed;
            return new AiJsonResult(
                    map,
                    completion != null ? completion.totalTokens() : 0,
                    completion != null ? completion.promptTokens() : 0,
                    completion != null ? completion.completionTokens() : 0
            );
        } catch (Exception ex) {
            // Last attempt: try to parse as Map directly from cleaned string.
            try {
                Map<String, Object> map = objectMapper.readValue(cleaned, new TypeReference<Map<String, Object>>() {});
                return new AiJsonResult(
                        map,
                        completion != null ? completion.totalTokens() : 0,
                        completion != null ? completion.promptTokens() : 0,
                        completion != null ? completion.completionTokens() : 0
                );
            } catch (Exception ignored) {
                throw new RuntimeException("Failed to parse AI JSON response", ex);
            }
        }
    }

    private String normalizeJson(String raw) {
        if (raw == null) {
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
}

