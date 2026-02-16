package com.ingilizce.calismaapp.controller;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ingilizce.calismaapp.dto.PracticeSentence;
import com.ingilizce.calismaapp.service.ChatbotService;
import com.ingilizce.calismaapp.service.WordService;
import com.ingilizce.calismaapp.service.GrammarCheckService;
import com.ingilizce.calismaapp.service.AiRateLimitService;
import com.ingilizce.calismaapp.service.AiTokenQuotaService;
import com.ingilizce.calismaapp.entity.Word;
import com.ingilizce.calismaapp.security.ClientIpResolver;
import io.micrometer.core.instrument.MeterRegistry;
import jakarta.servlet.http.HttpServletRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.ValueOperations;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.Duration;
import java.time.LocalDate;
import java.util.*;
import java.util.concurrent.TimeUnit;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api/chatbot")
public class ChatbotController {
    private static final Logger log = LoggerFactory.getLogger(ChatbotController.class);

    @Autowired
    private ChatbotService chatbotService;

    @Autowired
    private WordService wordService;

    @Autowired
    private com.ingilizce.calismaapp.repository.UserRepository userRepository;

    @Autowired(required = false)
    private RedisTemplate<String, String> redisTemplate;

    @Autowired(required = false)
    private GrammarCheckService grammarCheckService;

    @Autowired(required = false)
    private MeterRegistry meterRegistry;

    @Autowired(required = false)
    private AiRateLimitService aiRateLimitService;

    @Autowired(required = false)
    private AiTokenQuotaService aiTokenQuotaService;

    @Autowired
    private ClientIpResolver clientIpResolver;

    @Value("${cache.sentences.ttl:604800}") // Default: 7 days
    private long cacheTtlSeconds;

    private final ObjectMapper objectMapper;
    private static final String CACHE_KEY_PREFIX = "sentences:";
    private static final String CACHE_LOOKUP_TOTAL_METRIC = "chatbot.sentences.cache.lookup.total";
    private static final String CACHE_LOOKUP_LATENCY_METRIC = "chatbot.sentences.cache.lookup.latency";
    private static final String CACHE_WRITE_TOTAL_METRIC = "chatbot.sentences.cache.write.total";

    public ChatbotController() {
        this.objectMapper = new ObjectMapper();
        this.objectMapper.configure(com.fasterxml.jackson.databind.DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES,
                false);
    }

    // Securely retrieve UserID from the authenticated session (JWT)
    // private Long getUserId() { ... }
    // In a real Spring Security setup, we get Principal from context.
    // For MVP without full Spring Security yet, we can't fully trust headers,
    // but for now we should rely on the Token passed in Controller/Filter layer.
    // Since we are not implementing full Spring Security filter chain in this step,
    // we will mock this SECURE behavior by assuming the upstream AuthFilter has
    // validated the token
    // and set the ID in a Request Attribute or ThreadLocal.

    private boolean checkSubscription(Long userId) {
        return userRepository.findById(userId)
                .map(com.ingilizce.calismaapp.entity.User::isSubscriptionActive)
                .orElse(false);
    }

