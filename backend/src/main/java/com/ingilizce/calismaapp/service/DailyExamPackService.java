package com.ingilizce.calismaapp.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ingilizce.calismaapp.entity.DailyContent;
import com.ingilizce.calismaapp.repository.DailyContentRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;

/**
 * Generates and serves a daily exam practice pack (YDS/YOKDIL style) once per day.
 * Goal: avoid per-user AI generation cost and prevent abuse.
 *
 * Storage: daily_content (Postgres) as source of truth.
 */
@Service
public class DailyExamPackService {

    private static final Logger log = LoggerFactory.getLogger(DailyExamPackService.class);

    // Keep content_type short (<= 50).
    private static final String CONTENT_TYPE_YDS = "daily_exam_yds_v1";
    private static final List<String> TOPIC_ORDER = List.of(
            "Grammar",
            "Vocabulary",
            "Cloze Test",
            "Sentence Completion",
            "Reading"
    );
    private static final List<String> OPTION_KEYS = List.of("A", "B", "C", "D", "E");
    private static final int QUESTIONS_PER_TOPIC = 5;

    private final DailyContentRepository dailyContentRepository;
    private final GroqService groqService;
    private final ObjectMapper objectMapper;
    @Autowired(required = false)
    private AiModelRoutingService aiModelRoutingService;
    private final Object generationLock = new Object();

    @Value("${groq.api.key:}")
    private String groqApiKey;

    public DailyExamPackService(DailyContentRepository dailyContentRepository,
                                GroqService groqService,
                                ObjectMapper objectMapper) {
        this.dailyContentRepository = dailyContentRepository;
        this.groqService = groqService;
        this.objectMapper = objectMapper;
    }

    public Map<String, Object> getDailyExamPack(LocalDate date, String exam) {
        LocalDate normalized = date != null ? date : LocalDate.now();
        String normalizedExam = normalizeExam(exam);
        String contentType = contentTypeFor(normalizedExam);

        Optional<DailyContent> cached = dailyContentRepository
                .findByContentDateAndContentType(normalized, contentType);
        if (cached.isPresent()) {
            return normalizePayload(decodePayload(cached.get().getPayloadJson()), normalized, normalizedExam);
        }

        synchronized (generationLock) {
            cached = dailyContentRepository.findByContentDateAndContentType(normalized, contentType);
            if (cached.isPresent()) {
                return normalizePayload(decodePayload(cached.get().getPayloadJson()), normalized, normalizedExam);
            }

            Map<String, Object> payload;
            if (groqApiKey != null && !groqApiKey.isBlank()) {
                try {
                    payload = generateDailyExamPackPayload(normalized, normalizedExam);
                } catch (Exception e) {
                    log.warn("Daily exam pack generation failed date={} exam={}: {}",
                            normalized, normalizedExam, e.toString());
                    payload = fallbackPayload(normalized, normalizedExam);
                }
            } else {
                log.info("Groq API key not configured; daily exam pack will use fallback data");
                payload = fallbackPayload(normalized, normalizedExam);
            }

            String payloadJson = toJsonString(payload);

            try {
                dailyContentRepository.save(new DailyContent(normalized, contentType, payloadJson));
            } catch (DataIntegrityViolationException ignored) {
                // Another instance may have inserted concurrently.
            }

            return payload;
        }
    }

    private String normalizeExam(String exam) {
        String raw = exam == null ? "" : exam.trim().toLowerCase(Locale.ROOT);
        if (raw.isBlank()) return "yds";
        if (raw.equals("yokdil")) return "yds"; // same format for now
        return raw;
    }

    private String contentTypeFor(String exam) {
        if ("yds".equals(exam)) return CONTENT_TYPE_YDS;
        // Default to yds for now.
        return CONTENT_TYPE_YDS;
    }

