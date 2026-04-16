package com.ingilizce.calismaapp.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ingilizce.calismaapp.entity.DailyContent;
import com.ingilizce.calismaapp.repository.DailyContentRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

@Service
public class DailyReadingService {

    private static final Logger log = LoggerFactory.getLogger(DailyReadingService.class);
    private static final String CONTENT_TYPE_PREFIX = "daily_reading_v2_";

    private final DailyContentRepository dailyContentRepository;
    private final AiProxyService aiProxyService;
    private final ObjectMapper objectMapper;
    private final Object generationLock = new Object();

    public DailyReadingService(DailyContentRepository dailyContentRepository,
                               AiProxyService aiProxyService,
                               ObjectMapper objectMapper) {
        this.dailyContentRepository = dailyContentRepository;
        this.aiProxyService = aiProxyService;
        this.objectMapper = objectMapper;
    }

    public Map<String, Object> getDailyReading(LocalDate date, String level) {
        LocalDate normalizedDate = date != null ? date : LocalDate.now();
        String normalizedLevel = DailyLevelSupport.normalizeLevel(level);
        String contentType = contentTypeForLevel(normalizedLevel);

        Optional<DailyContent> cached = dailyContentRepository
                .findByContentDateAndContentType(normalizedDate, contentType);
        if (cached.isPresent()) {
            return decodePayload(cached.get().getPayloadJson());
        }

        synchronized (generationLock) {
            cached = dailyContentRepository.findByContentDateAndContentType(normalizedDate, contentType);
            if (cached.isPresent()) {
                return decodePayload(cached.get().getPayloadJson());
            }

            String payloadJson;
            try {
                payloadJson = generatePayload(normalizedDate, normalizedLevel, contentType);
            } catch (Exception e) {
                log.warn("Daily reading generation failed date={} level={}: {}",
                        normalizedDate, normalizedLevel, e.toString());
                payloadJson = toJsonString(fallbackPayload(normalizedDate, normalizedLevel, contentType));
            }

            try {
                dailyContentRepository.save(new DailyContent(normalizedDate, contentType, payloadJson));
            } catch (DataIntegrityViolationException ignored) {
                // Another request/instance inserted concurrently.
            }

            return decodePayload(payloadJson);
        }
    }

    private String generatePayload(LocalDate date, String level, String contentType) throws Exception {
        AiProxyService.AiJsonResult generated = aiProxyService.generateReadingPassage(
                level);

        Map<String, Object> payload = new LinkedHashMap<>();
        if (generated != null && generated.json() != null) {
            payload.putAll(generated.json());
        }

        ensureReadingPayloadShape(payload, date, level, contentType);
        payload.put("daily", true);
        payload.put("cefrLevel", level);
        payload.put("dateUtc", date.toString());
        payload.put("contentType", contentType);

        return toJsonString(payload);
    }

    private void ensureReadingPayloadShape(Map<String, Object> payload,
                                           LocalDate date,
                                           String level,
                                           String contentType) {
        if (payload == null) {
            return;
        }

        Object text = payload.get("text");
        Object questions = payload.get("questions");
        boolean hasValidText = text instanceof String s && !s.isBlank();
        boolean hasQuestions = questions instanceof List<?> list && !list.isEmpty();
        if (hasValidText && hasQuestions) {
            return;
        }

        payload.clear();
        payload.putAll(fallbackPayload(date, level, contentType));
    }

