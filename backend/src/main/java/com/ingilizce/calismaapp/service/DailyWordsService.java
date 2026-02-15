package com.ingilizce.calismaapp.service;

import com.fasterxml.jackson.core.type.TypeReference;
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
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;

@Service
public class DailyWordsService {

    private static final Logger log = LoggerFactory.getLogger(DailyWordsService.class);
    private static final String CONTENT_TYPE = "daily_words_v1";

    private final DailyContentRepository dailyContentRepository;
    private final GroqService groqService;
    private final ObjectMapper objectMapper;

    @Value("${groq.api.key:}")
    private String groqApiKey;

    private final Object generationLock = new Object();

    public DailyWordsService(DailyContentRepository dailyContentRepository,
                             GroqService groqService,
                             ObjectMapper objectMapper) {
        this.dailyContentRepository = dailyContentRepository;
        this.groqService = groqService;
        this.objectMapper = objectMapper;
    }

    public List<Map<String, Object>> getDailyWords(LocalDate date) {
        LocalDate normalized = date != null ? date : LocalDate.now();

        Optional<DailyContent> cached = dailyContentRepository
                .findByContentDateAndContentType(normalized, CONTENT_TYPE);
        if (cached.isPresent()) {
            return decodeWordsList(cached.get().getPayloadJson());
        }

        synchronized (generationLock) {
            cached = dailyContentRepository.findByContentDateAndContentType(normalized, CONTENT_TYPE);
            if (cached.isPresent()) {
                return decodeWordsList(cached.get().getPayloadJson());
            }

            String payloadJson = null;
            if (groqApiKey != null && !groqApiKey.isBlank()) {
                try {
                    payloadJson = generateDailyWordsPayload(normalized);
                } catch (Exception e) {
                    // Do not persist failures; allow future retries when Groq recovers.
                    log.warn("Daily words generation failed for date={}: {}", normalized, e.toString());
                }
            } else {
                log.info("Groq API key not configured; daily words will use fallback data");
            }

            if (payloadJson == null || payloadJson.isBlank()) {
                return fallbackWords(normalized);
            }

            try {
                dailyContentRepository.save(new DailyContent(normalized, CONTENT_TYPE, payloadJson));
            } catch (DataIntegrityViolationException ignored) {
                // Another concurrent request may have inserted; fetch and use it.
            }

            return decodeWordsList(payloadJson);
        }
    }