    private Map<String, Object> generateDailyExamPackPayload(LocalDate date, String exam) throws Exception {
        String prompt = """
                Generate a DAILY English exam practice pack for %s.

                Exam: %s
                Date seed: %s

                For each topic, generate exactly 5 multiple-choice questions.
                Topics: %s

                Return ONLY valid JSON (no markdown). The JSON must be an object with:
                - exam (String)
                - date (String, YYYY-MM-DD)
                - topics (Array)

                Each topics[] item must have:
                - topic (String)
                - questions (Array of 5)

                Each question must have:
                - id (Number 1-5)
                - question (String)
                - options (Object with keys A,B,C,D,E)
                - answer (String one of A,B,C,D,E)
                - explanation (String, short)
                """.formatted(exam.toUpperCase(Locale.ROOT), exam, date, TOPIC_ORDER);

        List<Map<String, String>> messages = new ArrayList<>();
        messages.add(Map.of("role", "system",
                "content", "You are a helpful exam-prep assistant. Return only valid JSON."));
        messages.add(Map.of("role", "user", "content", prompt));

        String content = groqService.chatCompletion(messages, true, resolveModelForScope("exam-daily-pack-generate"));
        if (content == null || content.isBlank()) {
            throw new IllegalStateException("Groq returned empty content");
        }

        JsonNode node = parseLenientJsonObject(content);
        if (node == null || !node.isObject()) {
            throw new IllegalStateException("Groq daily exam payload is not a JSON object");
        }

        Map<String, Object> payload = objectMapper.convertValue(node, Map.class);
        return normalizePayload(payload, date, exam);
    }

    private JsonNode parseLenientJsonObject(String raw) throws Exception {
        try {
            return objectMapper.readTree(raw);
        } catch (Exception ignored) {
            int start = raw.indexOf('{');
            int end = raw.lastIndexOf('}');
            if (start >= 0 && end > start) {
                String sliced = raw.substring(start, end + 1);
                return objectMapper.readTree(sliced);
            }
            throw ignored;
        }
    }

    private Map<String, Object> decodePayload(String payloadJson) {
        if (payloadJson == null || payloadJson.isBlank()) {
            return Map.of();
        }
        try {
            JsonNode root = objectMapper.readTree(payloadJson);
            return objectMapper.convertValue(root, Map.class);
        } catch (Exception e) {
            return Map.of();
        }
    }

    private Map<String, Object> normalizePayload(Map<String, Object> rawPayload,
                                                 LocalDate date,
                                                 String exam) {
        Map<String, Object> payload = rawPayload != null ? rawPayload : Map.of();
        Map<String, List<Map<String, Object>>> extractedTopics = extractQuestionsByTopic(payload);
        List<Map<String, Object>> topics = new ArrayList<>();
        boolean usedFallback = false;

        for (String topic : TOPIC_ORDER) {
            List<Map<String, Object>> fallbackQuestions = fallbackQuestionsFor(topic);
            List<Map<String, Object>> candidateQuestions = extractedTopics.getOrDefault(topic, List.of());
            List<Map<String, Object>> normalizedQuestions = new ArrayList<>();

            for (int i = 0; i < QUESTIONS_PER_TOPIC; i++) {
                Map<String, Object> fallbackQuestion = fallbackQuestions.get(i);
                Map<String, Object> candidate = i < candidateQuestions.size() ? candidateQuestions.get(i) : null;
                Map<String, Object> normalizedQuestion = normalizeQuestion(candidate, i + 1, fallbackQuestion);
                if (normalizedQuestion == fallbackQuestion) {
                    usedFallback = true;
                }
                normalizedQuestions.add(normalizedQuestion);
            }

            Map<String, Object> topicEntry = new LinkedHashMap<>();
            topicEntry.put("topic", topic);
            topicEntry.put("questions", normalizedQuestions);
            topics.add(topicEntry);
        }

        Map<String, Object> normalized = new LinkedHashMap<>();
        normalized.put("exam", exam);
        normalized.put("date", date.toString());
        normalized.put("topics", topics);
        normalized.put("fallback", usedFallback || Boolean.TRUE.equals(payload.get("fallback")));
        normalized.put("contentVersion", "v2");
        return normalized;
    }

    @SuppressWarnings("unchecked")
    private Map<String, List<Map<String, Object>>> extractQuestionsByTopic(Map<String, Object> payload) {
        Map<String, List<Map<String, Object>>> result = new LinkedHashMap<>();
        Object topicsValue = payload.get("topics");
        if (!(topicsValue instanceof List<?> topicList)) {
            return result;
        }

        for (Object topicEntry : topicList) {
            if (!(topicEntry instanceof Map<?, ?> rawTopicEntry)) {
                continue;
            }

            String topic = canonicalTopicName(rawTopicEntry.get("topic"));
            if (topic == null) {
                topic = canonicalTopicName(rawTopicEntry.get("name"));
            }
            if (topic == null) {
                continue;
            }

            Object questionsValue = rawTopicEntry.get("questions");
            if (!(questionsValue instanceof List<?> questionList)) {
                continue;
            }

            List<Map<String, Object>> questions = new ArrayList<>();
            for (Object questionEntry : questionList) {
                if (questionEntry instanceof Map<?, ?> rawQuestion) {
                    questions.add((Map<String, Object>) rawQuestion);
                }
            }
            result.put(topic, questions);
        }

        return result;
    }

