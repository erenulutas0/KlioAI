package com.ingilizce.calismaapp.controller;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ingilizce.calismaapp.dto.PracticeSentence;
import com.ingilizce.calismaapp.service.ChatbotService;
import com.ingilizce.calismaapp.service.WordService;
import com.ingilizce.calismaapp.service.GrammarCheckService;
import com.ingilizce.calismaapp.service.AiRateLimitService;
import com.ingilizce.calismaapp.service.AiTokenQuotaService;
import com.ingilizce.calismaapp.service.AiProxyService;
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
import java.time.ZoneOffset;
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
    private AiProxyService aiProxyService;

    @Autowired
    private ClientIpResolver clientIpResolver;

    @Value("${cache.sentences.ttl:604800}") // Default: 7 days
    private long cacheTtlSeconds;

    @Value("${cache.dictionary.ttl:86400}") // Default: 1 day
    private long dictionaryCacheTtlSeconds;

    private final ObjectMapper objectMapper;
    private static final String CACHE_KEY_PREFIX = "sentences:";
    private static final String DICTIONARY_CACHE_KEY_PREFIX = "dictionary:";
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

    private boolean checkLegacySubscription(Long userId) {
        return userRepository.findById(userId)
                .map(com.ingilizce.calismaapp.entity.User::isSubscriptionActive)
                .orElse(false);
    }

    private ResponseEntity<Map<String, Object>> enforceAiAccess(Long userId, String scope) {
        ResponseEntity<Map<String, Object>> quotaLimit = enforceAiTokenQuota(userId, scope);
        if (quotaLimit != null) {
            return quotaLimit;
        }
        if (aiTokenQuotaService == null) {
            if (!checkLegacySubscription(userId)) {
                return ResponseEntity.status(HttpStatus.FORBIDDEN)
                        .body(Map.of("error", "Subscription expired or not active."));
            }
            return null;
        }
        AiTokenQuotaService.Entitlement entitlement = aiTokenQuotaService.getEntitlement(userId);
        if (entitlement == null && !checkLegacySubscription(userId)) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN)
                    .body(Map.of("error", "Subscription expired or not active."));
        }
        return null;
    }

    @PostMapping("/generate-sentences")
    public ResponseEntity<Map<String, Object>> generateSentences(@RequestBody Map<String, Object> request,
            @RequestHeader("X-User-Id") Long userId,
            HttpServletRequest httpRequest) {
        ResponseEntity<Map<String, Object>> accessLimit = enforceAiAccess(userId, "generate-sentences");
        if (accessLimit != null) {
            return accessLimit;
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
        boolean fresh = request.get("fresh") != null &&
                Boolean.parseBoolean(request.get("fresh").toString());

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

            Optional<List<PracticeSentence>> cachedSentences = fresh
                    ? Optional.empty()
                    : loadSentencesFromCache(cacheKey);
            if (cachedSentences.isPresent()) {
                allSentences = cachedSentences.get();
                cached = true;
            } else {
                StringBuilder levelLengthInfo = new StringBuilder();
                levelLengthInfo.append("Return EXACTLY 5 sentences inside a JSON object with key 'sentences'.\n");
                levelLengthInfo.append("Target word: ").append(normalizedWord).append("\n");
                levelLengthInfo.append("Requested level/length combinations:\n");
                for (String level : levels) {
                    for (String length : lengths) {
                        levelLengthInfo.append(String.format("- Level: %s, Length: %s\n", level, length));
                    }
                }
                levelLengthInfo.append(
                        "Distribute the 5 sentences across these combinations as evenly as possible.\n");
                levelLengthInfo.append("Use genuinely different grammar patterns and contexts across the 5 sentences.\n");
                levelLengthInfo.append(
                        "Avoid generic textbook frames and avoid paraphrasing the same idea with tiny wording changes.\n");
                levelLengthInfo.append(
                        "If the word has multiple natural senses/collocations, cover more than one.\n");
                levelLengthInfo.append(
                        "Lengths must be meaningfully different: short=4-8 words, medium=9-15 words, long=16+ words.");
                if (fresh) {
                    levelLengthInfo.append("\nGenerate a fresh new set. Avoid reusing common previous examples.");
                    levelLengthInfo.append("\nvariationSeed=").append(System.currentTimeMillis());
                }

                String message = levelLengthInfo.toString();

                ChatbotService.AiCallResult llm = chatbotService.generateSentences(message);
                consumeAiTokens(userId, "generate-sentences", llm.totalTokens());
                String jsonResponse = llm.content();
                allSentences = sanitizePracticeSentences(
                        parsePracticeSentencesWithFallback(jsonResponse, normalizedWord));

                if (allSentences.size() > 5) {
                    allSentences = allSentences.subList(0, 5);
                }

                if (!fresh) {
                    storeSentencesToCache(cacheKey, allSentences);
                }
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

    private List<PracticeSentence> parsePracticeSentencesWithFallback(String rawResponse, String targetWord) {
        String normalized = normalizeSentenceJsonPayload(rawResponse);
        try {
            List<PracticeSentence> strict = parsePracticeSentencesStrict(normalized);
            if (!strict.isEmpty()) {
                return strict;
            }
            throw new IllegalArgumentException("Parsed sentence list is empty");
        } catch (Exception strictEx) {
            List<PracticeSentence> recovered = parsePracticeSentencesLenient(rawResponse);
            if (!recovered.isEmpty()) {
                log.warn("Recovered {} practice sentences from malformed LLM output.", recovered.size(), strictEx);
                return recovered;
            }
            List<PracticeSentence> freeTextRecovered = parsePracticeSentencesFromFreeText(rawResponse);
            if (!freeTextRecovered.isEmpty()) {
                log.warn("Recovered {} practice sentences from free-text LLM output.", freeTextRecovered.size(), strictEx);
                return freeTextRecovered;
            }
            List<PracticeSentence> deterministicFallback = buildDeterministicFallbackSentences(targetWord);
            log.warn("Using deterministic sentence fallback for word='{}' after malformed/empty LLM output.", targetWord, strictEx);
            return deterministicFallback;
        }
    }

    private String normalizeSentenceJsonPayload(String rawResponse) {
        if (rawResponse == null) {
            return "";
        }
        String jsonResponse = rawResponse.trim();
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
        return jsonResponse;
    }

    private List<PracticeSentence> parsePracticeSentencesStrict(String jsonResponse) throws Exception {
        if (jsonResponse == null || jsonResponse.isBlank()) {
            return List.of();
        }

        Object parsed = objectMapper.readValue(jsonResponse, Object.class);
        List<PracticeSentence> sentences = new ArrayList<>();
        if (parsed instanceof List<?> list) {
            for (Object item : list) {
                if (item instanceof Map<?, ?> mapRaw) {
                    @SuppressWarnings("unchecked")
                    Map<String, Object> map = (Map<String, Object>) mapRaw;
                    PracticeSentence ps = toPracticeSentence(map);
                    if (ps != null) {
                        sentences.add(ps);
                    }
                }
            }
            return sentences;
        }

        if (parsed instanceof Map<?, ?> mapRaw) {
            @SuppressWarnings("unchecked")
            Map<String, Object> map = (Map<String, Object>) mapRaw;
            if (map.containsKey("sentences") && map.get("sentences") instanceof List<?> wrapped) {
                for (Object item : wrapped) {
                    if (item instanceof Map<?, ?> itemRaw) {
                        @SuppressWarnings("unchecked")
                        Map<String, Object> itemMap = (Map<String, Object>) itemRaw;
                        PracticeSentence ps = toPracticeSentence(itemMap);
                        if (ps != null) {
                            sentences.add(ps);
                        }
                    }
                }
                return sentences;
            }

            PracticeSentence single = toPracticeSentence(map);
            if (single != null) {
                sentences.add(single);
            }
            return sentences;
        }

        throw new IllegalArgumentException("Unexpected JSON format for practice sentences");
    }

    private List<PracticeSentence> parsePracticeSentencesLenient(String rawResponse) {
        if (rawResponse == null || rawResponse.isBlank()) {
            return List.of();
        }

        String normalized = normalizeSentenceJsonPayload(rawResponse);
        List<PracticeSentence> recovered = new ArrayList<>();

        Matcher objectMatcher = Pattern.compile("\\{[^{}]*}").matcher(normalized);
        while (objectMatcher.find() && recovered.size() < 5) {
            String chunk = objectMatcher.group();
            try {
                Map<String, Object> item = objectMapper.readValue(chunk, new TypeReference<Map<String, Object>>() {
                });
                PracticeSentence ps = toPracticeSentence(item);
                if (ps != null) {
                    recovered.add(ps);
                }
            } catch (Exception ignored) {
                // best-effort recovery
            }
        }
        if (!recovered.isEmpty()) {
            return recovered;
        }

        List<String> english = extractJsonFieldValues(normalized, "englishSentence");
        if (english.isEmpty()) {
            english = extractJsonFieldValues(normalized, "english_sentence");
        }
        List<String> translations = extractJsonFieldValues(normalized, "turkishFullTranslation");
        if (translations.isEmpty()) {
            translations = extractJsonFieldValues(normalized, "turkishTranslation");
        }
        if (translations.isEmpty()) {
            translations = extractJsonFieldValues(normalized, "turkish_translation");
        }

        for (int i = 0; i < english.size() && recovered.size() < 5; i++) {
            String en = cleanExtractedValue(english.get(i));
            if (en.isBlank()) {
                continue;
            }
            String tr = i < translations.size() ? cleanExtractedValue(translations.get(i)) : "";
            recovered.add(new PracticeSentence(en, tr, tr));
        }
        return recovered;
    }

    private List<PracticeSentence> parsePracticeSentencesFromFreeText(String rawResponse) {
        if (rawResponse == null || rawResponse.isBlank()) {
            return List.of();
        }

        String cleaned = rawResponse
                .replace("```json", "")
                .replace("```", "")
                .trim();
        if (cleaned.isBlank()) {
            return List.of();
        }

        List<PracticeSentence> recovered = new ArrayList<>();
        Set<String> unique = new LinkedHashSet<>();

        String[] lines = cleaned.split("\\r?\\n");
        for (String rawLine : lines) {
            if (recovered.size() >= 5) {
                break;
            }
            PracticeSentence sentence = parseFreeTextLine(rawLine);
            if (sentence == null) {
                continue;
            }
            String dedupe = sentence.englishSentence().toLowerCase(Locale.ROOT);
            if (unique.add(dedupe)) {
                recovered.add(sentence);
            }
        }

        if (!recovered.isEmpty()) {
            return recovered;
        }

        Matcher matcher = Pattern.compile("[^.!?\\n]+[.!?]?").matcher(cleaned);
        while (matcher.find() && recovered.size() < 5) {
            PracticeSentence sentence = parseFreeTextLine(matcher.group());
            if (sentence == null) {
                continue;
            }
            String dedupe = sentence.englishSentence().toLowerCase(Locale.ROOT);
            if (unique.add(dedupe)) {
                recovered.add(sentence);
            }
        }
        return recovered;
    }

    private PracticeSentence parseFreeTextLine(String rawLine) {
        if (rawLine == null) {
            return null;
        }
        String line = rawLine.trim();
        if (line.isBlank()) {
            return null;
        }

        line = line.replaceAll("^[-*•\\d\\).:]+\\s*", "").trim();
        if (line.isBlank()) {
            return null;
        }
        if (line.startsWith("{") || line.startsWith("[") || line.startsWith("\"")) {
            return null;
        }
        if (line.contains("englishSentence") || line.contains("turkishTranslation")) {
            return null;
        }

        String english = line;
        String turkish = "";
        String[] separators = { " - ", " — ", " => ", " : " };
        for (String separator : separators) {
            int idx = line.indexOf(separator);
            if (idx > 0 && idx < line.length() - separator.length()) {
                english = line.substring(0, idx).trim();
                turkish = line.substring(idx + separator.length()).trim();
                break;
            }
        }

        if (!isLikelySentence(english)) {
            return null;
        }
        if (!english.matches(".*[.!?]$")) {
            english = english + ".";
        }

        String turkishClean = cleanExtractedValue(turkish);
        return new PracticeSentence(english, turkishClean, turkishClean);
    }

    private boolean isLikelySentence(String text) {
        if (text == null || text.isBlank()) {
            return false;
        }
        String normalized = text.trim();
        if (normalized.length() < 8) {
            return false;
        }
        long words = Arrays.stream(normalized.split("\\s+"))
                .filter(token -> !token.isBlank())
                .count();
        if (words < 3) {
            return false;
        }
        return normalized.matches(".*[A-Za-z].*");
    }

    private List<PracticeSentence> buildDeterministicFallbackSentences(String targetWord) {
        String word = (targetWord == null || targetWord.isBlank()) ? "word" : targetWord.trim();
        return List.of(
                new PracticeSentence("I am practicing the word " + word + " in a sentence.", "", ""),
                new PracticeSentence("She used " + word + " while speaking with her teacher.", "", ""),
                new PracticeSentence("We wrote a short paragraph that includes " + word + ".", "", ""),
                new PracticeSentence("Can you make a clear example sentence with " + word + "?", "", ""),
                new PracticeSentence("They repeated " + word + " to remember its meaning better.", "", ""));
    }

    private PracticeSentence toPracticeSentence(Map<String, Object> map) {
        if (map == null || map.isEmpty()) {
            return null;
        }
        String english = firstNonBlankString(map, "englishSentence", "english_sentence", "sentence");
        if (english.isBlank()) {
            return null;
        }
        String turkish = firstNonBlankString(map, "turkishTranslation", "turkish_translation", "turkish");
        String turkishFull = firstNonBlankString(map, "turkishFullTranslation", "turkish_full_translation");

        if (turkishFull.isBlank()) {
            turkishFull = turkish;
        }
        if (turkish.isBlank()) {
            turkish = turkishFull;
        }
        return new PracticeSentence(english, turkish, turkishFull);
    }

    private List<PracticeSentence> sanitizePracticeSentences(List<PracticeSentence> sentences) {
        if (sentences == null || sentences.isEmpty()) {
            return List.of();
        }

        List<PracticeSentence> sanitized = new ArrayList<>();
        Set<String> seenEnglish = new LinkedHashSet<>();
        for (PracticeSentence sentence : sentences) {
            if (sentence == null || sentence.englishSentence() == null) {
                continue;
            }
            String english = sentence.englishSentence().trim();
            if (english.isBlank()) {
                continue;
            }

            String dedupeKey = english
                    .toLowerCase(Locale.ROOT)
                    .replaceAll("[^a-z0-9\\s]", " ")
                    .replaceAll("\\s+", " ")
                    .trim();
            if (dedupeKey.isBlank() || !seenEnglish.add(dedupeKey)) {
                continue;
            }

            String turkish = sentence.turkishTranslation() != null ? sentence.turkishTranslation().trim() : "";
            String turkishFull = sentence.turkishFullTranslation() != null ? sentence.turkishFullTranslation().trim() : "";
            sanitized.add(new PracticeSentence(english, turkish, turkishFull));
        }
        return sanitized;
    }

    private String firstNonBlankString(Map<String, Object> map, String... keys) {
        for (String key : keys) {
            Object value = map.get(key);
            if (value == null) {
                continue;
            }
            String text = String.valueOf(value).trim();
            if (!text.isBlank()) {
                return text;
            }
        }
        return "";
    }

    private List<String> extractJsonFieldValues(String text, String fieldName) {
        if (text == null || text.isBlank()) {
            return List.of();
        }
        String patternText = "\"" + Pattern.quote(fieldName) + "\"\\s*:\\s*\"((?:\\\\.|[^\"\\\\])*)\"";
        Pattern pattern = Pattern.compile(patternText);
        Matcher matcher = pattern.matcher(text);
        List<String> values = new ArrayList<>();
        while (matcher.find()) {
            values.add(matcher.group(1));
        }
        return values;
    }

    private String cleanExtractedValue(String value) {
        if (value == null) {
            return "";
        }
        return value
                .replace("\\\"", "\"")
                .replace("\\n", " ")
                .replace("\\r", " ")
                .replace("\\t", " ")
                .replace("\\\\", "\\")
                .trim();
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

    private Optional<Map<String, Object>> loadMapFromCache(String cacheKey) {
        try {
            if (redisTemplate == null || cacheKey == null || cacheKey.isBlank()) {
                return Optional.empty();
            }
            ValueOperations<String, String> ops = redisTemplate.opsForValue();
            if (ops == null) {
                return Optional.empty();
            }
            String cachedJson = ops.get(cacheKey);
            if (cachedJson == null || cachedJson.isBlank()) {
                return Optional.empty();
            }
            Map<String, Object> payload = objectMapper.readValue(cachedJson, new TypeReference<Map<String, Object>>() {
            });
            return Optional.of(payload);
        } catch (Exception ignored) {
            return Optional.empty();
        }
    }

    private void storeMapToCache(String cacheKey, Map<String, Object> payload, long ttlSeconds) {
        if (redisTemplate == null || cacheKey == null || cacheKey.isBlank() || payload == null || payload.isEmpty()) {
            return;
        }
        try {
            ValueOperations<String, String> ops = redisTemplate.opsForValue();
            if (ops == null) {
                return;
            }
            String serialized = objectMapper.writeValueAsString(payload);
            if (ttlSeconds > 0) {
                ops.set(cacheKey, serialized, Duration.ofSeconds(ttlSeconds));
            } else {
                ops.set(cacheKey, serialized);
            }
        } catch (Exception ignored) {
            // Dictionary cache failures should not affect response path.
        }
    }

    private String normalizeCacheToken(Object raw) {
        if (raw == null) {
            return "";
        }
        String normalized = raw.toString()
                .trim()
                .toLowerCase(Locale.ROOT)
                .replaceAll("\\s+", "-");
        return normalized.length() > 120 ? normalized.substring(0, 120) : normalized;
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
        ResponseEntity<Map<String, Object>> accessLimit = enforceAiAccess(userId, "check-grammar");
        if (accessLimit != null) {
            return accessLimit;
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
        ResponseEntity<Map<String, Object>> accessLimit = enforceAiAccess(userId, "check-translation");
        if (accessLimit != null) {
            return accessLimit;
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
        ResponseEntity<Map<String, Object>> accessLimit = enforceAiAccess(userId, "chat");
        if (accessLimit != null) {
            return accessLimit;
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
        ResponseEntity<Map<String, Object>> accessLimit = enforceAiAccess(userId, "speaking-generate");
        if (accessLimit != null) {
            return accessLimit;
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
        ResponseEntity<Map<String, Object>> accessLimit = enforceAiAccess(userId, "speaking-evaluate");
        if (accessLimit != null) {
            return accessLimit;
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

    // ==================== DICTIONARY / READING / WRITING / EXAMS (Server-side AI Proxy) ====================

    @PostMapping("/dictionary/lookup")
    public ResponseEntity<Map<String, Object>> dictionaryLookup(@RequestBody Map<String, Object> request,
            @RequestHeader("X-User-Id") Long userId,
            HttpServletRequest httpRequest) {
        ResponseEntity<Map<String, Object>> accessLimit = enforceAiAccess(userId, "dictionary-lookup");
        if (accessLimit != null) return accessLimit;
        ResponseEntity<Map<String, Object>> aiLimit = enforceAiRateLimit(userId, httpRequest, "dictionary-lookup");
        if (aiLimit != null) return aiLimit;

        String word = request.get("word") != null ? request.get("word").toString() : null;
        if (word == null || word.trim().isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("error", "word is required"));
        }

        String normalizedWord = normalizeCacheToken(word);
        String cacheKey = DICTIONARY_CACHE_KEY_PREFIX + "lookup:" + normalizedWord;
        try {
            Optional<Map<String, Object>> cached = loadMapFromCache(cacheKey);
            if (cached.isPresent()) {
                return ResponseEntity.ok(cached.get());
            }

            AiProxyService.AiJsonResult result = aiProxyService.dictionaryLookup(word.trim());
            consumeAiTokens(userId, "dictionary-lookup", result.totalTokens());
            Map<String, Object> response = result.json() != null
                    ? result.json()
                    : Map.of("word", word.trim(), "meanings", List.of());
            storeMapToCache(cacheKey, response, dictionaryCacheTtlSeconds);
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            log.error("dictionaryLookup failed userId={} word={}", userId, word, e);
            return ResponseEntity.internalServerError().body(Map.of("error", "Dictionary lookup failed."));
        }
    }

    @PostMapping("/dictionary/lookup-detailed")
    public ResponseEntity<Map<String, Object>> dictionaryLookupDetailed(@RequestBody Map<String, Object> request,
            @RequestHeader("X-User-Id") Long userId,
            HttpServletRequest httpRequest) {
        ResponseEntity<Map<String, Object>> accessLimit = enforceAiAccess(userId, "dictionary-lookup-detailed");
        if (accessLimit != null) return accessLimit;
        ResponseEntity<Map<String, Object>> aiLimit = enforceAiRateLimit(userId, httpRequest, "dictionary-lookup-detailed");
        if (aiLimit != null) return aiLimit;

        String word = request.get("word") != null ? request.get("word").toString() : null;
        if (word == null || word.trim().isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("error", "word is required"));
        }

        String normalizedWord = normalizeCacheToken(word);
        String cacheKey = DICTIONARY_CACHE_KEY_PREFIX + "lookup-detailed:" + normalizedWord;
        try {
            Optional<Map<String, Object>> cached = loadMapFromCache(cacheKey);
            if (cached.isPresent()) {
                return ResponseEntity.ok(cached.get());
            }

            AiProxyService.AiJsonResult result = aiProxyService.dictionaryLookupDetailed(word.trim());
            consumeAiTokens(userId, "dictionary-lookup-detailed", result.totalTokens());
            Map<String, Object> response = result.json() != null
                    ? result.json()
                    : Map.of("word", word.trim(), "meanings", List.of());
            storeMapToCache(cacheKey, response, dictionaryCacheTtlSeconds);
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            log.error("dictionaryLookupDetailed failed userId={} word={}", userId, word, e);
            return ResponseEntity.internalServerError().body(Map.of("error", "Dictionary lookup failed."));
        }
    }

    @PostMapping("/dictionary/explain")
    public ResponseEntity<Map<String, Object>> dictionaryExplain(@RequestBody Map<String, Object> request,
            @RequestHeader("X-User-Id") Long userId,
            HttpServletRequest httpRequest) {
        ResponseEntity<Map<String, Object>> accessLimit = enforceAiAccess(userId, "dictionary-explain");
        if (accessLimit != null) return accessLimit;
        ResponseEntity<Map<String, Object>> aiLimit = enforceAiRateLimit(userId, httpRequest, "dictionary-explain");
        if (aiLimit != null) return aiLimit;

        String word = request.get("word") != null ? request.get("word").toString() : null;
        String sentence = request.get("sentence") != null ? request.get("sentence").toString() : null;
        if (word == null || word.trim().isEmpty() || sentence == null || sentence.trim().isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("error", "word and sentence are required"));
        }

        String cacheKey = DICTIONARY_CACHE_KEY_PREFIX + "explain:"
                + normalizeCacheToken(word) + ":" + normalizeCacheToken(sentence);
        try {
            Optional<Map<String, Object>> cached = loadMapFromCache(cacheKey);
            if (cached.isPresent()) {
                return ResponseEntity.ok(cached.get());
            }

            AiProxyService.AiJsonResult result = aiProxyService.dictionaryExplainWordInSentence(word.trim(), sentence.trim());
            consumeAiTokens(userId, "dictionary-explain", result.totalTokens());
            Map<String, Object> response = result.json() != null
                    ? result.json()
                    : Map.of("definition", "");
            storeMapToCache(cacheKey, response, dictionaryCacheTtlSeconds);
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            log.error("dictionaryExplain failed userId={} word={}", userId, word, e);
            return ResponseEntity.internalServerError().body(Map.of("error", "Dictionary explain failed."));
        }
    }

    @PostMapping("/dictionary/generate-specific-sentence")
    public ResponseEntity<Map<String, Object>> dictionaryGenerateSpecificSentence(@RequestBody Map<String, Object> request,
            @RequestHeader("X-User-Id") Long userId,
            HttpServletRequest httpRequest) {
        ResponseEntity<Map<String, Object>> accessLimit = enforceAiAccess(userId, "dictionary-specific-sentence");
        if (accessLimit != null) return accessLimit;
        ResponseEntity<Map<String, Object>> aiLimit = enforceAiRateLimit(userId, httpRequest, "dictionary-specific-sentence");
        if (aiLimit != null) return aiLimit;

        String word = request.get("word") != null ? request.get("word").toString() : null;
        String translation = request.get("translation") != null ? request.get("translation").toString() : null;
        String context = request.get("context") != null ? request.get("context").toString() : null;
        if (word == null || word.trim().isEmpty() || translation == null || translation.trim().isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("error", "word and translation are required"));
        }

        String cacheKey = DICTIONARY_CACHE_KEY_PREFIX + "specific-sentence:"
                + normalizeCacheToken(word) + ":" + normalizeCacheToken(translation) + ":"
                + normalizeCacheToken(context);
        try {
            Optional<Map<String, Object>> cached = loadMapFromCache(cacheKey);
            if (cached.isPresent()) {
                return ResponseEntity.ok(cached.get());
            }

            AiProxyService.AiJsonResult result = aiProxyService.dictionaryGenerateSpecificSentence(
                    word.trim(),
                    translation.trim(),
                    context != null ? context.trim() : "");
            consumeAiTokens(userId, "dictionary-specific-sentence", result.totalTokens());
            Map<String, Object> response = result.json() != null
                    ? result.json()
                    : Map.of("sentence", "");
            storeMapToCache(cacheKey, response, dictionaryCacheTtlSeconds);
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            log.error("dictionaryGenerateSpecificSentence failed userId={} word={}", userId, word, e);
            return ResponseEntity.internalServerError().body(Map.of("error", "Sentence generation failed."));
        }
    }

    @PostMapping("/reading/generate")
    public ResponseEntity<Map<String, Object>> generateReadingPassage(@RequestBody Map<String, Object> request,
            @RequestHeader("X-User-Id") Long userId,
            HttpServletRequest httpRequest) {
        ResponseEntity<Map<String, Object>> accessLimit = enforceAiAccess(userId, "reading-generate");
        if (accessLimit != null) return accessLimit;
        ResponseEntity<Map<String, Object>> aiLimit = enforceAiRateLimit(userId, httpRequest, "reading-generate");
        if (aiLimit != null) return aiLimit;

        String level = request.get("level") != null ? request.get("level").toString() : "Intermediate";
        try {
            AiProxyService.AiJsonResult result = aiProxyService.generateReadingPassage(level);
            consumeAiTokens(userId, "reading-generate", result.totalTokens());
            return ResponseEntity.ok(result.json());
        } catch (Exception e) {
            log.error("generateReadingPassage failed userId={} level={}", userId, level, e);
            return ResponseEntity.internalServerError().body(Map.of("error", "Reading generation failed."));
        }
    }

    @PostMapping("/writing/generate-topic")
    public ResponseEntity<Map<String, Object>> generateWritingTopic(@RequestBody Map<String, Object> request,
            @RequestHeader("X-User-Id") Long userId,
            HttpServletRequest httpRequest) {
        ResponseEntity<Map<String, Object>> accessLimit = enforceAiAccess(userId, "writing-topic");
        if (accessLimit != null) return accessLimit;
        ResponseEntity<Map<String, Object>> aiLimit = enforceAiRateLimit(userId, httpRequest, "writing-topic");
        if (aiLimit != null) return aiLimit;

        String level = request.get("level") != null ? request.get("level").toString() : "Intermediate";
        String wordCount = request.get("wordCount") != null ? request.get("wordCount").toString() : "150-200";
        try {
            AiProxyService.AiJsonResult result = aiProxyService.generateWritingTopic(level, wordCount);
            consumeAiTokens(userId, "writing-topic", result.totalTokens());
            return ResponseEntity.ok(result.json());
        } catch (Exception e) {
            log.error("generateWritingTopic failed userId={} level={}", userId, level, e);
            return ResponseEntity.internalServerError().body(Map.of("error", "Writing topic generation failed."));
        }
    }

    @PostMapping("/writing/evaluate")
    @SuppressWarnings("unchecked")
    public ResponseEntity<Map<String, Object>> evaluateWriting(@RequestBody Map<String, Object> request,
            @RequestHeader("X-User-Id") Long userId,
            HttpServletRequest httpRequest) {
        ResponseEntity<Map<String, Object>> accessLimit = enforceAiAccess(userId, "writing-evaluate");
        if (accessLimit != null) return accessLimit;
        ResponseEntity<Map<String, Object>> aiLimit = enforceAiRateLimit(userId, httpRequest, "writing-evaluate");
        if (aiLimit != null) return aiLimit;

        String text = request.get("text") != null ? request.get("text").toString() : null;
        String level = request.get("level") != null ? request.get("level").toString() : "Intermediate";
        Map<String, Object> topic = request.get("topic") instanceof Map ? (Map<String, Object>) request.get("topic") : null;
        if (text == null || text.trim().isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("error", "text is required"));
        }

        try {
            AiProxyService.AiJsonResult result = aiProxyService.evaluateWriting(text, level, topic);
            consumeAiTokens(userId, "writing-evaluate", result.totalTokens());
            return ResponseEntity.ok(result.json());
        } catch (Exception e) {
            log.error("evaluateWriting failed userId={} level={}", userId, level, e);
            return ResponseEntity.internalServerError().body(Map.of("error", "Writing evaluation failed."));
        }
    }

    @PostMapping("/exam/generate")
    public ResponseEntity<Map<String, Object>> generateExamBundle(@RequestBody Map<String, Object> request,
            @RequestHeader("X-User-Id") Long userId,
            HttpServletRequest httpRequest) {
        ResponseEntity<Map<String, Object>> accessLimit = enforceAiAccess(userId, "exam-generate");
        if (accessLimit != null) return accessLimit;
        ResponseEntity<Map<String, Object>> aiLimit = enforceAiRateLimit(userId, httpRequest, "exam-generate");
        if (aiLimit != null) return aiLimit;

        try {
            AiProxyService.AiJsonResult result = aiProxyService.generateExamBundle(request);
            consumeAiTokens(userId, "exam-generate", result.totalTokens());
            return ResponseEntity.ok(result.json());
        } catch (Exception e) {
            log.error("generateExamBundle failed userId={}", userId, e);
            return ResponseEntity.internalServerError().body(Map.of("error", "Exam generation failed."));
        }
    }

    @GetMapping("/quota/status")
    public ResponseEntity<Map<String, Object>> getQuotaStatus(@RequestHeader("X-User-Id") Long userId) {
        if (aiTokenQuotaService == null) {
            Map<String, Object> payload = new HashMap<>();
            payload.put("success", true);
            payload.put("quotaEnabled", false);
            payload.put("aiAccessEnabled", false);
            payload.put("planCode", "UNKNOWN");
            payload.put("trialActive", false);
            payload.put("trialDaysRemaining", 0);
            payload.put("dateUtc", LocalDate.now(ZoneOffset.UTC).toString());
            payload.put("tokenLimit", 0);
            payload.put("tokensUsed", 0);
            payload.put("tokensRemaining", 0);
            payload.put("usagePercent", 0.0);
            payload.put("remainingPercent", 0.0);
            return ResponseEntity.ok(payload);
        }

        try {
            AiTokenQuotaService.Entitlement entitlement = aiTokenQuotaService.getEntitlement(userId);
            AiTokenQuotaService.Usage usage = aiTokenQuotaService.getGlobalUsage(userId);
            long tokenLimit = Math.max(0L, usage.tokenLimit());
            long tokensUsed = Math.max(0L, usage.tokensUsed());
            long tokensRemaining = tokenLimit > 0 ? Math.max(0L, tokenLimit - tokensUsed) : Math.max(0L, usage.tokensRemaining());
            if (entitlement == null) {
                entitlement = new AiTokenQuotaService.Entitlement("UNKNOWN", true, tokenLimit, false, 0);
            }

            double usagePercent = tokenLimit > 0 ? Math.min(100.0, (tokensUsed * 100.0) / tokenLimit) : 0.0;
            double remainingPercent = tokenLimit > 0 ? Math.max(0.0, 100.0 - usagePercent) : 0.0;

            Map<String, Object> payload = new HashMap<>();
            payload.put("success", true);
            payload.put("quotaEnabled", true);
            payload.put("aiAccessEnabled", entitlement.aiAccessEnabled());
            payload.put("planCode", entitlement.planCode());
            payload.put("trialActive", entitlement.trialActive());
            payload.put("trialDaysRemaining", entitlement.trialDaysRemaining());
            payload.put("dateUtc", LocalDate.now(ZoneOffset.UTC).toString());
            payload.put("tokenLimit", tokenLimit);
            payload.put("tokensUsed", tokensUsed);
            payload.put("tokensRemaining", tokensRemaining);
            payload.put("usagePercent", usagePercent);
            payload.put("remainingPercent", remainingPercent);
            return ResponseEntity.ok(payload);
        } catch (Exception e) {
            log.warn("Failed to read AI token quota status for userId={}", userId, e);
            Map<String, Object> payload = new HashMap<>();
            payload.put("success", true);
            payload.put("quotaEnabled", true);
            payload.put("aiAccessEnabled", false);
            payload.put("planCode", "UNKNOWN");
            payload.put("trialActive", false);
            payload.put("trialDaysRemaining", 0);
            payload.put("dateUtc", LocalDate.now(ZoneOffset.UTC).toString());
            payload.put("tokenLimit", 0);
            payload.put("tokensUsed", 0);
            payload.put("tokensRemaining", 0);
            payload.put("usagePercent", 0.0);
            payload.put("remainingPercent", 0.0);
            return ResponseEntity.ok(payload);
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

        boolean abusePenalty = ABUSE_BAN_REASON.equals(decision.reason()) || decision.penaltyLevel() > 0;
        Map<String, Object> payload = new HashMap<>();
        payload.put("error", abusePenalty
                ? String.format("Anormal hizda AI istegi algilandi. Gecici erisim kisitlandi (%d sn).",
                decision.retryAfterSeconds())
                : "AI istek limitiniz doldu. Lütfen daha sonra tekrar deneyin.");
        payload.put("success", false);
        payload.put("retryAfterSeconds", decision.retryAfterSeconds());
        payload.put("reason", decision.reason());
        if (abusePenalty) {
            payload.put("abuseWarning", "Tekrar ihlalde gecici ban suresi artar.");
            payload.put("banLevel", decision.penaltyLevel());
            payload.put("nextBanSeconds", decision.nextPenaltySeconds());
        }

        return ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS)
                .header("Retry-After", String.valueOf(decision.retryAfterSeconds()))
                .body(payload);
    }

    private ResponseEntity<Map<String, Object>> enforceAiTokenQuota(Long userId, String scope) {
        if (aiTokenQuotaService == null) {
            return null;
        }

        AiTokenQuotaService.Decision decision = aiTokenQuotaService.check(userId, scope);
        if (!decision.blocked()) {
            return null;
        }

        Map<String, Object> payload = new HashMap<>();
        payload.put("success", false);
        payload.put("reason", decision.reason());
        payload.put("tokenLimit", decision.tokenLimit());
        payload.put("tokensUsed", decision.tokensUsed());
        payload.put("tokensRemaining", decision.tokensRemaining());

        if ("ai-access-disabled".equalsIgnoreCase(decision.reason())) {
            payload.put("error", "AI ozellikleri su an pasif. Devam etmek icin premium plana gecin.");
            payload.put("upgradeRequired", true);
            return ResponseEntity.status(HttpStatus.FORBIDDEN).body(payload);
        }

        payload.put("error", "Günlük AI hakkınız bitti. Lütfen daha sonra tekrar deneyin.");
        payload.put("retryAfterSeconds", decision.retryAfterSeconds());
        return ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS)
                .header("Retry-After", String.valueOf(decision.retryAfterSeconds()))
                .body(payload);
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

    private static final String ABUSE_BAN_REASON = "abuse-ban";
}