    @PostMapping("/generate-sentences")
    public ResponseEntity<Map<String, Object>> generateSentences(@RequestBody Map<String, Object> request,
            @RequestHeader("X-User-Id") Long userId,
            HttpServletRequest httpRequest) {
        if (!checkSubscription(userId)) {
            return ResponseEntity.status(403).body(Map.of("error", "Subscription expired or not active."));
        }
        ResponseEntity<Map<String, Object>> aiLimit = enforceAiRateLimit(userId, httpRequest, "generate-sentences");
        if (aiLimit != null) {
            return aiLimit;
        }

        String word = (String) request.get("word");
        @SuppressWarnings("unchecked")
        List<String> levels = request.get("levels") != null ? (List<String>) request.get("levels")
                : java.util.Arrays.asList("B1");
        @SuppressWarnings("unchecked")
        List<String> lengths = request.get("lengths") != null ? (List<String>) request.get("lengths")
                : java.util.Arrays.asList("medium");
        boolean checkGrammar = request.get("checkGrammar") != null &&
                Boolean.parseBoolean(request.get("checkGrammar").toString());

        if (word == null || word.trim().isEmpty()) {
            Map<String, Object> error = new HashMap<>();
            error.put("error", "Please provide a word");
            return ResponseEntity.badRequest().body(error);
        }

        // Validate levels and lengths
        List<String> validLevels = java.util.Arrays.asList("A1", "A2", "B1", "B2", "C1", "C2");
        List<String> validLengths = java.util.Arrays.asList("short", "medium", "long");
        levels = levels.stream()
                .filter(validLevels::contains)
                .distinct()
                .sorted()
                .collect(Collectors.toList());
        lengths = lengths.stream()
                .filter(validLengths::contains)
                .distinct()
                .sorted()
                .collect(Collectors.toList());

        if (levels.isEmpty())
            levels = java.util.Arrays.asList("B1");
        if (lengths.isEmpty())
            lengths = java.util.Arrays.asList("medium");

        String normalizedWord = word.trim().toLowerCase();
        // Separate cache per user? Or global? Sentences are knowledge, so global is
        // fine.
        String cacheKey = CACHE_KEY_PREFIX + normalizedWord + ":" + String.join(",", levels) + ":"
                + String.join(",", lengths);

        try {
            List<PracticeSentence> allSentences;
            boolean cached = false;

            Optional<List<PracticeSentence>> cachedSentences = loadSentencesFromCache(cacheKey);
            if (cachedSentences.isPresent()) {
                allSentences = cachedSentences.get();
                cached = true;
            } else {
                ResponseEntity<Map<String, Object>> tokenLimit = enforceAiTokenQuota(userId, "generate-sentences");
                if (tokenLimit != null) {
                    return tokenLimit;
                }

                StringBuilder levelLengthInfo = new StringBuilder();
                levelLengthInfo.append("Generate 5 diverse sentences total, covering these combinations:\n");
                for (String level : levels) {
                    for (String length : lengths) {
                        levelLengthInfo.append(String.format("- Level: %s, Length: %s\n", level, length));
                    }
                }
                levelLengthInfo.append(
                        "Distribute the 5 sentences across these combinations. Make sentences diverse and cover different meanings if the word has multiple meanings.");

                String message = String.format("Target word: '%s'.\n%s", normalizedWord, levelLengthInfo.toString());

                ChatbotService.AiCallResult llm = chatbotService.generateSentences(message);
                consumeAiTokens(userId, "generate-sentences", llm.totalTokens());
                String jsonResponse = llm.content();

                // ... (Existing Parsing Logic)
                jsonResponse = jsonResponse.trim();
                jsonResponse = jsonResponse.replaceAll("```json", "").replaceAll("```", "").trim();

                int arrayStartIndex = jsonResponse.indexOf('[');
                if (arrayStartIndex > 0) {
                    jsonResponse = jsonResponse.substring(arrayStartIndex);
                }
                int arrayEndIndex = jsonResponse.lastIndexOf(']');
                if (arrayEndIndex > 0 && arrayEndIndex < jsonResponse.length() - 1) {
                    jsonResponse = jsonResponse.substring(0, arrayEndIndex + 1);
                }
                jsonResponse = jsonResponse.trim();
                jsonResponse = jsonResponse.replaceAll("\"turkishTransliteration\"", "\"turkishTranslation\"");
                jsonResponse = jsonResponse.replaceAll("\"turkish_translation\"", "\"turkishTranslation\"");
                jsonResponse = jsonResponse.replaceAll("\"turkish\"", "\"turkishTranslation\"");

                allSentences = new ArrayList<>();
                try {
                    Object parsed = objectMapper.readValue(jsonResponse, Object.class);

                    if (parsed instanceof List) {
                        allSentences = objectMapper.readValue(
                                jsonResponse,
                                new TypeReference<List<PracticeSentence>>() {
                                });
                    } else {
                        @SuppressWarnings("unchecked")
                        Map<String, Object> map = (Map<String, Object>) parsed;
                        if (map.containsKey("sentences") && map.get("sentences") instanceof List) {
                            allSentences = objectMapper.convertValue(
                                    map.get("sentences"),
                                    new TypeReference<List<PracticeSentence>>() {
                                    });
                        } else {
                            try {
                                PracticeSentence single = objectMapper.convertValue(parsed, PracticeSentence.class);
                                allSentences.add(single);
                            } catch (Exception ex) {
                                throw new RuntimeException("Unexpected JSON format", ex);
                            }
                        }
                    }
                } catch (Exception e) {
                    throw new RuntimeException("Failed to parse LLM response: " + e.getMessage(), e);
                }

                if (allSentences.size() > 5) {
                    allSentences = allSentences.subList(0, 5);
                }

                storeSentencesToCache(cacheKey, allSentences);
            }

            // ... (Existing Grammar Check)

            // ... (Existing Response Construction)
            List<String> sentences = allSentences.stream()
                    .map(PracticeSentence::englishSentence)
                    .collect(Collectors.toList());

            List<String> translations = allSentences.stream()
                    .map(ps -> ps.turkishFullTranslation() != null ? ps.turkishFullTranslation() : "")
                    .collect(Collectors.toList());

            Map<String, Object> result = new HashMap<>();
            result.put("sentences", sentences);
            result.put("translations", translations);
            result.put("count", sentences.size());
            result.put("cached", cached);

            return ResponseEntity.ok(result);
        } catch (Exception e) {
            log.error("Failed to generate sentences for userId={}, word={}", userId, request.get("word"), e);
            Map<String, Object> error = new HashMap<>();
            error.put("error", "Failed to generate sentences: " + e.getMessage());
            return ResponseEntity.internalServerError().body(error);
        }
    }