    private String canonicalTopicName(Object rawTopicName) {
        String normalized = toNonBlankString(rawTopicName);
        if (normalized == null) {
            return null;
        }
        String lowered = normalized.toLowerCase(Locale.ROOT);
        if (lowered.contains("grammar")) return "Grammar";
        if (lowered.contains("vocabulary")) return "Vocabulary";
        if (lowered.contains("cloze")) return "Cloze Test";
        if (lowered.contains("sentence")) return "Sentence Completion";
        if (lowered.contains("reading")) return "Reading";
        return null;
    }

    private Map<String, Object> normalizeQuestion(Map<String, Object> candidate,
                                                  int id,
                                                  Map<String, Object> fallbackQuestion) {
        if (candidate == null || candidate.isEmpty()) {
            return fallbackQuestion;
        }

        String question = toNonBlankString(candidate.get("question"));
        if (question == null) {
            question = toNonBlankString(candidate.get("stem"));
        }

        Map<String, String> options = normalizeOptions(candidate.get("options"));
        String answer = normalizeAnswer(candidate.get("answer"));
        if (answer == null) {
            answer = normalizeAnswer(candidate.get("correct"));
        }
        String explanation = toNonBlankString(candidate.get("explanation"));
        if (explanation == null) {
            explanation = toNonBlankString(candidate.get("explanationEn"));
        }
        if (explanation == null) {
            explanation = toNonBlankString(candidate.get("explanationTr"));
        }

        if (question == null || options == null || answer == null || explanation == null) {
            return fallbackQuestion;
        }

        Map<String, Object> normalized = new LinkedHashMap<>();
        normalized.put("id", id);
        normalized.put("question", question);
        normalized.put("options", options);
        normalized.put("answer", answer);
        normalized.put("explanation", explanation);
        return normalized;
    }

    private Map<String, String> normalizeOptions(Object rawOptions) {
        if (rawOptions instanceof Map<?, ?> optionMap) {
            LinkedHashMap<String, String> normalized = new LinkedHashMap<>();
            for (String key : OPTION_KEYS) {
                String value = toNonBlankString(optionMap.get(key));
                if (value == null) {
                    return null;
                }
                normalized.put(key, value);
            }
            return normalized;
        }

        if (rawOptions instanceof List<?> optionList && optionList.size() >= OPTION_KEYS.size()) {
            LinkedHashMap<String, String> normalized = new LinkedHashMap<>();
            for (int i = 0; i < OPTION_KEYS.size(); i++) {
                String value = toNonBlankString(optionList.get(i));
                if (value == null) {
                    return null;
                }
                normalized.put(OPTION_KEYS.get(i), value);
            }
            return normalized;
        }

        return null;
    }

    private String normalizeAnswer(Object rawAnswer) {
        String answer = toNonBlankString(rawAnswer);
        if (answer == null) {
            return null;
        }
        String normalized = answer.trim().toUpperCase(Locale.ROOT);
        return OPTION_KEYS.contains(normalized) ? normalized : null;
    }

    private String toNonBlankString(Object value) {
        if (value == null) {
            return null;
        }
        String text = value.toString().trim();
        return text.isEmpty() ? null : text;
    }

    private Map<String, Object> fallbackPayload(LocalDate date, String exam) {
        Map<String, Object> payload = new LinkedHashMap<>();
        List<Map<String, Object>> topics = new ArrayList<>();
        for (String topic : TOPIC_ORDER) {
            Map<String, Object> topicEntry = new LinkedHashMap<>();
            topicEntry.put("topic", topic);
            topicEntry.put("questions", fallbackQuestionsFor(topic));
            topics.add(topicEntry);
        }
        payload.put("exam", exam);
        payload.put("date", date.toString());
        payload.put("topics", topics);
        payload.put("fallback", true);
        payload.put("contentVersion", "v2");
        return payload;
    }

