package com.ingilizce.calismaapp.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ingilizce.calismaapp.entity.DailyContent;
import com.ingilizce.calismaapp.repository.DailyContentRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.util.*;

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

    private final DailyContentRepository dailyContentRepository;
    private final GroqService groqService;
    private final ObjectMapper objectMapper;
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
            return decodePayload(cached.get().getPayloadJson());
        }

        synchronized (generationLock) {
            cached = dailyContentRepository.findByContentDateAndContentType(normalized, contentType);
            if (cached.isPresent()) {
                return decodePayload(cached.get().getPayloadJson());
            }

            String payloadJson = null;
            if (groqApiKey != null && !groqApiKey.isBlank()) {
                try {
                    payloadJson = generateDailyExamPackPayload(normalized, normalizedExam);
                } catch (Exception e) {
                    log.warn("Daily exam pack generation failed date={} exam={}: {}",
                            normalized, normalizedExam, e.toString());
                }
            } else {
                log.info("Groq API key not configured; daily exam pack will use fallback data");
            }

            if (payloadJson == null || payloadJson.isBlank()) {
                return fallbackPayload(normalized, normalizedExam);
            }

            try {
                dailyContentRepository.save(new DailyContent(normalized, contentType, payloadJson));
            } catch (DataIntegrityViolationException ignored) {
                // Another instance may have inserted concurrently.
            }

            return decodePayload(payloadJson);
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

    private String generateDailyExamPackPayload(LocalDate date, String exam) throws Exception {
        List<String> topics = List.of(
                "Grammar",
                "Vocabulary",
                "Cloze Test",
                "Sentence Completion",
                "Reading"
        );

        // Keep output stable and machine-readable.
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
                """.formatted(exam.toUpperCase(Locale.ROOT), exam, date, topics);

        List<Map<String, String>> messages = new ArrayList<>();
        messages.add(Map.of("role", "system",
                "content", "You are a helpful exam-prep assistant. Return only valid JSON."));
        messages.add(Map.of("role", "user", "content", prompt));

        String content = groqService.chatCompletion(messages, true);
        if (content == null || content.isBlank()) {
            throw new IllegalStateException("Groq returned empty content");
        }

        JsonNode node = parseLenientJsonObject(content);
        if (node == null || !node.isObject()) {
            throw new IllegalStateException("Groq daily exam payload is not a JSON object");
        }
        return objectMapper.writeValueAsString(node);
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
            return Map.of("exam", "yds", "date", LocalDate.now().toString(), "topics", List.of());
        }
        try {
            JsonNode root = objectMapper.readTree(payloadJson);
            return objectMapper.convertValue(root, Map.class);
        } catch (Exception e) {
            return Map.of("exam", "yds", "date", LocalDate.now().toString(), "topics", List.of());
        }
    }

    private Map<String, Object> fallbackPayload(LocalDate date, String exam) {
        // Deterministic, minimal fallback to keep UI stable without Groq.
        Map<String, Object> q1 = Map.of(
                "id", 1,
                "question", "Choose the correct option: She ____ to the airport yesterday.",
                "options", Map.of(
                        "A", "go",
                        "B", "goes",
                        "C", "went",
                        "D", "gone",
                        "E", "going"
                ),
                "answer", "C",
                "explanation", "Past simple is used for completed actions in the past."
        );

        List<Map<String, Object>> five = List.of(q1, q1, q1, q1, q1);
        List<Map<String, Object>> topics = List.of(
                Map.of("topic", "Grammar", "questions", five),
                Map.of("topic", "Vocabulary", "questions", five),
                Map.of("topic", "Cloze Test", "questions", five),
                Map.of("topic", "Sentence Completion", "questions", five),
                Map.of("topic", "Reading", "questions", five)
        );

        return Map.of(
                "exam", exam,
                "date", date.toString(),
                "topics", topics,
                "fallback", true
        );
    }
}