    private Optional<List<PracticeSentence>> loadSentencesFromCache(String cacheKey) {
        long startNs = System.nanoTime();
        String outcome = "miss";
        try {
            if (redisTemplate == null) {
                outcome = "disabled";
                return Optional.empty();
            }

            ValueOperations<String, String> ops = redisTemplate.opsForValue();
            if (ops == null) {
                outcome = "disabled";
                return Optional.empty();
            }

            String cachedJson = ops.get(cacheKey);
            if (cachedJson == null || cachedJson.isBlank()) {
                return Optional.empty();
            }

            List<PracticeSentence> cachedSentences = objectMapper.readValue(
                    cachedJson,
                    new TypeReference<List<PracticeSentence>>() {
                    });
            outcome = "hit";
            return Optional.of(cachedSentences);
        } catch (Exception e) {
            outcome = "error";
            return Optional.empty();
        } finally {
            recordCacheLookupMetric(outcome, System.nanoTime() - startNs);
        }
    }

    private void storeSentencesToCache(String cacheKey, List<PracticeSentence> sentences) {
        if (redisTemplate == null || sentences == null || sentences.isEmpty()) {
            recordCacheWriteMetric("skipped");
            return;
        }

        try {
            ValueOperations<String, String> ops = redisTemplate.opsForValue();
            if (ops == null) {
                recordCacheWriteMetric("skipped");
                return;
            }

            String serialized = objectMapper.writeValueAsString(sentences);
            if (cacheTtlSeconds > 0) {
                ops.set(cacheKey, serialized, Duration.ofSeconds(cacheTtlSeconds));
            } else {
                ops.set(cacheKey, serialized);
            }
            recordCacheWriteMetric("stored");
        } catch (Exception ignored) {
            // Cache failures must not affect user-facing sentence generation.
            recordCacheWriteMetric("error");
        }
    }

    private void recordCacheLookupMetric(String outcome, long latencyNanos) {
        if (meterRegistry == null) {
            return;
        }
        meterRegistry.counter(CACHE_LOOKUP_TOTAL_METRIC, "outcome", outcome).increment();
        meterRegistry.timer(CACHE_LOOKUP_LATENCY_METRIC, "outcome", outcome)
                .record(Math.max(0L, latencyNanos), TimeUnit.NANOSECONDS);
    }