    private List<Map<String, Object>> fallbackQuestionsFor(String topic) {
        return switch (topic) {
            case "Grammar" -> List.of(
                    question(1, "Choose the correct option: If she ____ earlier, she would have caught the train.",
                            "left", "had left", "has left", "would leave", "was leaving", "B",
                            "Third conditional requires past perfect in the if-clause."),
                    question(2, "Select the best sentence: The report ____ by the committee before noon.",
                            "was reviewing", "had reviewed", "had been reviewed", "has reviewing", "reviewed", "C",
                            "Past perfect passive shows the review was completed before another past point."),
                    question(3, "Choose the correct option: Hardly ____ the meeting started when the lights went out.",
                            "has", "had", "did", "was", "would", "B",
                            "After 'Hardly', inversion with past perfect is required."),
                    question(4, "Choose the correct option: Neither the manager nor the assistants ____ willing to delay the launch.",
                            "was", "is", "are", "be", "has been", "C",
                            "With 'neither...nor', the verb agrees with the nearer plural subject."),
                    question(5, "Choose the correct option: She insisted that the final draft ____ submitted that evening.",
                            "is", "was", "be", "has been", "being", "C",
                            "After 'insist', the mandative subjunctive uses the bare infinitive.")
            );
            case "Vocabulary" -> List.of(
                    question(1, "Choose the closest meaning of 'meticulous' in the sentence: The researcher kept meticulous records of every observation.",
                            "careless", "detailed", "uncertain", "hasty", "temporary", "B",
                            "'Meticulous' means very careful and precise."),
                    question(2, "Choose the best word to complete the sentence: The minister's comments were too ____ to answer the public's concerns.",
                            "vague", "vivid", "steady", "mature", "dense", "A",
                            "'Vague' fits because the comments lacked clarity."),
                    question(3, "Choose the closest meaning of 'feasible': The board approved only the most feasible proposal.",
                            "profitable", "practical", "urgent", "creative", "costly", "B",
                            "'Feasible' refers to something that can realistically be done."),
                    question(4, "Choose the best word to complete the sentence: Repeated delays began to ____ the company's reputation.",
                            "enhance", "erode", "clarify", "restore", "broaden", "B",
                            "'Erode' means gradually weaken or damage."),
                    question(5, "Choose the closest meaning of 'notion' in the sentence: The study challenges the notion that talent is fixed.",
                            "warning", "assumption", "reward", "method", "conflict", "B",
                            "'Notion' here means a belief or assumption.")
            );
            case "Cloze Test" -> List.of(
                    question(1, "Complete the sentence: Although the sample size was limited, the findings were still ____ enough to justify further study.",
                            "cautious", "tentative", "compelling", "accidental", "fragile", "C",
                            "'Compelling' best matches evidence strong enough to support more research."),
                    question(2, "Complete the sentence: The team postponed the launch ____ the security audit had been finalized.",
                            "unless", "until", "despite", "whereas", "besides", "B",
                            "'Until' correctly expresses waiting for the audit to finish."),
                    question(3, "Complete the sentence: The author argues that innovation should be evaluated not only by speed ____ by long-term social benefit.",
                            "but also", "as if", "even though", "rather than", "in case", "A",
                            "The correlative pair is 'not only ... but also'."),
                    question(4, "Complete the sentence: Several participants withdrew from the survey, ____ reduced the reliability of the final results.",
                            "who", "that", "which", "what", "whom", "C",
                            "'Which' refers to the whole preceding clause."),
                    question(5, "Complete the sentence: By the time the policy was announced, the market ____ to the earlier rumors.",
                            "reacts", "has reacted", "had already reacted", "would react", "is reacting", "C",
                            "Past perfect shows the reaction happened before the announcement.")
            );
            case "Sentence Completion" -> List.of(
                    question(1, "Researchers now share preprint versions of their studies online, ____.",
                            "because the library closed early",
                            "which allows other experts to comment before formal publication",
                            "unless the experiment was cancelled",
                            "even if the equipment is broken",
                            "so that the conference was delayed",
                            "B",
                            "Only option B logically and grammatically completes the idea."),
                    question(2, "Public transport use increased sharply after the city introduced discounted student passes, ____.",
                            "although many stations were built decades ago",
                            "whereas the weather remained unstable throughout the month",
                            "suggesting that cost had been a major barrier for young commuters",
                            "because some citizens preferred walking on weekends",
                            "unless the roads are closed for repairs",
                            "C",
                            "Option C directly explains the observed increase."),
                    question(3, "The committee refused to approve the proposal in its current form, ____.",
                            "since the budget projections were based on unrealistic assumptions",
                            "while the corridor had recently been painted",
                            "even though the coffee machine was working properly",
                            "so the interns left before noon yesterday",
                            "unless the memo is translated into French",
                            "A",
                            "Option A gives a coherent reason for the refusal."),
                    question(4, "If universities want graduates to adapt to rapid technological change, ____.",
                            "the old building was renovated last summer",
                            "they should emphasize problem-solving as much as memorization",
                            "students had forgotten their identity cards",
                            "the final bell rings at exactly five",
                            "many departments were founded in the 1980s",
                            "B",
                            "Option B presents the logical educational response."),
                    question(5, "The documentary was praised for presenting a complex issue in clear language, ____.",
                            "yet several viewers still found the conclusion simplistic",
                            "unless the tickets had been refunded immediately",
                            "because the studio moved to another district",
                            "while the actors were waiting backstage",
                            "so that the airport security line became shorter",
                            "A",
                            "Option A extends the evaluation with a balanced contrast.")
            );
            case "Reading" -> List.of(
                    question(1, "Read the text and answer the question:\nCities that invest in shaded walking routes often discover that residents walk more regularly, not because distances shrink, but because the experience becomes more comfortable.\nAccording to the text, what mainly increases walking?",
                            "Shorter distances", "Lower fuel prices", "Improved comfort", "Stricter traffic fines", "More parking lots", "C",
                            "The passage says residents walk more because the experience becomes more comfortable."),
                    question(2, "Read the text and answer the question:\nSome companies assume that remote work automatically improves productivity. However, studies show that the gains are strongest when teams also establish clear communication norms.\nWhat is the main point of the text?",
                            "Remote work never improves productivity", "Communication structure matters alongside remote work", "Most teams prefer office work", "Productivity depends only on salary", "Studies on remote work are unreliable", "B",
                            "The passage emphasizes that remote work alone is not enough without clear norms."),
                    question(3, "Read the text and answer the question:\nMuseums increasingly use digital guides, but visitors still value human-led tours because guides can respond to curiosity in real time and adapt their explanations.\nWhy are human-led tours still valued?",
                            "They are always cheaper", "They use less technology", "They can adapt instantly to visitors", "They shorten the museum visit", "They remove the need for exhibits", "C",
                            "Human guides remain useful because they can answer and adapt in real time."),
                    question(4, "Read the text and answer the question:\nA pilot program gave first-year students weekly feedback instead of only midterm reports. At the end of the term, attendance and assignment completion both improved.\nWhich conclusion is best supported?",
                            "Weekly feedback may help engagement", "Midterms should be removed from all courses", "Attendance matters more than assignments", "First-year students dislike feedback", "The pilot program reduced course difficulty", "A",
                            "The observed improvement supports the idea that frequent feedback boosts engagement."),
                    question(5, "Read the text and answer the question:\nThe article argues that public trust grows when officials explain not just what decision was made, but how evidence and trade-offs were weighed.\nWhat does the article link to public trust?",
                            "Faster announcements", "Simple slogans", "Visible reasoning behind decisions", "Frequent leadership changes", "Reduced media coverage", "C",
                            "Trust is linked to transparent explanation of evidence and trade-offs.")
            );
            default -> List.of();
        };
    }

    private Map<String, Object> question(int id,
                                         String question,
                                         String a,
                                         String b,
                                         String c,
                                         String d,
                                         String e,
                                         String answer,
                                         String explanation) {
        Map<String, String> options = new LinkedHashMap<>();
        options.put("A", a);
        options.put("B", b);
        options.put("C", c);
        options.put("D", d);
        options.put("E", e);

        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("id", id);
        payload.put("question", question);
        payload.put("options", options);
        payload.put("answer", answer);
        payload.put("explanation", explanation);
        return payload;
    }

    private String toJsonString(Map<String, Object> payload) {
        try {
            return objectMapper.writeValueAsString(payload);
        } catch (Exception e) {
            throw new IllegalStateException("Failed to serialize daily exam pack payload", e);
        }
    }

    private String resolveModelForScope(String scope) {
        if (aiModelRoutingService == null) {
            return null;
        }
        return aiModelRoutingService.resolveModelForScope(scope);
    }
}