    private Map<String, Object> fallbackPayload(LocalDate date, String level, String contentType) {
        String text;
        List<Map<String, Object>> questions;

        switch (level) {
            case "A1" -> {
                text = "Tom wakes up at 7 o'clock. He eats breakfast with his family. "
                        + "Then he walks to school. After school, he plays football with his friends.";
                questions = List.of(
                        question("What time does Tom wake up?", "7 o'clock", "8 o'clock", "6 o'clock", "9 o'clock", "A"),
                        question("How does Tom go to school?", "By bus", "By bike", "He walks", "By car", "C"),
                        question("What does Tom do after school?", "He studies math", "He plays football", "He sleeps", "He watches TV", "B")
                );
            }
            case "A2" -> {
                text = "Merve likes cooking at home. She usually prepares dinner for her family on weekends. "
                        + "Last Sunday, she tried a new pasta recipe and everyone loved it.";
                questions = List.of(
                        question("What does Merve like?", "Running", "Cooking", "Drawing", "Singing", "B"),
                        question("When does she usually prepare dinner?", "Weekdays", "Mornings", "Weekends", "At night only", "C"),
                        question("What happened last Sunday?", "She visited friends", "She bought a car", "She tried a new recipe", "She stayed at work", "C")
                );
            }
            case "B1" -> {
                text = "Many students use short daily routines to improve their English. "
                        + "They read one article, write a few sentences, and review vocabulary. "
                        + "This method works because consistency is easier than long but rare study sessions.";
                questions = List.of(
                        question("Why does the method work?", "It is expensive", "It uses consistency", "It requires teachers", "It is very long", "B"),
                        question("What do students write?", "A full book", "A few sentences", "Only tests", "Nothing", "B"),
                        question("Which idea is emphasized?", "Study only once a week", "Long sessions are always better", "Small routines can be effective", "Vocabulary is unnecessary", "C")
                );
            }
            case "B2" -> {
                text = "Remote work offers flexibility, but it also demands self-discipline. "
                        + "People who plan clear boundaries between work and personal life are more likely to avoid burnout. "
                        + "Regular breaks and focused schedules improve both productivity and well-being.";
                questions = List.of(
                        question("What does remote work demand?", "Higher rent", "Self-discipline", "New uniforms", "Public transport", "B"),
                        question("What helps avoid burnout?", "No breaks", "Working late every day", "Clear boundaries", "Ignoring personal life", "C"),
                        question("What improves productivity?", "Regular breaks and schedules", "Random meetings", "Long commutes", "No planning", "A")
                );
            }
            case "C1" -> {
                text = "Public trust in institutions depends not only on outcomes but also on transparency. "
                        + "When decisions are explained clearly, people are more likely to accept short-term difficulties. "
                        + "In contrast, opaque processes often generate suspicion, even when policies are technically effective.";
                questions = List.of(
                        question("What is a key factor for public trust?", "Strict silence", "Transparency", "Lower taxes only", "Short announcements", "B"),
                        question("Why might people accept difficulties?", "They are forced", "Decisions are clearly explained", "Media is absent", "Policies are secret", "B"),
                        question("What can opaque processes create?", "Higher confidence", "Faster learning", "Suspicion", "Automatic approval", "C")
                );
            }
            case "C2" -> {
                text = "Contemporary innovation policy often rewards speed, yet durable progress depends on institutional patience. "
                        + "Breakthroughs emerge not merely from disruptive ideas but from iterative refinement, regulatory calibration, "
                        + "and long-horizon investment that tolerates temporary inefficiency. Societies that confuse novelty with value "
                        + "may optimize for visibility instead of resilience.";
                questions = List.of(
                        question("What does the passage suggest about breakthroughs?", "They appear instantly", "They need iterative refinement", "They reject regulation", "They avoid investment", "B"),
                        question("What risk is highlighted?", "Too much patience", "Optimizing for visibility over resilience", "Excessive regulation only", "Lack of novel ideas", "B"),
                        question("Which contrast is central?", "Novelty vs value", "Speed vs cost", "Talent vs training", "Research vs education", "A")
                );
            }
            default -> {
                text = "Learning is more effective when practice is regular. "
                        + "Even short sessions help learners build confidence over time.";
                questions = List.of(
                        question("What makes learning effective?", "Irregular practice", "Regular practice", "No repetition", "Long breaks", "B"),
                        question("What do short sessions build?", "Stress", "Confidence", "Confusion", "Silence", "B"),
                        question("How does progress happen?", "Over time", "In one hour", "Only with luck", "Without effort", "A")
                );
            }
        }

        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("title", "Daily Reading - " + level);
        payload.put("text", text);
        payload.put("wordCount", approximateWordCount(text));
        payload.put("questions", questions);
        payload.put("fallback", true);
        payload.put("daily", true);
        payload.put("cefrLevel", level);
        payload.put("dateUtc", date.toString());
        payload.put("contentType", contentType);
        return payload;
    }

    private Map<String, Object> question(String question,
                                         String a,
                                         String b,
                                         String c,
                                         String d,
                                         String correct) {
        return Map.of(
                "question", question,
                "options", List.of(a, b, c, d),
                "correctAnswer", correct,
                "explanation", "Read the passage carefully and choose the best option.",
                "correctAnswerQuote", ""
        );
    }

    private int approximateWordCount(String text) {
        if (text == null || text.isBlank()) {
            return 0;
        }
        return (int) java.util.Arrays.stream(text.trim().split("\\s+"))
                .filter(token -> token != null && !token.isBlank())
                .count();
    }

    private Map<String, Object> decodePayload(String payloadJson) {
        if (payloadJson == null || payloadJson.isBlank()) {
            return Map.of();
        }
        try {
            return objectMapper.readValue(payloadJson, Map.class);
        } catch (Exception e) {
            return Map.of();
        }
    }

    private String toJsonString(Map<String, Object> payload) {
        try {
            return objectMapper.writeValueAsString(payload);
        } catch (Exception e) {
            throw new IllegalStateException("Failed to serialize daily reading payload", e);
        }
    }

    private String contentTypeForLevel(String level) {
        return CONTENT_TYPE_PREFIX + DailyLevelSupport.normalizeLevel(level).toLowerCase();
    }
}