    private void recordCacheWriteMetric(String outcome) {
        if (meterRegistry == null) {
            return;
        }
        meterRegistry.counter(CACHE_WRITE_TOTAL_METRIC, "outcome", outcome).increment();
    }

    @PostMapping("/check-grammar")
    public ResponseEntity<Map<String, Object>> checkGrammar(@RequestBody Map<String, String> request,
            @RequestHeader("X-User-Id") Long userId,
            HttpServletRequest httpRequest) {
        if (!checkSubscription(userId)) {
            return ResponseEntity.status(403).body(Map.of("error", "Subscription expired or not active."));
        }
        ResponseEntity<Map<String, Object>> aiLimit = enforceAiRateLimit(userId, httpRequest, "check-grammar");
        if (aiLimit != null) {
            return aiLimit;
        }

        String sentence = request.get("sentence");
        if (sentence == null || sentence.trim().isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("error", "Please provide a sentence"));
        }

        try {
            Map<String, Object> result = grammarCheckService.checkGrammar(sentence);
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            return ResponseEntity.internalServerError()
                    .body(Map.of("error", "Grammar check failed: " + e.getMessage()));
        }
    }

    @PostMapping("/check-translation")
    public ResponseEntity<Map<String, Object>> checkTranslation(@RequestBody Map<String, String> request,
            @RequestHeader("X-User-Id") Long userId,
            HttpServletRequest httpRequest) {
        if (!checkSubscription(userId)) {
            return ResponseEntity.status(403).body(Map.of("error", "Subscription expired or not active."));
        }
        ResponseEntity<Map<String, Object>> tokenLimit = enforceAiTokenQuota(userId, "check-translation");
        if (tokenLimit != null) {
            return tokenLimit;
        }
        ResponseEntity<Map<String, Object>> aiLimit = enforceAiRateLimit(userId, httpRequest, "check-translation");
        if (aiLimit != null) {
            return aiLimit;
        }

        return originalCheckTranslation(request, userId);
    }

    // Helper to keep existing logic cleaner while wrapping with auth check
    private ResponseEntity<Map<String, Object>> originalCheckTranslation(Map<String, String> request, Long userId) {
        String direction = request.getOrDefault("direction", "EN_TO_TR");
        String userTranslation = request.get("userTranslation");

        if (userTranslation == null) {
            return ResponseEntity.badRequest().body(Map.of("error", "Please provide translation"));
        }

        try {
            ChatbotService.AiCallResult response;
            if ("TR_TO_EN".equals(direction)) {
                String turkishSentence = request.get("turkishSentence");
                String englishRef = request.get("englishSentence");
                if (turkishSentence == null) {
                    return ResponseEntity.badRequest().body(Map.of("error", "Turkish sentence is required"));
                }
                String combinedMessage = "Turkish sentence: " + turkishSentence + ". User's English translation: "
                        + userTranslation + ".";
                if (englishRef != null)
                    combinedMessage += " (Reference: " + englishRef + ")";
                combinedMessage += " Evaluate this translation generously. Return ONLY JSON.";
                response = chatbotService.checkEnglishTranslation(combinedMessage);
            } else {
                String englishSentence = request.get("englishSentence");
                if (englishSentence == null) {
                    return ResponseEntity.badRequest().body(Map.of("error", "English sentence is required"));
                }
                String combinedMessage = "English sentence: " + englishSentence + ". User's Turkish translation: "
                        + userTranslation + ". Evaluate this translation generously. Return ONLY JSON.";
                response = chatbotService.checkTranslation(combinedMessage);
            }
            consumeAiTokens(userId, "check-translation", response != null ? response.totalTokens() : 0);
            return ResponseEntity.ok(parseJsonResponse(response != null ? response.content() : null));
        } catch (Exception e) {
            log.error("Failed to check translation", e);
            return ResponseEntity.internalServerError()
                    .body(Map.of("error", "Failed to check translation: " + e.getMessage()));
        }
    }

    private Map<String, Object> parseJsonResponse(String response) {
        Map<String, Object> result = new HashMap<>();

        try {
            // Clean response - remove markdown code blocks if present
            response = response.trim();
            response = response.replaceAll("```json", "").replaceAll("```", "").trim();

            // Try to extract JSON object
            int jsonStart = response.indexOf("{");
            int jsonEnd = response.lastIndexOf("}") + 1;

            if (jsonStart >= 0 && jsonEnd > jsonStart) {
                String jsonStr = response.substring(jsonStart, jsonEnd);

                // Parse isCorrect
                Pattern isCorrectPattern = Pattern.compile("\"isCorrect\"\\s*:\\s*(true|false)");
                Matcher isCorrectMatcher = isCorrectPattern.matcher(jsonStr);
                if (isCorrectMatcher.find()) {
                    result.put("isCorrect", Boolean.parseBoolean(isCorrectMatcher.group(1)));
                } else {
                    result.put("isCorrect", false);
                }

                // Extract correctTranslation
                Pattern correctPattern = Pattern.compile("\"correctTranslation\"\\s*:\\s*\"([^\"]+)\"");
                Matcher correctMatcher = correctPattern.matcher(jsonStr);
                if (correctMatcher.find()) {
                    result.put("correctTranslation", correctMatcher.group(1));
                } else {
                    result.put("correctTranslation", "");
                }

                // Extract feedback
                Pattern feedbackPattern = Pattern.compile("\"feedback\"\\s*:\\s*\"([^\"]+)\"");
                Matcher feedbackMatcher = feedbackPattern.matcher(jsonStr);
                if (feedbackMatcher.find()) {
                    result.put("feedback", feedbackMatcher.group(1));
                } else {
                    result.put("feedback", "Çeviri kontrol edildi.");
                }
            } else {
                // If no JSON found, try to infer from text
                boolean isCorrect = response.toLowerCase().contains("\"isCorrect\":true") ||
                        response.toLowerCase().contains("doğru") ||
                        (!response.toLowerCase().contains("incorrect") &&
                                !response.toLowerCase().contains("yanlış") &&
                                !response.toLowerCase().contains("\"isCorrect\":false"));

                result.put("isCorrect", isCorrect);
                result.put("correctTranslation", "");
                result.put("feedback", response);
            }
        } catch (Exception e) {
            // Fallback
            result.put("isCorrect", false);
            result.put("correctTranslation", "");
            result.put("feedback", "Çeviri kontrol edilemedi: " + e.getMessage());
        }

        return result;
    }

    @PostMapping("/save-to-today")
    @SuppressWarnings("unchecked")
    public ResponseEntity<Map<String, Object>> saveToToday(@RequestBody Map<String, Object> request,
            @RequestHeader("X-User-Id") Long userId) {
        // Note: Saving words doesn't necessarily require active subscription, but
        // generating them did.
        // We act largely as a proxy here.

        try {
            String englishWord = (String) request.get("englishWord");
            List<String> meanings = request.get("meanings") != null
                    ? (List<String>) request.get("meanings")
                    : new ArrayList<>();
            List<String> sentences = request.get("sentences") != null
                    ? (List<String>) request.get("sentences")
                    : new ArrayList<>();

            if (englishWord == null || englishWord.trim().isEmpty()) {
                return ResponseEntity.badRequest().body(Map.of("error", "English word is required"));
            }

            Word word = new Word();
            word.setUserId(userId);
            word.setEnglishWord(englishWord.trim());
            word.setTurkishMeaning(meanings != null ? String.join(", ", meanings) : "");
            word.setLearnedDate(LocalDate.now());
            word.setDifficulty("medium");

            Word savedWord = wordService.saveWord(word);

            if (sentences != null && !sentences.isEmpty()) {
                for (String sentenceStr : sentences) {
                    wordService.addSentence(
                            savedWord.getId(),
                            sentenceStr.trim(),
                            "",
                            "medium",
                            userId);
                }
            }

            // Reload word
            savedWord = wordService.getWordByIdAndUser(savedWord.getId(), userId).orElse(savedWord);

            Map<String, Object> result = new HashMap<>();
            result.put("success", true);
            result.put("word", savedWord);
            result.put("message", "Kelime ve cümleler bugünkü tarihe başarıyla eklendi.");
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            log.error("Failed to save word to today list for userId={}", userId, e);
            return ResponseEntity.internalServerError().body(Map.of("error", "Failed to save word: " + e.getMessage()));
        }
    }

    @PostMapping("/chat")
    public ResponseEntity<Map<String, Object>> chat(@RequestBody Map<String, String> request,
            @RequestHeader("X-User-Id") Long userId,
            HttpServletRequest httpRequest) {
        if (!checkSubscription(userId)) {
            return ResponseEntity.status(403).body(Map.of("error", "Subscription expired or not active."));
        }
        ResponseEntity<Map<String, Object>> tokenLimit = enforceAiTokenQuota(userId, "chat");
        if (tokenLimit != null) {
            return tokenLimit;
        }
        ResponseEntity<Map<String, Object>> aiLimit = enforceAiRateLimit(userId, httpRequest, "chat");
        if (aiLimit != null) {
            return aiLimit;
        }

        String message = request.get("message");
        if (message == null || message.trim().isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("error", "Please provide a message"));
        }

        try {
            String scenario = request.get("scenario");
            String scenarioContext = request.get("scenarioContext");
            ChatbotService.AiCallResult llm;
            if (scenario != null || scenarioContext != null) {
                llm = chatbotService.chat(message.trim(), scenario, scenarioContext);
            } else {
                llm = chatbotService.chat(message.trim());
            }
            consumeAiTokens(userId, "chat", llm.totalTokens());
            Map<String, Object> result = new HashMap<>();
            result.put("response", llm.content());
            result.put("timestamp", System.currentTimeMillis());
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            log.error("Failed to get chatbot response for userId={}", userId, e);
            return ResponseEntity.internalServerError()
                    .body(Map.of("error", "Failed to get response: " + e.getMessage()));
        }
    }

    @PostMapping("/speaking-test/generate-questions")
    public ResponseEntity<Map<String, Object>> generateSpeakingTestQuestions(@RequestBody Map<String, String> request,
            @RequestHeader("X-User-Id") Long userId,
            HttpServletRequest httpRequest) {
        if (!checkSubscription(userId)) {
            return ResponseEntity.status(403).body(Map.of("error", "Subscription expired or not active."));
        }
        ResponseEntity<Map<String, Object>> tokenLimit = enforceAiTokenQuota(userId, "speaking-generate");
        if (tokenLimit != null) {
            return tokenLimit;
        }
        ResponseEntity<Map<String, Object>> aiLimit = enforceAiRateLimit(userId, httpRequest, "speaking-generate");
        if (aiLimit != null) {
            return aiLimit;
        }

        String testType = request.get("testType");
        String part = request.get("part");

        if (testType == null || part == null) {
            return ResponseEntity.badRequest().body(Map.of("error", "Please provide testType and part"));
        }

        try {
            String message = String.format("Generate %s Speaking test questions for %s. Return ONLY JSON.", testType,
                    part);
            ChatbotService.AiCallResult llm = chatbotService.generateSpeakingTestQuestions(message);
            String response = llm.content();
            consumeAiTokens(userId, "speaking-generate", llm.totalTokens());

            response = response.trim();
            response = response.replaceAll("```json", "").replaceAll("```", "").trim();

            Map<String, Object> result = objectMapper.readValue(response, new TypeReference<Map<String, Object>>() {
            });
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            log.error("Failed to generate speaking test questions for userId={}", userId, e);
            return ResponseEntity.internalServerError()
                    .body(Map.of("error", "Failed to generate questions: " + e.getMessage()));
        }
    }

    @PostMapping("/speaking-test/evaluate")
    public ResponseEntity<Map<String, Object>> evaluateSpeakingTest(@RequestBody Map<String, String> request,
            @RequestHeader("X-User-Id") Long userId,
            HttpServletRequest httpRequest) {
        if (!checkSubscription(userId)) {
            return ResponseEntity.status(403).body(Map.of("error", "Subscription expired or not active."));
        }
        ResponseEntity<Map<String, Object>> tokenLimit = enforceAiTokenQuota(userId, "speaking-evaluate");
        if (tokenLimit != null) {
            return tokenLimit;
        }
        ResponseEntity<Map<String, Object>> aiLimit = enforceAiRateLimit(userId, httpRequest, "speaking-evaluate");
        if (aiLimit != null) {
            return aiLimit;
        }

        String testType = request.get("testType");
        String question = request.get("question");
        String response = request.get("response");

        if (testType == null || question == null || response == null) {
            return ResponseEntity.badRequest().body(Map.of("error", "Please provide testType, question, and response"));
        }

        try {
            String message = String.format(
                    "Evaluate this %s Speaking test response. Question: %s. Candidate's response: %s. Return ONLY JSON.",
                    testType, question, response);
            ChatbotService.AiCallResult llm = chatbotService.evaluateSpeakingTest(message);
            String llmResponse = llm.content();
            consumeAiTokens(userId, "speaking-evaluate", llm.totalTokens());

            llmResponse = llmResponse.trim();
            llmResponse = llmResponse.replaceAll("```json", "").replaceAll("```", "").trim();

            Map<String, Object> result = objectMapper.readValue(llmResponse, new TypeReference<Map<String, Object>>() {
            });
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            log.error("Failed to evaluate speaking test for userId={}", userId, e);
            return ResponseEntity.internalServerError()
                    .body(Map.of("error", "Failed to evaluate response: " + e.getMessage()));
        }
    }

    private ResponseEntity<Map<String, Object>> enforceAiRateLimit(Long userId,
                                                                    HttpServletRequest httpRequest,
                                                                    String scope) {
        if (aiRateLimitService == null) {
            return null;
        }

        AiRateLimitService.Decision decision = aiRateLimitService.checkAndConsume(
                userId,
                resolveClientIp(httpRequest),
                scope);

        if (!decision.blocked()) {
            return null;
        }

        return ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS)
                .header("Retry-After", String.valueOf(decision.retryAfterSeconds()))
                .body(Map.of(
                        "error", "AI request quota exceeded. Please retry later.",
                        "success", false,
                        "retryAfterSeconds", decision.retryAfterSeconds(),
                        "reason", decision.reason()));
    }

    private ResponseEntity<Map<String, Object>> enforceAiTokenQuota(Long userId, String scope) {
        if (aiTokenQuotaService == null) {
            return null;
        }

        AiTokenQuotaService.Decision decision = aiTokenQuotaService.check(userId, scope);
        if (!decision.blocked()) {
            return null;
        }

        return ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS)
                .header("Retry-After", String.valueOf(decision.retryAfterSeconds()))
                .body(Map.of(
                        "error", "Günlük AI hakkınız bitti. Lütfen daha sonra tekrar deneyin.",
                        "success", false,
                        "retryAfterSeconds", decision.retryAfterSeconds(),
                        "reason", decision.reason(),
                        "tokenLimit", decision.tokenLimit(),
                        "tokensUsed", decision.tokensUsed(),
                        "tokensRemaining", decision.tokensRemaining()
                ));
    }

    private void consumeAiTokens(Long userId, String scope, int tokens) {
        if (aiTokenQuotaService == null) {
            return;
        }
        // Best-effort: do not throw if quota bookkeeping fails.
        try {
            aiTokenQuotaService.consume(userId, scope, Math.max(0, tokens));
        } catch (Exception ignored) {
        }
    }

    private String resolveClientIp(HttpServletRequest request) {
        return clientIpResolver.resolve(request);
    }
}