    private String generateDailyWordsPayload(LocalDate date) throws Exception {
        String prompt = """
                Generate 5 "Word of the Day" vocabulary words for an intermediate English learner.

                Date seed: %s

                Return a JSON object with a "words" key containing an array of 5 objects.
                Each object must have exactly these fields:
                - id (number 1-5)
                - word (String)
                - pronunciation (String, e.g. /.../ )
                - translation (String - Turkish)
                - partOfSpeech (String - e.g. Noun, Verb)
                - definition (String - English)
                - exampleSentence (String - English)
                - exampleTranslation (String - Turkish)
                - synonyms (Array of Strings - max 3)
                - difficulty (String - Easy, Medium, or Hard)

                Return only valid JSON. No markdown.
                """.formatted(date);

        List<Map<String, String>> messages = new ArrayList<>();
        messages.add(Map.of(
                "role", "system",
                "content", "You are a helpful language learning assistant. Return only valid JSON."
        ));
        messages.add(Map.of(
                "role", "user",
                "content", prompt
        ));

        String content = groqService.chatCompletion(messages, true);
        if (content == null || content.isBlank()) {
            throw new IllegalStateException("Groq returned empty content");
        }

        // Ensure it's valid JSON and normalize (store compact JSON object).
        JsonNode node = parseLenientJsonObject(content);
        if (node == null || !node.isObject()) {
            throw new IllegalStateException("Groq daily words payload is not a JSON object");
        }
        JsonNode wordsNode = node.get("words");
        if (wordsNode == null || !wordsNode.isArray() || wordsNode.size() < 1) {
            throw new IllegalStateException("Groq daily words payload missing 'words' array");
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

    private List<Map<String, Object>> decodeWordsList(String payloadJson) {
        if (payloadJson == null || payloadJson.isBlank()) {
            return List.of();
        }
        try {
            JsonNode root = objectMapper.readTree(payloadJson);
            JsonNode words = root.get("words");
            if (words == null || !words.isArray()) {
                return List.of();
            }
            return objectMapper.convertValue(words, new TypeReference<>() {});
        } catch (Exception e) {
            return List.of();
        }
    }

    private List<Map<String, Object>> fallbackWords(LocalDate date) {
        // Minimal offline-safe fallback, deterministic per date.
        // This avoids "missing section" when Groq is not configured.
        int daySeed = Math.abs(date.toString().hashCode());
        int variant = (daySeed % 3);

        if (variant == 0) {
            return List.of(
                    Map.of("id", 1, "word", "resilient", "pronunciation", "/rɪˈzɪl.jənt/", "translation", "dayanıklı",
                            "partOfSpeech", "Adjective", "definition", "Able to recover quickly from difficulties.",
                            "exampleSentence", "She stayed resilient during the stressful week.",
                            "exampleTranslation", "Stresli hafta boyunca dayanıklı kaldı.",
                            "synonyms", List.of("tough", "strong", "adaptable"), "difficulty", "Medium"),
                    Map.of("id", 2, "word", "insight", "pronunciation", "/ˈɪn.saɪt/", "translation", "içgörü",
                            "partOfSpeech", "Noun", "definition", "A deep understanding of a person or situation.",
                            "exampleSentence", "The book gave me insight into modern habits.",
                            "exampleTranslation", "Kitap bana modern alışkanlıklar hakkında içgörü verdi.",
                            "synonyms", List.of("understanding", "perception", "awareness"), "difficulty", "Medium"),
                    Map.of("id", 3, "word", "enhance", "pronunciation", "/ɪnˈhæns/", "translation", "geliştirmek",
                            "partOfSpeech", "Verb", "definition", "To improve the quality or value of something.",
                            "exampleSentence", "Reading daily can enhance your vocabulary.",
                            "exampleTranslation", "Her gün okumak kelime dağarcığını geliştirebilir.",
                            "synonyms", List.of("improve", "boost", "refine"), "difficulty", "Easy"),
                    Map.of("id", 4, "word", "diligent", "pronunciation", "/ˈdɪl.ɪ.dʒənt/", "translation", "çalışkan",
                            "partOfSpeech", "Adjective", "definition", "Having or showing careful and persistent work.",
                            "exampleSentence", "He is diligent about reviewing his notes.",
                            "exampleTranslation", "Notlarını gözden geçirme konusunda çalışkandır.",
                            "synonyms", List.of("hardworking", "careful", "thorough"), "difficulty", "Medium"),
                    Map.of("id", 5, "word", "subtle", "pronunciation", "/ˈsʌt.əl/", "translation", "ince",
                            "partOfSpeech", "Adjective", "definition", "Not obvious; delicate or understated.",
                            "exampleSentence", "There was a subtle change in her tone.",
                            "exampleTranslation", "Tonunda ince bir değişiklik vardı.",
                            "synonyms", List.of("delicate", "slight", "nuanced"), "difficulty", "Hard")
            );
        }

        if (variant == 1) {
            return List.of(
                    Map.of("id", 1, "word", "clarify", "pronunciation", "/ˈklær.ə.faɪ/", "translation", "netleştirmek",
                            "partOfSpeech", "Verb", "definition", "To make something clear or easier to understand.",
                            "exampleSentence", "Could you clarify what you mean by that?",
                            "exampleTranslation", "Ne demek istediğini netleştirebilir misin?",
                            "synonyms", List.of("explain", "define", "clear up"), "difficulty", "Easy"),
                    Map.of("id", 2, "word", "consistent", "pronunciation", "/kənˈsɪs.tənt/", "translation", "tutarlı",
                            "partOfSpeech", "Adjective", "definition", "Always behaving or happening in the same way.",
                            "exampleSentence", "Consistency is key when learning a language.",
                            "exampleTranslation", "Dil öğrenirken tutarlılık çok önemlidir.",
                            "synonyms", List.of("steady", "reliable", "uniform"), "difficulty", "Medium"),
                    Map.of("id", 3, "word", "overcome", "pronunciation", "/ˌoʊ.vɚˈkʌm/", "translation", "üstesinden gelmek",
                            "partOfSpeech", "Verb", "definition", "To succeed in dealing with a problem or difficulty.",
                            "exampleSentence", "She overcame her fear of speaking in public.",
                            "exampleTranslation", "Topluluk önünde konuşma korkusunu yendi.",
                            "synonyms", List.of("defeat", "conquer", "surmount"), "difficulty", "Medium"),
                    Map.of("id", 4, "word", "efficient", "pronunciation", "/ɪˈfɪʃ.ənt/", "translation", "verimli",
                            "partOfSpeech", "Adjective", "definition", "Working well without wasting time or energy.",
                            "exampleSentence", "This method is more efficient for revision.",
                            "exampleTranslation", "Bu yöntem tekrar için daha verimli.",
                            "synonyms", List.of("effective", "productive", "streamlined"), "difficulty", "Easy"),
                    Map.of("id", 5, "word", "inevitable", "pronunciation", "/ɪnˈev.ɪ.t̬ə.bəl/", "translation", "kaçınılmaz",
                            "partOfSpeech", "Adjective", "definition", "Certain to happen; unavoidable.",
                            "exampleSentence", "Mistakes are inevitable when you're learning.",
                            "exampleTranslation", "Öğrenirken hatalar kaçınılmazdır.",
                            "synonyms", List.of("unavoidable", "certain", "inescapable"), "difficulty", "Hard")
            );
        }

        return List.of(
                Map.of("id", 1, "word", "prioritize", "pronunciation", "/praɪˈɔːr.ə.taɪz/", "translation", "öncelik vermek",
                        "partOfSpeech", "Verb", "definition", "To decide what is most important and deal with it first.",
                        "exampleSentence", "I need to prioritize my study plan this week.",
                        "exampleTranslation", "Bu hafta çalışma planıma öncelik vermem gerekiyor.",
                        "synonyms", List.of("rank", "focus on", "emphasize"), "difficulty", "Medium"),
                Map.of("id", 2, "word", "retain", "pronunciation", "/rɪˈteɪn/", "translation", "akılda tutmak",
                        "partOfSpeech", "Verb", "definition", "To keep or continue to have something.",
                        "exampleSentence", "Short reviews help you retain new words.",
                        "exampleTranslation", "Kısa tekrarlar yeni kelimeleri akılda tutmana yardımcı olur.",
                        "synonyms", List.of("keep", "hold", "preserve"), "difficulty", "Medium"),
                Map.of("id", 3, "word", "accurate", "pronunciation", "/ˈæk.jɚ.ət/", "translation", "doğru",
                        "partOfSpeech", "Adjective", "definition", "Correct in all details; exact.",
                        "exampleSentence", "Try to be accurate with your pronunciation.",
                        "exampleTranslation", "Telaffuzunda doğru olmaya çalış.",
                        "synonyms", List.of("correct", "precise", "exact"), "difficulty", "Easy"),
                Map.of("id", 4, "word", "adapt", "pronunciation", "/əˈdæpt/", "translation", "uyum sağlamak",
                        "partOfSpeech", "Verb", "definition", "To change to fit a new situation.",
                        "exampleSentence", "You can adapt the sentence to your own experience.",
                        "exampleTranslation", "Cümleyi kendi deneyimine göre uyarlayabilirsin.",
                        "synonyms", List.of("adjust", "modify", "tailor"), "difficulty", "Easy"),
                Map.of("id", 5, "word", "compelling", "pronunciation", "/kəmˈpel.ɪŋ/", "translation", "etkileyici",
                        "partOfSpeech", "Adjective", "definition", "Very interesting or convincing.",
                        "exampleSentence", "She made a compelling argument in her essay.",
                        "exampleTranslation", "Denemesinde çok etkileyici bir argüman sundu.",
                        "synonyms", List.of("convincing", "engaging", "persuasive"), "difficulty", "Hard")
        );
    }
}

