package com.ingilizce.calismaapp.controller;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ingilizce.calismaapp.dto.PracticeSentence;
import com.ingilizce.calismaapp.service.ChatbotService;
import com.ingilizce.calismaapp.service.LearningLanguageProfile;
import com.ingilizce.calismaapp.service.PromptCatalog;
import com.ingilizce.calismaapp.service.WordService;
import com.ingilizce.calismaapp.service.GrammarCheckService;
import com.ingilizce.calismaapp.service.AiRateLimitService;
import com.ingilizce.calismaapp.service.AiTokenQuotaService;
import com.ingilizce.calismaapp.service.AiProxyService;
import com.ingilizce.calismaapp.service.GroqSpeechToTextService;
import com.ingilizce.calismaapp.service.ProgressService;
import com.ingilizce.calismaapp.service.SentenceStarterTrackingService;
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
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

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
    private GroqSpeechToTextService speechToTextService;

    @Autowired
    private ClientIpResolver clientIpResolver;

    @Autowired(required = false)
    private ProgressService progressService;

    @Autowired(required = false)
    private SentenceStarterTrackingService sentenceStarterTrackingService;

    @Value("${cache.sentences.ttl:604800}") // Default: 7 days
    private long cacheTtlSeconds;

    @Value("${cache.dictionary.ttl:86400}") // Default: 1 day
    private long dictionaryCacheTtlSeconds;

    @Value("${app.ai.speech.max-audio-bytes:5242880}")
    private long speechMaxAudioBytes;

    @Value("${app.ai.speech.max-duration-seconds:60}")
    private long speechMaxDurationSeconds;

    @Value("${app.ai.speech.min-billed-seconds:10}")
    private long speechMinBilledSeconds;

    @Value("${app.ai.speech.tokens-per-billed-second:10}")
    private long speechTokensPerBilledSecond;

    private final ObjectMapper objectMapper;
    private static final String CACHE_KEY_PREFIX = "sentences:";
    private static final String DICTIONARY_CACHE_KEY_PREFIX = "dictionary:";
    private static final String CACHE_LOOKUP_TOTAL_METRIC = "chatbot.sentences.cache.lookup.total";
    private static final String CACHE_LOOKUP_LATENCY_METRIC = "chatbot.sentences.cache.lookup.latency";
    private static final String CACHE_WRITE_TOTAL_METRIC = "chatbot.sentences.cache.write.total";
    private static final java.util.regex.Pattern STARTER_WORD_PATTERN =
            java.util.regex.Pattern.compile("^[^A-Za-z']*([A-Za-z']+)");

    public ChatbotController() {
        this.objectMapper = new ObjectMapper();
        this.objectMapper.configure(com.fasterxml.jackson.databind.DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES,
                false);
    }

    private LearningLanguageProfile languageProfileFrom(Map<?, ?> request) {
        if (request == null) {
            return LearningLanguageProfile.defaultProfile();
        }
        return LearningLanguageProfile.of(
                stringValue(request.get("sourceLanguage")),
                stringValue(request.get("targetLanguage")),
                stringValue(request.get("feedbackLanguage")),
                stringValue(request.get("englishLevel")),
                stringValue(request.get("learningGoal")));
    }

    private String stringValue(Object value) {
        if (value == null) {
            return null;
        }
        String text = value.toString().trim();
        return text.isEmpty() ? null : text;
    }

    private String firstNonBlank(String... values) {
        if (values == null) {
            return null;
        }
        for (String value : values) {
            if (value != null && !value.trim().isEmpty()) {
                return value.trim();
            }
        }
        return null;
    }

    private List<String> extractStringList(Object rawValue) {
        if (!(rawValue instanceof List<?> rawList)) {
            return new ArrayList<>();
        }
        List<String> result = new ArrayList<>();
        for (Object item : rawList) {
            String value = stringValue(item);
            if (value == null) {
                continue;
            }
            result.add(value);
            if (result.size() >= 4) {
                break;
            }
        }
        return result;
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

    private ResponseEntity<Map<String, Object>> enforceAiAccess(Long userId, HttpServletRequest request, String scope) {
        ResponseEntity<Map<String, Object>> quotaLimit = enforceAiTokenQuota(userId, request, scope);
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
        ResponseEntity<Map<String, Object>> accessLimit = enforceAiAccess(userId, httpRequest, "generate-sentences");
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
        String direction = normalizeTranslationDirection(request.get("direction"));
        LearningLanguageProfile languageProfile = languageProfileFrom(request);

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

        List<String> targetWords = parseTargetWords(word);
        String normalizedWord = String.join(", ", targetWords).toLowerCase(Locale.ROOT);
        Map<String, String> targetWordMeanings = targetWordMeanings(userId, targetWords, languageProfile);
        List<String> grammarPatterns = PromptCatalog.grammarPatternSetFor(normalizedWord + ":" + direction, userId, fresh);
        String promptVersion = "v6";
        // Separate cache per user? Or global? Sentences are knowledge, so global is
        // fine.
        String cacheKey = CACHE_KEY_PREFIX + promptVersion + ":" + languageCachePart(languageProfile) + ":" + normalizedWord + ":"
                + String.join(",", levels) + ":" + String.join(",", lengths) + ":"
                + grammarPatterns.stream().map(this::normalizeCacheToken).collect(Collectors.joining(","));

        try {
            List<PracticeSentence> allSentences;
            boolean cached = false;
            boolean shouldStoreFreshResponse = false;

            Optional<List<PracticeSentence>> cachedSentences = fresh
                    ? Optional.empty()
                    : loadSentencesFromCache(cacheKey);
            if (cachedSentences.isPresent()) {
                allSentences = cachedSentences.get();
                cached = true;
            } else {
                StringBuilder levelLengthInfo = new StringBuilder();
                levelLengthInfo.append("Return EXACTLY 5 natural translation-practice sentences inside a JSON object with key 'sentences'.\n");
                if (targetWords.size() == 1) {
                    levelLengthInfo.append("Target word: ").append(targetWords.get(0)).append("\n");
                    appendMeaningHint(levelLengthInfo, targetWords.get(0), targetWordMeanings);
                    levelLengthInfo.append("Every English sentence must use this target word naturally, without quotation marks.\n");
                } else {
                    levelLengthInfo.append("Target words: ").append(String.join(", ", targetWords)).append("\n");
                    appendMeaningHints(levelLengthInfo, targetWords, targetWordMeanings);
                    levelLengthInfo.append(
                            "Multi-word mode: use exactly ONE target word per sentence, rotate through the target words, and NEVER treat the comma-separated list as one phrase.\n");
                    levelLengthInfo.append("Target words must appear naturally, without quotation marks.\n");
                }
                levelLengthInfo.append("Practice direction: ").append(direction).append("\n");
                if (isSourceToTargetDirection(direction) || direction.equals("MIXED")) {
                    levelLengthInfo.append(
                            "For source-to-English practice, think of the source-language sentence first, then provide the natural English equivalent. Avoid awkward literal translation.\n");
                }
                levelLengthInfo.append("Requested level/length combinations:\n");
                for (String level : levels) {
                    for (String length : lengths) {
                        levelLengthInfo.append(String.format("- Level: %s, Length: %s\n", level, length));
                    }
                }
                levelLengthInfo.append(
                        "Distribute the 5 sentences across these combinations as evenly as possible.\n");
                levelLengthInfo.append("Soft grammar pattern slots, use when natural:\n");
                for (int i = 0; i < grammarPatterns.size(); i++) {
                    levelLengthInfo.append(String.format("- Sentence %d: %s\n", i + 1, grammarPatterns.get(i)));
                }
                levelLengthInfo.append("Use these real-life context slots exactly once:\n");
                levelLengthInfo.append("- travel, transport, or appointment\n");
                levelLengthInfo.append("- work, school, or planning\n");
                levelLengthInfo.append("- family, friend, or daily life\n");
                levelLengthInfo.append("- news, public service, or community\n");
                levelLengthInfo.append("- personal decision, problem, or opinion\n");
                levelLengthInfo.append(
                        "Avoid generic textbook frames and avoid paraphrasing the same idea with tiny wording changes.\n");
                levelLengthInfo.append(
                        "If the word has multiple natural senses/collocations, cover more than one.\n");
                levelLengthInfo.append(
                        "Do NOT write meta sentences about the target word itself. Forbidden frames: \"the word ...\", \"used ... to describe\", \"explained ...\", \"heard ...\", \"practice ...\", \"remember ...\".\n");
                levelLengthInfo.append(
                        "Do not start more than one sentence with a personal pronoun. At least one sentence must be a question.\n");
                List<String> recentStarters = sentenceStarterTrackingService != null
                        ? sentenceStarterTrackingService.recentStarters(userId)
                        : List.of();
                if (!recentStarters.isEmpty()) {
                    levelLengthInfo.append("This learner has recently seen sentences starting with: ")
                            .append(String.join(", ", recentStarters))
                            .append(". Avoid starting any new sentence with these same words.\n");
                }
                levelLengthInfo.append("Prefer natural, idiomatic ")
                        .append(languageProfile.sourceLanguage())
                        .append(" phrasing that a native speaker would actually write; avoid literal, translated-sounding wording.\n");
                if (isTurkishSource(languageProfile)) {
                    levelLengthInfo.append(
                            "Think in Turkish first for the full-sentence translation, not as a word-for-word translation of the English sentence.\n");
                } else {
                    levelLengthInfo.append("All source-language translations must be in ")
                            .append(languageProfile.sourceLanguage())
                            .append(". Do not output Turkish translations for this request.\n");
                }
                levelLengthInfo.append(
                        "Lengths must be meaningfully different: short=4-8 words, medium=9-15 words, long=16+ words.\n");
                levelLengthInfo.append("Good example for target word 'delay': The flight was delayed by heavy rain.\n");
                levelLengthInfo.append("Bad example for target word 'delay': A short news article used \"delay\" to describe the problem.");
                if (fresh) {
                    levelLengthInfo.append("\nGenerate a fresh new set. Avoid reusing common previous examples.");
                    levelLengthInfo.append("\nvariationSeed=").append(System.currentTimeMillis());
                }

                String message = levelLengthInfo.toString();

                try {
                    ChatbotService.AiCallResult llm = chatbotService.generateSentences(message, languageProfile);
                    consumeAiTokens(userId, httpRequest, "generate-sentences", llm.totalTokens());
                    String jsonResponse = llm.content();
                    allSentences = sanitizePracticeSentences(
                            parsePracticeSentencesWithFallback(jsonResponse, normalizedWord, languageProfile), targetWords);
                } catch (Exception aiException) {
                    log.error(
                            "AI sentence generation failed; serving deterministic fallback. userId={}, word={}",
                            userId,
                            normalizedWord,
                            aiException);
                    allSentences = buildDeterministicFallbackSentences(targetWords, targetWordMeanings, languageProfile);
                }

                shouldStoreFreshResponse = !fresh;
            }

            allSentences = sanitizePracticeSentences(allSentences, targetWords);
            allSentences = completePracticeSentences(allSentences, targetWords, targetWordMeanings, languageProfile);
            if (allSentences.size() > 5) {
                allSentences = allSentences.subList(0, 5);
            }

            if (shouldStoreFreshResponse) {
                storeSentencesToCache(cacheKey, allSentences);
            }

            recordSentenceStarters(userId, allSentences);

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
            result.put("sourceTranslations", translations);
            result.put("sourceFullTranslations", translations);
            result.put("count", sentences.size());
            result.put("cached", cached);
            result.put("direction", direction);
            result.put("targetWords", targetWords);

            return ResponseEntity.ok(result);
        } catch (Exception e) {
            log.error("Failed to generate sentences for userId={}, word={}", userId, request.get("word"), e);
            Map<String, Object> error = new HashMap<>();
            error.put("error", "Failed to generate sentences: " + e.getMessage());
            return ResponseEntity.internalServerError().body(error);
        }
    }

    private List<PracticeSentence> parsePracticeSentencesWithFallback(String rawResponse, String targetWord) {
        return parsePracticeSentencesWithFallback(rawResponse, targetWord, LearningLanguageProfile.defaultProfile());
    }

    private List<PracticeSentence> parsePracticeSentencesWithFallback(
            String rawResponse,
            String targetWord,
            LearningLanguageProfile profile
    ) {
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
            List<PracticeSentence> deterministicFallback =
                    buildDeterministicFallbackSentences(parseTargetWords(targetWord), Map.of(), profile);
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
        jsonResponse = jsonResponse.replaceAll("(?is)<think>.*?</think>", "").trim();
        int arrayStartIndex = jsonResponse.indexOf('[');
        if (arrayStartIndex > 0) {
            jsonResponse = jsonResponse.substring(arrayStartIndex);
        }
        int arrayEndIndex = jsonResponse.lastIndexOf(']');
        if (arrayEndIndex > 0 && arrayEndIndex < jsonResponse.length() - 1) {
            jsonResponse = jsonResponse.substring(0, arrayEndIndex + 1);
        }
        int objectStartIndex = jsonResponse.indexOf('{');
        int objectEndIndex = jsonResponse.lastIndexOf('}');
        if (arrayStartIndex < 0 && objectStartIndex > 0 && objectEndIndex > objectStartIndex) {
            jsonResponse = jsonResponse.substring(objectStartIndex, objectEndIndex + 1);
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

    private Map<String, String> targetWordMeanings(Long userId, List<String> targetWords, LearningLanguageProfile profile) {
        if (!isTurkishSource(profile)) {
            return Map.of();
        }
        if (userId == null || targetWords == null || targetWords.isEmpty()) {
            return Map.of();
        }
        Set<String> requested = targetWords.stream()
                .filter(Objects::nonNull)
                .map(value -> value.trim().toLowerCase(Locale.ROOT))
                .filter(value -> !value.isBlank())
                .collect(Collectors.toSet());
        if (requested.isEmpty()) {
            return Map.of();
        }
        try {
            return wordService.getAllWords(userId).stream()
                    .filter(Objects::nonNull)
                    .filter(word -> word.getEnglishWord() != null)
                    .filter(word -> requested.contains(word.getEnglishWord().trim().toLowerCase(Locale.ROOT)))
                    .filter(word -> word.getTurkishMeaning() != null && !word.getTurkishMeaning().trim().isBlank())
                    .collect(Collectors.toMap(
                            word -> word.getEnglishWord().trim().toLowerCase(Locale.ROOT),
                            word -> word.getTurkishMeaning().trim(),
                            (first, ignored) -> first));
        } catch (Exception e) {
            log.warn("Could not load word meaning hints for sentence generation. userId={}", userId, e);
            return Map.of();
        }
    }

    private boolean isTurkishSource(LearningLanguageProfile profile) {
        return profile != null && "Turkish".equalsIgnoreCase(profile.sourceLanguage());
    }

    // Records what this user was just shown, regardless of whether the sentences came
    // from a fresh AI call or the shared cache - the point is to track the learner's own
    // exposure so future prompts can steer away from starters they've already seen.
    private void recordSentenceStarters(Long userId, List<PracticeSentence> sentences) {
        if (sentenceStarterTrackingService == null || userId == null || sentences == null || sentences.isEmpty()) {
            return;
        }
        List<String> starters = sentences.stream()
                .map(PracticeSentence::englishSentence)
                .map(this::extractStarterWord)
                .filter(word -> word != null && !word.isBlank())
                .distinct()
                .collect(Collectors.toList());
        sentenceStarterTrackingService.recordStarters(userId, starters);
    }

    private String extractStarterWord(String sentence) {
        if (sentence == null) {
            return null;
        }
        java.util.regex.Matcher matcher = STARTER_WORD_PATTERN.matcher(sentence.trim());
        return matcher.find() ? matcher.group(1) : null;
    }

    private void appendMeaningHint(StringBuilder prompt, String targetWord, Map<String, String> meanings) {
        String meaning = meaningFor(targetWord, meanings);
        if (!meaning.isBlank()) {
            prompt.append("Known learner meaning: ").append(meaning).append("\n");
        }
    }

    private void appendMeaningHints(StringBuilder prompt, List<String> targetWords, Map<String, String> meanings) {
        List<String> hints = targetWords.stream()
                .map(word -> {
                    String meaning = meaningFor(word, meanings);
                    return meaning.isBlank() ? "" : word + " = " + meaning;
                })
                .filter(value -> !value.isBlank())
                .toList();
        if (!hints.isEmpty()) {
            prompt.append("Known learner meanings: ").append(String.join("; ", hints)).append("\n");
        }
    }

    private String meaningFor(String targetWord, Map<String, String> meanings) {
        if (targetWord == null || meanings == null || meanings.isEmpty()) {
            return "";
        }
        return meanings.getOrDefault(targetWord.trim().toLowerCase(Locale.ROOT), "");
    }

    private List<String> parseTargetWords(String raw) {
        if (raw == null || raw.isBlank()) {
            return List.of("word");
        }
        List<String> words = Arrays.stream(raw.split("[,;\\n]+"))
                .map(String::trim)
                .filter(value -> !value.isBlank())
                .map(value -> value.length() > 60 ? value.substring(0, 60).trim() : value)
                .distinct()
                .limit(5)
                .collect(Collectors.toList());
        if (words.isEmpty()) {
            return List.of(raw.trim());
        }
        return words;
    }

    private List<PracticeSentence> completePracticeSentences(
            List<PracticeSentence> aiSentences,
            List<String> targetWords,
            Map<String, String> meanings,
            LearningLanguageProfile profile
    ) {
        List<PracticeSentence> completed = new ArrayList<>();
        if (aiSentences != null) {
            completed.addAll(sanitizePracticeSentences(aiSentences, targetWords));
        }
        if (!isTurkishSource(profile) && !completed.isEmpty()) {
            return completed;
        }
        Set<String> seen = completed.stream()
                .map(PracticeSentence::englishSentence)
                .filter(Objects::nonNull)
                .map(value -> value.toLowerCase(Locale.ROOT).replaceAll("[^a-z0-9\\s]", " ").replaceAll("\\s+", " ").trim())
                .collect(Collectors.toCollection(LinkedHashSet::new));
        for (PracticeSentence fallback : buildDeterministicFallbackSentences(targetWords, meanings, profile)) {
            if (completed.size() >= 5) {
                break;
            }
            String key = fallback.englishSentence().toLowerCase(Locale.ROOT)
                    .replaceAll("[^a-z0-9\\s]", " ")
                    .replaceAll("\\s+", " ")
                    .trim();
            if (seen.add(key)) {
                completed.add(fallback);
            }
        }
        return completed;
    }

    private List<PracticeSentence> buildDeterministicFallbackSentences(String targetWord) {
        return buildDeterministicFallbackSentences(parseTargetWords(targetWord));
    }

    private List<PracticeSentence> buildDeterministicFallbackSentences(List<String> targetWords) {
        return buildDeterministicFallbackSentences(targetWords, Map.of());
    }

    private List<PracticeSentence> buildDeterministicFallbackSentences(List<String> targetWords, Map<String, String> meanings) {
        return buildDeterministicFallbackSentences(targetWords, meanings, LearningLanguageProfile.defaultProfile());
    }

    private List<PracticeSentence> buildDeterministicFallbackSentences(
            List<String> targetWords,
            Map<String, String> meanings,
            LearningLanguageProfile profile
    ) {
        // Word meanings are only ever stored in Turkish at the DB layer (legacy
        // turkishMeaning field), so a non-Turkish source can't get a translated
        // fallback sentence without a schema change or a live AI call - and a
        // live AI call defeats the point of a fallback used when AI is down.
        // Still serve the English sentence itself (with no source translation)
        // rather than nothing: 5 untranslated practice sentences beat zero.
        boolean includeSourceTranslation = isTurkishSource(profile);
        List<String> words = targetWords == null || targetWords.isEmpty() ? List.of("word") : targetWords;
        List<PracticeSentence> templates = new ArrayList<>();
        for (int i = 0; i < 5; i++) {
            String word = words.get(i % words.size());
            PracticeSentence sentence = fallbackPracticeSentence(word, meaningFor(word, meanings), i);
            if (!includeSourceTranslation) {
                sentence = new PracticeSentence(sentence.englishSentence(), null, null);
            }
            templates.add(sentence);
        }
        return templates;
    }

    private PracticeSentence fallbackPracticeSentence(String targetWord, int index) {
        return fallbackPracticeSentence(targetWord, "", index);
    }

    private PracticeSentence fallbackPracticeSentence(String targetWord, String knownMeaning, int index) {
        String word = targetWord == null || targetWord.isBlank() ? "word" : targetWord.trim();
        List<PracticeSentence> knownSet = knownFallbackSentenceSet(word);
        if (!knownSet.isEmpty()) {
            return knownSet.get(index % knownSet.size());
        }
        boolean likelyVerb = isLikelyVerb(word, knownMeaning);
        boolean likelyAdjective = !likelyVerb && isLikelyAdjective(word, knownMeaning);
        if (likelyVerb) {
            return switch (index % 5) {
                case 0 -> new PracticeSentence(
                        "Please " + word + " your answer a little more.",
                        knownMeaning.isBlank() ? word : knownMeaning,
                        "Lütfen cevabını biraz daha " + (knownMeaning.isBlank() ? word : knownMeaning) + ".");
                case 1 -> new PracticeSentence(
                        "Could you " + word + " on that idea?",
                        knownMeaning.isBlank() ? word : knownMeaning,
                        "Bu fikri biraz daha " + (knownMeaning.isBlank() ? word : knownMeaning) + " misin?");
                case 2 -> new PracticeSentence(
                        "The teacher asked Maya to " + word + " before class ended.",
                        knownMeaning.isBlank() ? word : knownMeaning,
                        "Öğretmen Maya'dan ders bitmeden bunu " + (knownMeaning.isBlank() ? word : knownMeaning) + " istedi.");
                case 3 -> new PracticeSentence(
                        "Why did he need to " + word + " during the meeting?",
                        knownMeaning.isBlank() ? word : knownMeaning,
                        "Toplantı sırasında neden bunu " + (knownMeaning.isBlank() ? word : knownMeaning) + " gerekiyordu?");
                default -> new PracticeSentence(
                        "A short example can help you " + word + " clearly.",
                        knownMeaning.isBlank() ? word : knownMeaning,
                        "Kısa bir örnek bunu net şekilde " + (knownMeaning.isBlank() ? word : knownMeaning) + " yardımcı olabilir.");
            };
        }
        if (likelyAdjective) {
            return switch (index % 5) {
                case 0 -> new PracticeSentence(
                        "The explanation was " + word + ", but useful.",
                        knownMeaning.isBlank() ? word : knownMeaning,
                        "Açıklama " + (knownMeaning.isBlank() ? word : knownMeaning) + " ama faydalıydı.");
                case 1 -> new PracticeSentence(
                        "Why does this detail feel " + word + "?",
                        knownMeaning.isBlank() ? word : knownMeaning,
                        "Bu ayrıntı neden " + (knownMeaning.isBlank() ? word : knownMeaning) + " hissettiriyor?");
                case 2 -> new PracticeSentence(
                        "Her message sounded " + word + " after the meeting.",
                        knownMeaning.isBlank() ? word : knownMeaning,
                        "Toplantıdan sonra mesajı " + (knownMeaning.isBlank() ? word : knownMeaning) + " geliyordu.");
                case 3 -> new PracticeSentence(
                        "A more " + word + " plan would help everyone.",
                        knownMeaning.isBlank() ? word : knownMeaning,
                        "Daha " + (knownMeaning.isBlank() ? word : knownMeaning) + " bir plan herkese yardımcı olurdu.");
                default -> new PracticeSentence(
                        "The article gave a " + word + " example.",
                        knownMeaning.isBlank() ? word : knownMeaning,
                        "Makale " + (knownMeaning.isBlank() ? word : knownMeaning) + " bir örnek verdi.");
            };
        }
        return switch (index % 5) {
            case 0 -> new PracticeSentence(
                    "The plan changed because of " + word + ".",
                    word,
                    "Plan " + word + " nedeniyle değişti.");
            case 1 -> new PracticeSentence(
                    "Could " + word + " affect our decision today?",
                    word,
                    word + " bugün kararımızı etkileyebilir mi?");
            case 2 -> new PracticeSentence(
                    "Maya noticed " + word + " during the trip.",
                    word,
                    "Maya yolculuk sırasında " + word + " fark etti.");
            case 3 -> new PracticeSentence(
                    "A problem with " + word + " delayed the meeting.",
                    word,
                    word + " ile ilgili bir sorun toplantıyı geciktirdi.");
            default -> new PracticeSentence(
                    "This situation made " + word + " difficult to ignore.",
                    word,
                    "Bu durum " + word + " göz ardı etmeyi zorlaştırdı.");
        };
    }

    private boolean isLikelyVerb(String word, String knownMeaning) {
        String normalizedWord = word == null ? "" : word.trim().toLowerCase(Locale.ROOT);
        String normalizedMeaning = knownMeaning == null ? "" : knownMeaning.trim().toLowerCase(Locale.ROOT);
        if (normalizedMeaning.endsWith("mek") || normalizedMeaning.endsWith("mak")
                || normalizedMeaning.startsWith("to ")) {
            return true;
        }
        return Set.of("elaborate", "clarify", "enhance", "overcome", "prioritize", "retain", "adapt",
                "navigate", "recover", "prevent", "adjust", "improve", "explain", "describe", "compare",
                "decide", "suggest", "reduce", "increase", "support", "avoid").contains(normalizedWord);
    }

    private boolean isLikelyAdjective(String word, String knownMeaning) {
        String normalizedWord = word == null ? "" : word.trim().toLowerCase(Locale.ROOT);
        String normalizedMeaning = knownMeaning == null ? "" : knownMeaning.trim().toLowerCase(Locale.ROOT);
        if (normalizedWord.endsWith("ive") || normalizedWord.endsWith("able") || normalizedWord.endsWith("ible")
                || normalizedWord.endsWith("al") || normalizedWord.endsWith("ful") || normalizedWord.endsWith("less")
                || normalizedWord.endsWith("ous") || normalizedWord.endsWith("ent") || normalizedWord.endsWith("ant")) {
            return true;
        }
        return Set.of("subtle", "resilient", "diligent", "consistent", "efficient", "inevitable",
                "accurate", "compelling", "reliable", "balanced", "exhausted", "accessible").contains(normalizedWord)
                || normalizedMeaning.endsWith("li")
                || normalizedMeaning.endsWith("lı")
                || normalizedMeaning.endsWith("lu")
                || normalizedMeaning.endsWith("lü")
                || normalizedMeaning.endsWith("sal")
                || normalizedMeaning.endsWith("sel");
    }

    private List<PracticeSentence> knownFallbackSentenceSet(String targetWord) {
        String word = targetWord == null ? "" : targetWord.trim().toLowerCase(Locale.ROOT);
        return switch (word) {
            case "elaborate" -> List.of(
                    new PracticeSentence("Could you elaborate on your answer?", "detaylandırmak",
                            "Cevabını biraz daha detaylandırabilir misin?"),
                    new PracticeSentence("Maya gave an elaborate explanation after the meeting.", "ayrıntılı",
                            "Maya toplantıdan sonra ayrıntılı bir açıklama yaptı."),
                    new PracticeSentence("Please elaborate before we make a final decision.", "detaylandırmak",
                            "Son kararı vermeden önce lütfen biraz daha detaylandır."),
                    new PracticeSentence("The design looked elaborate, but it was easy to use.", "özenli/ayrıntılı",
                            "Tasarım ayrıntılı görünüyordu ama kullanımı kolaydı."),
                    new PracticeSentence("Why did the manager ask him to elaborate?", "detaylandırmak",
                            "Yönetici neden ondan bunu detaylandırmasını istedi?"));
            case "delay" -> List.of(
                    new PracticeSentence("The flight was delayed by heavy rain.", "gecikmek",
                            "Uçuş yoğun yağmur nedeniyle gecikti."),
                    new PracticeSentence("The delay forced us to change our plans.", "gecikme",
                            "Gecikme planlarımızı değiştirmemize neden oldu."),
                    new PracticeSentence("Why was the morning train delayed again?", "gecikmek",
                            "Sabah treni neden yine gecikti?"),
                    new PracticeSentence("A short delay is better than a careless decision.", "gecikme",
                            "Kısa bir gecikme dikkatsiz bir karardan daha iyidir."),
                    new PracticeSentence("Traffic delays are common during holiday weekends.", "gecikmeler",
                            "Trafik gecikmeleri tatil hafta sonlarında yaygındır."));
            case "focus" -> List.of(
                    new PracticeSentence("Please focus on the main problem first.", "odaklanmak",
                            "Lütfen önce ana probleme odaklan."),
                    new PracticeSentence("Her focus improved after a short break.", "odak",
                            "Kısa bir aradan sonra odağı gelişti."),
                    new PracticeSentence("What helps you focus when work gets noisy?", "odaklanmak",
                            "İş ortamı gürültülü olduğunda odaklanmana ne yardımcı olur?"),
                    new PracticeSentence("The team lost focus near the deadline.", "odak",
                            "Ekip son teslim tarihine yakın odağını kaybetti."),
                    new PracticeSentence("This lesson focuses on natural daily English.", "odaklanır",
                            "Bu ders doğal günlük İngilizceye odaklanır."));
            case "apple" -> List.of(
                    new PracticeSentence("She packed an apple for the bus ride.", "elma",
                            "Otobüs yolculuğu için yanına bir elma aldı."),
                    new PracticeSentence("Why does this apple taste so sweet?", "elma",
                            "Bu elmanın tadı neden bu kadar tatlı?"),
                    new PracticeSentence("The apple pie cooled on the kitchen counter.", "elmalı",
                            "Elmalı turta mutfak tezgahında soğudu."),
                    new PracticeSentence("A fresh apple can make breakfast feel lighter.", "elma",
                            "Taze bir elma kahvaltıyı daha hafif hissettirebilir."),
                    new PracticeSentence("They shared the last apple after lunch.", "elma",
                            "Öğle yemeğinden sonra son elmayı paylaştılar."));
            case "book" -> List.of(
                    new PracticeSentence("I borrowed this book from the library.", "kitap",
                            "Bu kitabı kütüphaneden ödünç aldım."),
                    new PracticeSentence("Can you book a table for Friday night?", "rezervasyon yapmak",
                            "Cuma gecesi için masa rezervasyonu yapabilir misin?"),
                    new PracticeSentence("The book was too heavy for my bag.", "kitap",
                            "Kitap çantam için fazla ağırdı."),
                    new PracticeSentence("Maya booked the earliest train to Ankara.", "rezervasyon yaptı",
                            "Maya Ankara'ya en erken tren için rezervasyon yaptı."),
                    new PracticeSentence("Which book changed the way you think?", "kitap",
                            "Hangi kitap düşünme şeklini değiştirdi?"));
            default -> List.of();
        };
    }

    private PracticeSentence toPracticeSentence(Map<String, Object> map) {
        if (map == null || map.isEmpty()) {
            return null;
        }
        String english = firstNonBlankString(map, "englishSentence", "english_sentence", "sentence");
        if (english.isBlank()) {
            return null;
        }
        String turkish = firstNonBlankString(map, "sourceTranslation", "turkishTranslation", "turkish_translation", "turkish");
        String turkishFull = firstNonBlankString(map, "sourceFullTranslation", "turkishFullTranslation", "turkish_full_translation");

        if (turkishFull.isBlank()) {
            turkishFull = turkish;
        }
        if (turkish.isBlank()) {
            turkish = turkishFull;
        }
        return new PracticeSentence(english, turkish, turkishFull);
    }

    private List<PracticeSentence> sanitizePracticeSentences(List<PracticeSentence> sentences) {
        return sanitizePracticeSentences(sentences, List.of());
    }

    private List<PracticeSentence> sanitizePracticeSentences(List<PracticeSentence> sentences, List<String> targetWords) {
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
            if (isMetaPracticeSentence(english, targetWords)) {
                continue;
            }
            if (!containsAnyTargetWord(english, targetWords)) {
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

    private boolean containsAnyTargetWord(String english, List<String> targetWords) {
        if (english == null || english.isBlank() || targetWords == null || targetWords.isEmpty()) {
            return true;
        }

        String normalizedEnglish = english.toLowerCase(Locale.ROOT)
                .replaceAll("[^a-z0-9'\\s-]", " ")
                .replaceAll("\\s+", " ")
                .trim();
        if (normalizedEnglish.isBlank()) {
            return false;
        }

        Set<String> englishTokens = Arrays.stream(normalizedEnglish.split("[\\s-]+"))
                .map(String::trim)
                .filter(token -> !token.isBlank())
                .collect(Collectors.toSet());

        for (String rawTarget : targetWords) {
            if (rawTarget == null || rawTarget.isBlank()) {
                continue;
            }
            String target = rawTarget.toLowerCase(Locale.ROOT)
                    .replaceAll("[^a-z0-9'\\s-]", " ")
                    .replaceAll("\\s+", " ")
                    .trim();
            if (target.isBlank()) {
                continue;
            }
            if (target.contains(" ") || target.contains("-")) {
                if (normalizedEnglish.contains(target)) {
                    return true;
                }
                continue;
            }
            for (String variant : targetWordVariants(target)) {
                if (englishTokens.contains(variant)) {
                    return true;
                }
            }
        }
        return false;
    }

    private Set<String> targetWordVariants(String target) {
        Set<String> variants = new LinkedHashSet<>();
        if (target == null || target.isBlank()) {
            return variants;
        }
        variants.add(target);
        variants.add(target + "s");
        variants.add(target + "es");
        variants.add(target + "d");
        variants.add(target + "ed");
        variants.add(target + "ing");
        if (target.endsWith("e") && target.length() > 1) {
            variants.add(target.substring(0, target.length() - 1) + "ing");
        }
        if (target.endsWith("y") && target.length() > 1) {
            variants.add(target.substring(0, target.length() - 1) + "ied");
        }
        return variants;
    }

    private boolean isMetaPracticeSentence(String english, List<String> targetWords) {
        if (english == null || english.isBlank()) {
            return true;
        }
        String normalized = english.toLowerCase(Locale.ROOT)
                .replace('\u201c', '"')
                .replace('\u201d', '"')
                .replace('\u2018', '\'')
                .replace('\u2019', '\'');
        if (normalized.contains("the word")
                || normalized.contains("how to use")
                || normalized.contains("feel important")
                || normalized.contains("used \"")
                || normalized.contains("explained \"")
                || normalized.contains("heard \"")
                || normalized.contains("practice \"")
                || normalized.contains("remember \"")) {
            return true;
        }
        if (targetWords == null) {
            return false;
        }
        for (String targetWord : targetWords) {
            if (targetWord == null || targetWord.isBlank()) {
                continue;
            }
            String word = Pattern.quote(targetWord.trim().toLowerCase(Locale.ROOT));
            if (normalized.matches(".*[\"']\\s*" + word + "\\s*[\"'].*")) {
                return true;
            }
        }
        return false;
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

    private String languageCachePart(LearningLanguageProfile profile) {
        return normalizeCacheToken(profile.sourceLanguage())
                + ":" + normalizeCacheToken(profile.targetLanguage())
                + ":" + normalizeCacheToken(profile.feedbackLanguage())
                + ":" + normalizeCacheToken(profile.englishLevel())
                + ":" + normalizeCacheToken(profile.learningGoal());
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
        ResponseEntity<Map<String, Object>> accessLimit = enforceAiAccess(userId, httpRequest, "check-grammar");
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
        ResponseEntity<Map<String, Object>> accessLimit = enforceAiAccess(userId, httpRequest, "check-translation");
        if (accessLimit != null) {
            return accessLimit;
        }
        ResponseEntity<Map<String, Object>> aiLimit = enforceAiRateLimit(userId, httpRequest, "check-translation");
        if (aiLimit != null) {
            return aiLimit;
        }

        return originalCheckTranslation(request, userId, httpRequest);
    }

    // Helper to keep existing logic cleaner while wrapping with auth check
    private ResponseEntity<Map<String, Object>> originalCheckTranslation(Map<String, String> request,
                                                                         Long userId,
                                                                         HttpServletRequest httpRequest) {
        String direction = normalizeTranslationDirection(request.get("direction"));
        String userTranslation = request.get("userTranslation");
        LearningLanguageProfile languageProfile = languageProfileFrom(request);

        if (userTranslation == null) {
            return ResponseEntity.badRequest().body(Map.of("error", "Please provide translation"));
        }

        try {
            ChatbotService.AiCallResult response;
            if (isSourceToTargetDirection(direction)) {
                String sourceSentence = firstNonBlank(request.get("sourceSentence"), request.get("turkishSentence"));
                String targetRef = firstNonBlank(request.get("targetSentence"), request.get("englishSentence"));
                if (sourceSentence == null) {
                    return ResponseEntity.badRequest()
                            .body(Map.of("error", languageProfile.sourceLanguage() + " sentence is required"));
                }
                String combinedMessage = languageProfile.sourceLanguage() + " sentence: " + sourceSentence
                        + ". User's " + languageProfile.targetLanguage() + " translation: "
                        + userTranslation + ".";
                if (targetRef != null)
                    combinedMessage += " (Reference: " + targetRef + ")";
                combinedMessage += " Evaluate this translation generously. Return ONLY JSON.";
                response = chatbotService.checkEnglishTranslation(combinedMessage, languageProfile);
            } else {
                String targetSentence = firstNonBlank(request.get("targetSentence"), request.get("englishSentence"));
                if (targetSentence == null) {
                    return ResponseEntity.badRequest()
                            .body(Map.of("error", languageProfile.targetLanguage() + " sentence is required"));
                }
                String combinedMessage = languageProfile.targetLanguage() + " sentence: " + targetSentence
                        + ". User's " + languageProfile.sourceLanguage() + " translation: " + userTranslation
                        + ". Evaluate this translation generously. Return ONLY JSON.";
                response = chatbotService.checkTranslation(combinedMessage, languageProfile);
            }
            consumeAiTokens(userId, httpRequest, "check-translation", response != null ? response.totalTokens() : 0);
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
                // If no JSON found, try to infer from text.
                // Locale.ROOT is required here: on a JVM whose default locale is
                // Turkish, toLowerCase() maps 'I' -> 'ı' (dotless), so a response
                // containing "Incorrect" would silently fail the .contains("incorrect")
                // check below, flipping a wrong translation-practice answer into a
                // reported "correct" result for the user.
                String lowerResponse = response.toLowerCase(java.util.Locale.ROOT);
                boolean isCorrect = lowerResponse.contains("\"iscorrect\":true") ||
                        lowerResponse.contains("doğru") ||
                        (!lowerResponse.contains("incorrect") &&
                                !lowerResponse.contains("yanlış") &&
                                !lowerResponse.contains("\"iscorrect\":false"));

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
        ResponseEntity<Map<String, Object>> accessLimit = enforceAiAccess(userId, httpRequest, "chat");
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
            LearningLanguageProfile languageProfile = languageProfileFrom(request);
            ChatbotService.AiCallResult llm =
                    chatbotService.chat(message.trim(), scenario, scenarioContext, userId, languageProfile);
            consumeAiTokens(userId, httpRequest, "chat", llm.totalTokens());
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

    private String normalizeTranslationDirection(Object rawDirection) {
        String normalized = Optional.ofNullable(rawDirection)
                .map(Object::toString)
                .map(String::trim)
                .map(String::toUpperCase)
                .orElse("EN_TO_TR");
        return switch (normalized) {
            case "TR_TO_EN", "SOURCE_TO_TARGET" -> normalized;
            case "EN_TO_TR", "TARGET_TO_SOURCE" -> normalized;
            case "MIXED" -> "MIXED";
            default -> "EN_TO_TR";
        };
    }

    private boolean isSourceToTargetDirection(String direction) {
        return "SOURCE_TO_TARGET".equals(direction) || "TR_TO_EN".equals(direction);
    }

    @PostMapping(value = "/speech/transcribe", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<Map<String, Object>> transcribeSpeech(
            @RequestParam("audio") MultipartFile audio,
            @RequestParam(value = "durationMs", required = false) Long durationMs,
            @RequestParam(value = "locale", required = false) String locale,
            @RequestHeader("X-User-Id") Long userId,
            HttpServletRequest httpRequest) {
        ResponseEntity<Map<String, Object>> accessLimit = enforceAiAccess(userId, httpRequest, "speech-transcribe");
        if (accessLimit != null) {
            return accessLimit;
        }
        ResponseEntity<Map<String, Object>> aiLimit = enforceAiRateLimit(userId, httpRequest, "speech-transcribe");
        if (aiLimit != null) {
            return aiLimit;
        }

        if (audio == null || audio.isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of(
                    "success", false,
                    "error", "Audio file is required",
                    "reason", "missing-audio"));
        }
        if (audio.getSize() > Math.max(1L, speechMaxAudioBytes)) {
            return ResponseEntity.status(HttpStatus.PAYLOAD_TOO_LARGE).body(Map.of(
                    "success", false,
                    "error", "Audio file is too large",
                    "reason", "audio-too-large",
                    "maxAudioBytes", speechMaxAudioBytes));
        }
        if (durationMs != null && durationMs > Math.max(1L, speechMaxDurationSeconds) * 1000L) {
            return ResponseEntity.badRequest().body(Map.of(
                    "success", false,
                    "error", "Audio duration is too long",
                    "reason", "audio-too-long",
                    "maxDurationSeconds", speechMaxDurationSeconds));
        }

        long estimatedTokens = estimateSpeechTokens(durationMs);
        try {
            GroqSpeechToTextService.TranscriptionResult transcription = speechToTextService.transcribe(
                    audio.getBytes(),
                    audio.getOriginalFilename(),
                    audio.getContentType(),
                    locale);
            consumeAiTokens(userId, httpRequest, "speech-transcribe", estimatedTokens);

            Map<String, Object> result = new HashMap<>();
            result.put("success", true);
            result.put("text", transcription.text());
            result.put("model", transcription.model());
            result.put("estimatedTokens", estimatedTokens);
            result.put("durationMs", durationMs == null ? 0L : Math.max(0L, durationMs));
            // Whisper'ın ölçtüğü gerçek ses süresi (istemci duvar-saatinden
            // dürüst) + kelime zaman damgaları. Eski istemciler bu alanları
            // yok sayar - saf ek alanlar.
            if (transcription.durationSeconds() != null) {
                result.put("measuredDurationMs",
                        Math.round(transcription.durationSeconds() * 1000.0));
            }
            if (!transcription.words().isEmpty()) {
                result.put("words", transcription.words().stream()
                        .map(w -> Map.of(
                                "word", w.word(),
                                "start", w.start(),
                                "end", w.end()))
                        .toList());
            }
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            log.error("Failed to transcribe speech for userId={}", userId, e);
            return ResponseEntity.internalServerError().body(Map.of(
                    "success", false,
                    "error", "Failed to transcribe speech",
                    "reason", "speech-transcription-failed"));
        }
    }

    @PostMapping("/speaking-test/generate-questions")
    public ResponseEntity<Map<String, Object>> generateSpeakingTestQuestions(@RequestBody Map<String, String> request,
            @RequestHeader("X-User-Id") Long userId,
            HttpServletRequest httpRequest) {
        ResponseEntity<Map<String, Object>> accessLimit = enforceAiAccess(userId, httpRequest, "speaking-generate");
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
            // CEFR seviyesi + günlük tema rotasyonu: eski hali profilsiz ve
            // rotasyonsuzdu, her oturumda neredeyse aynı sorular üretiyordu.
            LearningLanguageProfile speakingProfile = languageProfileFrom(request);
            int dayOfYear = java.time.LocalDate.now(java.time.ZoneOffset.UTC).getDayOfYear();
            ChatbotService.AiCallResult llm =
                    chatbotService.generateSpeakingTestQuestions(message, speakingProfile, dayOfYear);
            String response = llm.content();
            consumeAiTokens(userId, httpRequest, "speaking-generate", llm.totalTokens());

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
        ResponseEntity<Map<String, Object>> accessLimit = enforceAiAccess(userId, httpRequest, "speaking-evaluate");
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
        LearningLanguageProfile languageProfile = languageProfileFrom(request);

        if (testType == null || question == null || response == null) {
            return ResponseEntity.badRequest().body(Map.of("error", "Please provide testType, question, and response"));
        }

        try {
            String message = String.format(
                    "Evaluate this %s Speaking test response. Question: %s. Candidate's response: %s. Return ONLY JSON.",
                    testType, question, response);
            ChatbotService.AiCallResult llm = chatbotService.evaluateSpeakingTest(message, languageProfile);
            String llmResponse = llm.content();
            consumeAiTokens(userId, httpRequest, "speaking-evaluate", llm.totalTokens());

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
        ResponseEntity<Map<String, Object>> accessLimit = enforceAiAccess(userId, httpRequest, "dictionary-lookup");
        if (accessLimit != null) return accessLimit;
        ResponseEntity<Map<String, Object>> aiLimit = enforceAiRateLimit(userId, httpRequest, "dictionary-lookup");
        if (aiLimit != null) return aiLimit;

        String word = request.get("word") != null ? request.get("word").toString() : null;
        LearningLanguageProfile languageProfile = languageProfileFrom(request);
        if (word == null || word.trim().isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("error", "word is required"));
        }

        String normalizedWord = normalizeCacheToken(word);
        String cacheKey = DICTIONARY_CACHE_KEY_PREFIX + "lookup:" + languageCachePart(languageProfile) + ":" + normalizedWord;
        try {
            Optional<Map<String, Object>> cached = loadMapFromCache(cacheKey);
            if (cached.isPresent()) {
                return ResponseEntity.ok(cached.get());
            }

            AiProxyService.AiJsonResult result = aiProxyService.dictionaryLookup(word.trim(), languageProfile);
            consumeAiTokens(userId, httpRequest, "dictionary-lookup", result.totalTokens());
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
        ResponseEntity<Map<String, Object>> accessLimit = enforceAiAccess(userId, httpRequest, "dictionary-lookup-detailed");
        if (accessLimit != null) return accessLimit;
        ResponseEntity<Map<String, Object>> aiLimit = enforceAiRateLimit(userId, httpRequest, "dictionary-lookup-detailed");
        if (aiLimit != null) return aiLimit;

        String word = request.get("word") != null ? request.get("word").toString() : null;
        LearningLanguageProfile languageProfile = languageProfileFrom(request);
        if (word == null || word.trim().isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("error", "word is required"));
        }

        String normalizedWord = normalizeCacheToken(word);
        String cacheKey = DICTIONARY_CACHE_KEY_PREFIX + "lookup-detailed:" + languageCachePart(languageProfile) + ":" + normalizedWord;
        try {
            Optional<Map<String, Object>> cached = loadMapFromCache(cacheKey);
            if (cached.isPresent()) {
                return ResponseEntity.ok(cached.get());
            }

            AiProxyService.AiJsonResult result = aiProxyService.dictionaryLookupDetailed(word.trim(), languageProfile);
            consumeAiTokens(userId, httpRequest, "dictionary-lookup-detailed", result.totalTokens());
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
        ResponseEntity<Map<String, Object>> accessLimit = enforceAiAccess(userId, httpRequest, "dictionary-explain");
        if (accessLimit != null) return accessLimit;
        ResponseEntity<Map<String, Object>> aiLimit = enforceAiRateLimit(userId, httpRequest, "dictionary-explain");
        if (aiLimit != null) return aiLimit;

        String word = request.get("word") != null ? request.get("word").toString() : null;
        String sentence = request.get("sentence") != null ? request.get("sentence").toString() : null;
        LearningLanguageProfile languageProfile = languageProfileFrom(request);
        if (word == null || word.trim().isEmpty() || sentence == null || sentence.trim().isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("error", "word and sentence are required"));
        }

        String cacheKey = DICTIONARY_CACHE_KEY_PREFIX + "explain:"
                + languageCachePart(languageProfile) + ":" + normalizeCacheToken(word) + ":" + normalizeCacheToken(sentence);
        try {
            Optional<Map<String, Object>> cached = loadMapFromCache(cacheKey);
            if (cached.isPresent()) {
                return ResponseEntity.ok(cached.get());
            }

            AiProxyService.AiJsonResult result = aiProxyService.dictionaryExplainWordInSentence(
                    word.trim(), sentence.trim(), languageProfile);
            consumeAiTokens(userId, httpRequest, "dictionary-explain", result.totalTokens());
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
        ResponseEntity<Map<String, Object>> accessLimit = enforceAiAccess(userId, httpRequest, "dictionary-specific-sentence");
        if (accessLimit != null) return accessLimit;
        ResponseEntity<Map<String, Object>> aiLimit = enforceAiRateLimit(userId, httpRequest, "dictionary-specific-sentence");
        if (aiLimit != null) return aiLimit;

        String word = request.get("word") != null ? request.get("word").toString() : null;
        String translation = request.get("translation") != null ? request.get("translation").toString() : null;
        String context = request.get("context") != null ? request.get("context").toString() : null;
        LearningLanguageProfile languageProfile = languageProfileFrom(request);
        if (word == null || word.trim().isEmpty() || translation == null || translation.trim().isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("error", "word and translation are required"));
        }

        String cacheKey = DICTIONARY_CACHE_KEY_PREFIX + "specific-sentence:"
                + languageCachePart(languageProfile) + ":" + normalizeCacheToken(word) + ":" + normalizeCacheToken(translation) + ":"
                + normalizeCacheToken(context);
        try {
            Optional<Map<String, Object>> cached = loadMapFromCache(cacheKey);
            if (cached.isPresent()) {
                return ResponseEntity.ok(cached.get());
            }

            AiProxyService.AiJsonResult result = aiProxyService.dictionaryGenerateSpecificSentence(
                    word.trim(),
                    translation.trim(),
                    context != null ? context.trim() : "",
                    languageProfile);
            consumeAiTokens(userId, httpRequest, "dictionary-specific-sentence", result.totalTokens());
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
        ResponseEntity<Map<String, Object>> accessLimit = enforceAiAccess(userId, httpRequest, "reading-generate");
        if (accessLimit != null) return accessLimit;
        ResponseEntity<Map<String, Object>> aiLimit = enforceAiRateLimit(userId, httpRequest, "reading-generate");
        if (aiLimit != null) return aiLimit;

        String level = request.get("level") != null ? request.get("level").toString() : "Intermediate";
        LearningLanguageProfile languageProfile = languageProfileFrom(request);
        // "Yeni pasaj" akışı: istemci artan bir variant sayısı yollar; her
        // varyant günün temasından farklı bir konu/kombinasyona zorlanır.
        int variant = 0;
        Object rawVariant = request.get("variant");
        if (rawVariant instanceof Number number) {
            variant = Math.max(0, Math.min(50, number.intValue()));
        } else if (rawVariant != null) {
            try {
                variant = Math.max(0, Math.min(50, Integer.parseInt(rawVariant.toString().trim())));
            } catch (NumberFormatException ignored) {
            }
        }
        int dayOfYear = java.time.LocalDate.now(java.time.ZoneOffset.UTC).getDayOfYear();
        try {
            AiProxyService.AiJsonResult result =
                    aiProxyService.generateReadingPassage(level, languageProfile, dayOfYear, variant);
            consumeAiTokens(userId, httpRequest, "reading-generate", result.totalTokens());
            return ResponseEntity.ok(result.json());
        } catch (Exception e) {
            log.error("generateReadingPassage failed userId={} level={}", userId, level, e);
            return ResponseEntity.internalServerError().body(Map.of("error", "Reading generation failed."));
        }
    }

    @PostMapping("/pronunciation/generate-texts")
    public ResponseEntity<Map<String, Object>> generatePronunciationTexts(@RequestBody Map<String, Object> request,
            @RequestHeader("X-User-Id") Long userId,
            HttpServletRequest httpRequest) {
        ResponseEntity<Map<String, Object>> accessLimit = enforceAiAccess(userId, httpRequest, "pronunciation-text-generate");
        if (accessLimit != null) return accessLimit;
        ResponseEntity<Map<String, Object>> aiLimit = enforceAiRateLimit(userId, httpRequest, "pronunciation-text-generate");
        if (aiLimit != null) return aiLimit;

        String level = request.get("level") != null ? request.get("level").toString() : "B1";
        List<String> focusWords = extractStringList(request.get("focusWords"));
        LearningLanguageProfile languageProfile = languageProfileFrom(request);
        int pronunciationVariant = 0;
        Object rawPronunciationVariant = request.get("variant");
        if (rawPronunciationVariant instanceof Number number) {
            pronunciationVariant = Math.max(0, Math.min(50, number.intValue()));
        } else if (rawPronunciationVariant != null) {
            try {
                pronunciationVariant = Math.max(0,
                        Math.min(50, Integer.parseInt(rawPronunciationVariant.toString().trim())));
            } catch (NumberFormatException ignored) {
            }
        }
        try {
            AiProxyService.AiJsonResult result = aiProxyService.generatePronunciationTexts(
                    level,
                    focusWords,
                    languageProfile,
                    pronunciationVariant);
            consumeAiTokens(userId, httpRequest, "pronunciation-text-generate", result.totalTokens());
            return ResponseEntity.ok(result.json());
        } catch (Exception e) {
            log.error("generatePronunciationTexts failed userId={} level={}", userId, level, e);
            return ResponseEntity.internalServerError().body(Map.of("error", "Pronunciation text generation failed."));
        }
    }

    @PostMapping("/writing/generate-topic")
    public ResponseEntity<Map<String, Object>> generateWritingTopic(@RequestBody Map<String, Object> request,
            @RequestHeader("X-User-Id") Long userId,
            HttpServletRequest httpRequest) {
        ResponseEntity<Map<String, Object>> accessLimit = enforceAiAccess(userId, httpRequest, "writing-topic");
        if (accessLimit != null) return accessLimit;
        ResponseEntity<Map<String, Object>> aiLimit = enforceAiRateLimit(userId, httpRequest, "writing-topic");
        if (aiLimit != null) return aiLimit;

        String level = request.get("level") != null ? request.get("level").toString() : "Intermediate";
        String wordCount = request.get("wordCount") != null ? request.get("wordCount").toString() : "150-200";
        LearningLanguageProfile languageProfile = languageProfileFrom(request);
        try {
            AiProxyService.AiJsonResult result = aiProxyService.generateWritingTopic(level, wordCount, languageProfile);
            consumeAiTokens(userId, httpRequest, "writing-topic", result.totalTokens());
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
        ResponseEntity<Map<String, Object>> accessLimit = enforceAiAccess(userId, httpRequest, "writing-evaluate");
        if (accessLimit != null) return accessLimit;
        ResponseEntity<Map<String, Object>> aiLimit = enforceAiRateLimit(userId, httpRequest, "writing-evaluate");
        if (aiLimit != null) return aiLimit;

        String text = request.get("text") != null ? request.get("text").toString() : null;
        String level = request.get("level") != null ? request.get("level").toString() : "Intermediate";
        Map<String, Object> topic = request.get("topic") instanceof Map ? (Map<String, Object>) request.get("topic") : null;
        LearningLanguageProfile languageProfile = languageProfileFrom(request);
        if (text == null || text.trim().isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("error", "text is required"));
        }

        try {
            AiProxyService.AiJsonResult result = aiProxyService.evaluateWriting(text, level, topic, languageProfile);
            consumeAiTokens(userId, httpRequest, "writing-evaluate", result.totalTokens());
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
        ResponseEntity<Map<String, Object>> accessLimit = enforceAiAccess(userId, httpRequest, "exam-generate");
        if (accessLimit != null) return accessLimit;
        ResponseEntity<Map<String, Object>> aiLimit = enforceAiRateLimit(userId, httpRequest, "exam-generate");
        if (aiLimit != null) return aiLimit;

        try {
            AiProxyService.AiJsonResult result = aiProxyService.generateExamBundle(request);
            consumeAiTokens(userId, httpRequest, "exam-generate", result.totalTokens());
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
            payload.put("activityEstimates", estimateRemainingActivities(tokensRemaining));
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

    // Representative total (prompt + completion) token cost per user-facing action.
    // These are deliberately conservative rounded averages so the "N actions left"
    // hint never over-promises; they translate the opaque token quota into units
    // users understand. Keep the keys stable: the Flutter card localizes the labels.
    private static final int TOKENS_PER_CONVERSATION_MESSAGE = 700;
    private static final int TOKENS_PER_TRANSLATION_CHECK = 450;
    private static final int TOKENS_PER_SENTENCE_SET = 1000;
    private static final int TOKENS_PER_GRAMMAR_CHECK = 400;

    private Map<String, Integer> estimateRemainingActivities(long tokensRemaining) {
        long safeRemaining = Math.max(0L, tokensRemaining);
        Map<String, Integer> estimates = new LinkedHashMap<>();
        estimates.put("conversations", (int) (safeRemaining / TOKENS_PER_CONVERSATION_MESSAGE));
        estimates.put("translationChecks", (int) (safeRemaining / TOKENS_PER_TRANSLATION_CHECK));
        estimates.put("sentenceSets", (int) (safeRemaining / TOKENS_PER_SENTENCE_SET));
        // Flutter's AiTokenQuotaCard only reads specific known keys today (see
        // _activityHint in ai_token_quota_card.dart) and ignores unknown ones, so
        // adding this key is safe/additive - surfacing it in the UI is a separate,
        // not-yet-done Flutter follow-up.
        estimates.put("grammarChecks", (int) (safeRemaining / TOKENS_PER_GRAMMAR_CHECK));
        return estimates;
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

    private ResponseEntity<Map<String, Object>> enforceAiTokenQuota(Long userId,
                                                                    HttpServletRequest request,
                                                                    String scope) {
        if (aiTokenQuotaService == null) {
            return null;
        }

        AiTokenQuotaService.Decision decision = aiTokenQuotaService.check(
                userId,
                scope,
                resolveDeviceId(request),
                resolveClientIp(request));
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

    private long estimateSpeechTokens(Long durationMs) {
        long durationSeconds = durationMs == null
                ? 0L
                : (long) Math.ceil(Math.max(0L, durationMs) / 1000.0);
        long billedSeconds = Math.max(Math.max(1L, speechMinBilledSeconds), durationSeconds);
        return Math.max(1L, billedSeconds * Math.max(1L, speechTokensPerBilledSecond));
    }

    // Every completed AI practice action (sentences, translation, chat, speech,
    // dictionary, reading, writing, exam, pronunciation) funnels through this
    // single method, so it is the one safe shared place to credit the daily
    // streak. Previously only SRS review and adding a new word touched the
    // streak, so a user who only did reading/writing/speaking practice on a
    // given day would still lose their streak the next day.
    private void consumeAiTokens(Long userId, HttpServletRequest request, String scope, long tokens) {
        if (aiTokenQuotaService != null) {
            // Best-effort: do not throw if quota bookkeeping fails.
            try {
                aiTokenQuotaService.consume(
                        userId,
                        scope,
                        Math.max(0, tokens),
                        resolveDeviceId(request),
                        resolveClientIp(request));
            } catch (Exception ignored) {
            }
        }
        creditDailyStreak(userId);
    }

    private void creditDailyStreak(Long userId) {
        if (progressService == null || userId == null) {
            return;
        }
        try {
            progressService.updateStreak(userId);
        } catch (Exception ignored) {
        }
    }

    private String resolveClientIp(HttpServletRequest request) {
        return clientIpResolver.resolve(request);
    }

    private String resolveDeviceId(HttpServletRequest request) {
        if (request == null) {
            return null;
        }
        String deviceId = request.getHeader("X-Device-Id");
        if (deviceId == null || deviceId.isBlank()) {
            return null;
        }
        return deviceId.trim();
    }

    private static final String ABUSE_BAN_REASON = "abuse-ban";
}
