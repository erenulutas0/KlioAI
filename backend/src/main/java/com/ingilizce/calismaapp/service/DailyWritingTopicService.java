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
import java.util.Map;
import java.util.Optional;

@Service
public class DailyWritingTopicService {

    private static final Logger log = LoggerFactory.getLogger(DailyWritingTopicService.class);
    private static final String CONTENT_TYPE_PREFIX = "daily_writing_v1_";

    private final DailyContentRepository dailyContentRepository;
    private final AiProxyService aiProxyService;
    private final ObjectMapper objectMapper;
    private final Object generationLock = new Object();

    public DailyWritingTopicService(DailyContentRepository dailyContentRepository,
                                    AiProxyService aiProxyService,
                                    ObjectMapper objectMapper) {
        this.dailyContentRepository = dailyContentRepository;
        this.aiProxyService = aiProxyService;
        this.objectMapper = objectMapper;
    }

    public Map<String, Object> getDailyWritingTopic(LocalDate date, String level) {
        LocalDate normalizedDate = date != null ? date : LocalDate.now();
        String normalizedLevel = DailyLevelSupport.normalizeLevel(level);
        String contentType = contentTypeForLevel(normalizedLevel);

        Optional<DailyContent> cached = dailyContentRepository
                .findByContentDateAndContentType(normalizedDate, contentType);
        if (cached.isPresent()) {
            return normalizePayload(decodePayload(cached.get().getPayloadJson()), normalizedDate, normalizedLevel, contentType);
        }

        synchronized (generationLock) {
            cached = dailyContentRepository.findByContentDateAndContentType(normalizedDate, contentType);
            if (cached.isPresent()) {
                return normalizePayload(decodePayload(cached.get().getPayloadJson()), normalizedDate, normalizedLevel, contentType);
            }

            String payloadJson;
            try {
                payloadJson = generatePayload(normalizedDate, normalizedLevel, contentType);
            } catch (Exception e) {
                log.warn("Daily writing topic generation failed date={} level={}: {}",
                        normalizedDate, normalizedLevel, e.toString());
                payloadJson = toJsonString(fallbackPayload(normalizedDate, normalizedLevel, contentType));
            }

            try {
                dailyContentRepository.save(new DailyContent(normalizedDate, contentType, payloadJson));
            } catch (DataIntegrityViolationException ignored) {
                // Another request/instance inserted concurrently.
            }

            return normalizePayload(decodePayload(payloadJson), normalizedDate, normalizedLevel, contentType);
        }
    }

    private String generatePayload(LocalDate date, String level, String contentType) {
        String wordCount = DailyLevelSupport.writingWordCountForLevel(level);
        AiProxyService.AiJsonResult generated = aiProxyService.generateWritingTopic(level, wordCount);

        Map<String, Object> payload = new LinkedHashMap<>();
        if (generated != null && generated.json() != null) {
            payload.putAll(generated.json());
        }

        ensureWritingPayloadShape(payload, level, wordCount, date);
        payload.put("daily", true);
        payload.put("level", level);
        payload.put("cefrLevel", level);
        payload.put("wordCount", wordCount);
        payload.put("dateUtc", date.toString());
        payload.put("contentType", contentType);
        payload.put("topicId", date + ":" + level);
        return toJsonString(payload);
    }

    private void ensureWritingPayloadShape(Map<String, Object> payload,
                                           String level,
                                           String wordCount,
                                           LocalDate date) {
        if (payload == null) {
            return;
        }
        Object topic = payload.get("topic");
        Object description = payload.get("description");
        boolean hasTopic = topic instanceof String s && !s.isBlank();
        boolean hasDescription = description instanceof String s && !s.isBlank();
        if (hasTopic && hasDescription) {
            return;
        }

        payload.clear();
        payload.putAll(fallbackPayload(date, level, contentTypeForLevel(level)));
        payload.put("wordCount", wordCount);
    }

    private Map<String, Object> fallbackPayload(LocalDate date, String level, String contentType) {
        String prompt = switch (level) {
            case "A1" -> "Describe your favorite day of the week and explain why you like it.";
            case "A2" -> "Write about a memorable trip with your family or friends.";
            case "B1" -> "Write about a challenge you faced while learning something new and how you solved it.";
            case "B2" -> "Discuss whether online learning can replace traditional classrooms.";
            case "C1" -> "Evaluate how social media influences personal identity and communication habits.";
            case "C2" -> "Analyze the balance between technological progress and ethical responsibility in modern societies.";
            default -> "Write about a meaningful experience that changed your perspective.";
        };

        String description = "Use clear structure (introduction, body, conclusion). "
                + "Support your ideas with examples and keep your language level-appropriate.";

        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("topic", prompt);
        payload.put("description", description);
        payload.put("level", level);
        payload.put("wordCount", DailyLevelSupport.writingWordCountForLevel(level));
        payload.put("fallback", true);
        payload.put("daily", true);
        payload.put("cefrLevel", level);
        payload.put("dateUtc", date.toString());
        payload.put("contentType", contentType);
        payload.put("topicId", date + ":" + level);
        return payload;
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

    private Map<String, Object> normalizePayload(Map<String, Object> payload,
                                                 LocalDate date,
                                                 String level,
                                                 String contentType) {
        Map<String, Object> normalized = new LinkedHashMap<>();
        if (payload != null) {
            normalized.putAll(payload);
        }
        if (!(normalized.get("topic") instanceof String s) || s.isBlank()) {
            normalized.putAll(fallbackPayload(date, level, contentType));
        }
        normalized.put("daily", true);
        normalized.put("level", level);
        normalized.put("cefrLevel", level);
        normalized.put("wordCount", DailyLevelSupport.writingWordCountForLevel(level));
        normalized.put("dateUtc", date.toString());
        normalized.put("contentType", contentType);
        normalized.put("topicId", date + ":" + level);
        return normalized;
    }

    private String toJsonString(Map<String, Object> payload) {
        try {
            return objectMapper.writeValueAsString(payload);
        } catch (Exception e) {
            throw new IllegalStateException("Failed to serialize daily writing payload", e);
        }
    }

    private String contentTypeForLevel(String level) {
        return CONTENT_TYPE_PREFIX + DailyLevelSupport.normalizeLevel(level).toLowerCase();
    }
}
