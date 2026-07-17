package com.ingilizce.calismaapp.service;

import com.fasterxml.jackson.core.type.TypeReference;
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
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.stream.Collectors;

@Service
public class DailyWordsService {

    private static final Logger log = LoggerFactory.getLogger(DailyWordsService.class);
    private static final String CONTENT_TYPE = "daily_words_v3";
    private static final String PREVIOUS_CONTENT_TYPE = "daily_words_v2";
    private static final String LEGACY_CONTENT_TYPE = "daily_words_v1";

    private final DailyContentRepository dailyContentRepository;
    private final AiCompletionProvider aiCompletionProvider;
    private final ObjectMapper objectMapper;
    @Autowired(required = false)
    private AiModelRoutingService aiModelRoutingService;

    @Value("${groq.api.key:}")
    private String groqApiKey;

    private final Object generationLock = new Object();

    public DailyWordsService(DailyContentRepository dailyContentRepository,
                             AiCompletionProvider aiCompletionProvider,
                             ObjectMapper objectMapper) {
        this.dailyContentRepository = dailyContentRepository;
        this.aiCompletionProvider = aiCompletionProvider;
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
        LearningLanguageProfile profile = LearningLanguageProfile.defaultProfile();
        String topicCategory = PromptCatalog.topicForDay(date.getDayOfYear());
        Set<String> excludeWords = recentDailyWords(date.minusDays(30), date.minusDays(1));
        String excludeWordsCsv = excludeWords.isEmpty()
                ? "none"
                : excludeWords.stream().limit(80).collect(Collectors.joining(", "));

        String prompt = """
                %s

                Generate 5 "Word of the Day" vocabulary words for an intermediate %s learner.

                DATE: %s
                TODAY'S TOPIC CATEGORY: %s
                TARGET CEFR RANGE: A2-B2 (mix 2 Easy, 2 Medium, 1 Hard)
                EXCLUDE recently used words: [%s]

                VOCABULARY RULES:
                1. All 5 words must relate to the topic category but span different sub-topics.
                2. Include at least 2 different parts of speech.
                3. Choose useful real-world words, not obscure exam-only vocabulary.
                4. Avoid the most obvious beginner words for the topic.
                5. Example sentences must use varied subjects and contexts; at least one must be a question.
                6. Translations must sound natural in %s, not word-for-word.
                7. For each word, include 2-3 useful meanings/senses or common collocations when the word is polysemous.
                   If the word has one main meaning, include one main meaning and one common use/context.

                Return a JSON object with a "words" key containing an array of 5 objects.
                Each object must include these fields:
                - id (number 1-5)
                - word (String)
                - pronunciation (String, e.g. /.../ )
                - translation (String - primary %s meaning, short)
                - meanings (Array of 2-3 objects with: translation, sense, exampleSentence, exampleTranslation)
                - partOfSpeech (String - e.g. Noun, Verb)
                - definition (String - %s)
                - exampleSentence (String - %s)
                - exampleTranslation (String - %s)
                - synonyms (Array of Strings - max 3)
                - difficulty (String - Easy, Medium, or Hard)

                Return only valid JSON. No markdown.
                """.formatted(
                profile.toPromptPolicyBlock(),
                profile.targetLanguage(),
                date,
                topicCategory,
                excludeWordsCsv,
                profile.sourceLanguage(),
                profile.sourceLanguage(),
                profile.targetLanguage(),
                profile.targetLanguage(),
                profile.sourceLanguage()
        );

        List<Map<String, String>> messages = new ArrayList<>();
        messages.add(Map.of(
                "role", "system",
                "content", "You are a helpful language learning assistant. Return only valid JSON."
        ));
        messages.add(Map.of(
                "role", "user",
                "content", prompt
        ));

        String content = aiCompletionProvider.chatCompletion(messages, false, resolveModelForScope("daily-words-generate"));
        if (content == null || content.isBlank()) {
            throw new IllegalStateException("AI provider returned empty content");
        }

        // Ensure it's valid JSON and normalize (store compact JSON object).
        JsonNode node = parseLenientJsonObject(content);
        if (node == null || !node.isObject()) {
            throw new IllegalStateException("AI daily words payload is not a JSON object");
        }
        JsonNode wordsNode = node.get("words");
        if (wordsNode == null || !wordsNode.isArray() || wordsNode.size() != 5) {
            throw new IllegalStateException("AI daily words payload missing 'words' array");
        }
        validateDailyWordsPayload(wordsNode, excludeWords);
        return objectMapper.writeValueAsString(node);
    }

    private Set<String> recentDailyWords(LocalDate startDate, LocalDate endDate) {
        Set<String> words = new LinkedHashSet<>();
        collectWordsFromRecentContent(words, CONTENT_TYPE, startDate, endDate);
        collectWordsFromRecentContent(words, PREVIOUS_CONTENT_TYPE, startDate, endDate);
        collectWordsFromRecentContent(words, LEGACY_CONTENT_TYPE, startDate, endDate);
        return words;
    }

    private void collectWordsFromRecentContent(
            Set<String> sink,
            String contentType,
            LocalDate startDate,
            LocalDate endDate) {
        if (startDate == null || endDate == null || endDate.isBefore(startDate)) {
            return;
        }
        try {
            for (DailyContent content : dailyContentRepository
                    .findByContentTypeAndContentDateBetweenOrderByContentDateDesc(contentType, startDate, endDate)) {
                JsonNode root = objectMapper.readTree(content.getPayloadJson());
                JsonNode wordsNode = root.get("words");
                if (wordsNode == null || !wordsNode.isArray()) {
                    continue;
                }
                for (JsonNode wordNode : wordsNode) {
                    String word = normalizeWord(wordNode.path("word").asText(""));
                    if (!word.isBlank()) {
                        sink.add(word);
                    }
                }
            }
        } catch (Exception e) {
            log.debug("Could not collect recent daily words for contentType={}: {}", contentType, e.toString());
        }
    }

    private void validateDailyWordsPayload(JsonNode wordsNode, Set<String> excludeWords) {
        Set<String> seen = new HashSet<>();
        Set<String> partsOfSpeech = new HashSet<>();
        for (JsonNode wordNode : wordsNode) {
            String word = normalizeWord(wordNode.path("word").asText(""));
            if (word.isBlank()) {
                throw new IllegalStateException("AI daily words payload contains blank word");
            }
            if (!seen.add(word)) {
                throw new IllegalStateException("AI daily words payload contains duplicate word: " + word);
            }
            if (excludeWords.contains(word)) {
                throw new IllegalStateException("AI daily words payload repeated recent word: " + word);
            }
            requireNonBlank(wordNode, "pronunciation");
            requireNonBlank(wordNode, "translation");
            JsonNode meanings = wordNode.get("meanings");
            if (meanings == null || !meanings.isArray() || meanings.size() < 2) {
                throw new IllegalStateException("AI daily words payload needs at least 2 meanings for: " + word);
            }
            for (JsonNode meaning : meanings) {
                requireNonBlank(meaning, "translation");
                requireNonBlank(meaning, "sense");
                requireNonBlank(meaning, "exampleSentence");
                requireNonBlank(meaning, "exampleTranslation");
            }
            requireNonBlank(wordNode, "partOfSpeech");
            requireNonBlank(wordNode, "definition");
            requireNonBlank(wordNode, "exampleSentence");
            requireNonBlank(wordNode, "exampleTranslation");
            partsOfSpeech.add(wordNode.path("partOfSpeech").asText("").trim().toLowerCase());
        }
        if (partsOfSpeech.size() < 2) {
            throw new IllegalStateException("AI daily words payload needs at least 2 parts of speech");
        }
    }

    private void requireNonBlank(JsonNode node, String field) {
        if (node.path(field).asText("").trim().isEmpty()) {
            throw new IllegalStateException("AI daily words payload missing field: " + field);
        }
    }

    private String normalizeWord(String value) {
        return value == null ? "" : value.trim().toLowerCase();
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
        int variant = (daySeed % 8);

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

        if (variant == 2) {
            return List.of(
                    fallbackWord(1, "commute", "/kəˈmjuːt/", "işe gidip gelmek", "Verb", "To travel regularly between home and work.", "Many people commute by train in big cities.", "Büyük şehirlerde birçok insan işe trenle gidip gelir.", List.of("travel", "go back and forth", "journey"), "Easy"),
                    fallbackWord(2, "delay", "/dɪˈleɪ/", "gecikme", "Noun", "A period of waiting longer than expected.", "The flight delay gave us time for coffee.", "Uçuş gecikmesi bize kahve içmek için zaman verdi.", List.of("postponement", "hold-up", "wait"), "Easy"),
                    fallbackWord(3, "route", "/ruːt/", "rota", "Noun", "The way taken to reach a place.", "Which route avoids the morning traffic?", "Hangi rota sabah trafiğinden kaçınır?", List.of("path", "way", "course"), "Medium"),
                    fallbackWord(4, "navigate", "/ˈnæv.ɪ.ɡeɪt/", "yolunu bulmak", "Verb", "To find the right way through a place.", "The app helped us navigate the old city.", "Uygulama eski şehirde yolumuzu bulmamıza yardım etti.", List.of("find your way", "steer", "guide"), "Medium"),
                    fallbackWord(5, "accessible", "/əkˈses.ə.bəl/", "erişilebilir", "Adjective", "Easy to reach, enter, or use.", "Is the museum accessible by public transport?", "Müzeye toplu taşımayla erişilebilir mi?", List.of("reachable", "available", "usable"), "Hard")
            );
        }

        if (variant == 3) {
            return List.of(
                    fallbackWord(1, "ingredient", "/ɪnˈɡriː.di.ənt/", "malzeme", "Noun", "One food item used to make a dish.", "Fresh basil is the secret ingredient in this sauce.", "Bu sosun gizli malzemesi taze fesleğen.", List.of("component", "item", "element"), "Easy"),
                    fallbackWord(2, "stir", "/stɝː/", "karıştırmak", "Verb", "To mix something with a spoon.", "Stir the soup before you taste it.", "Çorbayı tatmadan önce karıştır.", List.of("mix", "blend", "move"), "Easy"),
                    fallbackWord(3, "portion", "/ˈpɔːr.ʃən/", "porsiyon", "Noun", "An amount of food for one person.", "The portions were small but delicious.", "Porsiyonlar küçüktü ama lezzetliydi.", List.of("serving", "amount", "share"), "Medium"),
                    fallbackWord(4, "savory", "/ˈseɪ.vɚ.i/", "tuzlu", "Adjective", "Having a salty or spicy taste, not sweet.", "Do you prefer savory snacks or sweet ones?", "Tuzlu atıştırmalıkları mı yoksa tatlı olanları mı tercih edersin?", List.of("salty", "spicy", "flavorful"), "Medium"),
                    fallbackWord(5, "leftovers", "/ˈleftˌoʊ.vɚz/", "artan yemek", "Noun", "Food that remains after a meal.", "We turned the leftovers into a quick lunch.", "Artan yemekleri hızlı bir öğle yemeğine dönüştürdük.", List.of("remaining food", "extras", "remains"), "Hard")
            );
        }

        if (variant == 4) {
            return List.of(
                    fallbackWord(1, "symptom", "/ˈsɪmp.təm/", "belirti", "Noun", "A sign of an illness or problem.", "A high fever can be a serious symptom.", "Yüksek ateş ciddi bir belirti olabilir.", List.of("sign", "indication", "warning"), "Easy"),
                    fallbackWord(2, "recover", "/rɪˈkʌv.ɚ/", "iyileşmek", "Verb", "To become healthy again after illness.", "He recovered quickly after a few days of rest.", "Birkaç gün dinlendikten sonra hızlıca iyileşti.", List.of("get better", "heal", "improve"), "Easy"),
                    fallbackWord(3, "balanced", "/ˈbæl.ənst/", "dengeli", "Adjective", "Having the right mix of different things.", "A balanced diet does not have to be complicated.", "Dengeli bir beslenme karmaşık olmak zorunda değil.", List.of("stable", "healthy", "well-mixed"), "Medium"),
                    fallbackWord(4, "exhausted", "/ɪɡˈzɑː.stɪd/", "bitkin", "Adjective", "Extremely tired.", "After the long shift, the nurse looked exhausted.", "Uzun vardiyadan sonra hemşire bitkin görünüyordu.", List.of("worn out", "drained", "tired"), "Medium"),
                    fallbackWord(5, "preventive", "/prɪˈven.t̬ɪv/", "önleyici", "Adjective", "Intended to stop something bad before it happens.", "Preventive care can reduce future health problems.", "Önleyici bakım gelecekteki sağlık sorunlarını azaltabilir.", List.of("protective", "precautionary", "proactive"), "Hard")
            );
        }

        if (variant == 5) {
            return List.of(
                    fallbackWord(1, "device", "/dɪˈvaɪs/", "cihaz", "Noun", "A tool or machine made for a purpose.", "This small device tracks your sleep.", "Bu küçük cihaz uykunu takip eder.", List.of("gadget", "tool", "machine"), "Easy"),
                    fallbackWord(2, "update", "/ˌʌpˈdeɪt/", "güncellemek", "Verb", "To make software or information newer.", "You should update the app before traveling.", "Seyahate çıkmadan önce uygulamayı güncellemelisin.", List.of("refresh", "upgrade", "revise"), "Easy"),
                    fallbackWord(3, "privacy", "/ˈpraɪ.və.si/", "gizlilik", "Noun", "The right to keep personal information secret.", "Online privacy matters more than many people realize.", "Çevrim içi gizlilik birçok kişinin sandığından daha önemlidir.", List.of("confidentiality", "secrecy", "personal space"), "Medium"),
                    fallbackWord(4, "reliable", "/rɪˈlaɪ.ə.bəl/", "güvenilir", "Adjective", "Able to be trusted or depended on.", "A reliable connection is essential for video calls.", "Video görüşmeleri için güvenilir bir bağlantı şarttır.", List.of("dependable", "trustworthy", "consistent"), "Medium"),
                    fallbackWord(5, "shortcut", "/ˈʃɔːrt.kʌt/", "kısayol", "Noun", "A quicker way to do or reach something.", "Which keyboard shortcut do you use most often?", "En sık hangi klavye kısayolunu kullanıyorsun?", List.of("quick route", "time-saver", "abbreviation"), "Hard")
            );
        }

        if (variant == 6) {
            return List.of(
                    fallbackWord(1, "deadline", "/ˈded.laɪn/", "son tarih", "Noun", "The latest time by which work must be finished.", "The deadline is Friday, so we need a clear plan.", "Son tarih cuma, bu yüzden net bir plana ihtiyacımız var.", List.of("due date", "time limit", "cutoff"), "Easy"),
                    fallbackWord(2, "brief", "/briːf/", "kısa", "Adjective", "Short in time or length.", "Could you give me a brief summary?", "Bana kısa bir özet verebilir misin?", List.of("short", "concise", "quick"), "Easy"),
                    fallbackWord(3, "negotiate", "/nəˈɡoʊ.ʃi.eɪt/", "müzakere etmek", "Verb", "To discuss terms to reach an agreement.", "They negotiated a better schedule for the team.", "Ekip için daha iyi bir program üzerinde müzakere ettiler.", List.of("discuss", "bargain", "arrange"), "Medium"),
                    fallbackWord(4, "proposal", "/prəˈpoʊ.zəl/", "öneri", "Noun", "A formal suggestion or plan.", "Her proposal solved the budget problem.", "Onun önerisi bütçe sorununu çözdü.", List.of("plan", "suggestion", "offer"), "Medium"),
                    fallbackWord(5, "accountable", "/əˈkaʊn.t̬ə.bəl/", "sorumlu", "Adjective", "Expected to explain and take responsibility.", "Managers should be accountable for their decisions.", "Yöneticiler kararlarından sorumlu olmalıdır.", List.of("responsible", "answerable", "liable"), "Hard")
            );
        }

        if (variant == 7) {
            return List.of(
                    fallbackWord(1, "habit", "/ˈhæb.ɪt/", "alışkanlık", "Noun", "Something you do regularly.", "A small habit can change your whole morning.", "Küçük bir alışkanlık bütün sabahını değiştirebilir.", List.of("routine", "custom", "practice"), "Easy"),
                    fallbackWord(2, "notice", "/ˈnoʊ.t̬ɪs/", "fark etmek", "Verb", "To become aware of something.", "Did you notice the new sign near the station?", "İstasyonun yanındaki yeni tabelayı fark ettin mi?", List.of("see", "observe", "spot"), "Easy"),
                    fallbackWord(3, "arrangement", "/əˈreɪndʒ.mənt/", "düzenleme", "Noun", "A plan or way things are organized.", "The seating arrangement made the meeting feel informal.", "Oturma düzeni toplantıyı samimi hissettirdi.", List.of("plan", "setup", "organization"), "Medium"),
                    fallbackWord(4, "ordinary", "/ˈɔːr.dən.er.i/", "sıradan", "Adjective", "Normal and not special.", "An ordinary walk became a surprisingly good idea.", "Sıradan bir yürüyüş şaşırtıcı derecede iyi bir fikre dönüştü.", List.of("normal", "usual", "common"), "Medium"),
                    fallbackWord(5, "adjustment", "/əˈdʒʌst.mənt/", "ayarlama", "Noun", "A small change made to improve something.", "One small adjustment made the schedule easier.", "Küçük bir ayarlama programı kolaylaştırdı.", List.of("change", "modification", "adaptation"), "Hard")
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

    private Map<String, Object> fallbackWord(
            int id,
            String word,
            String pronunciation,
            String translation,
            String partOfSpeech,
            String definition,
            String exampleSentence,
            String exampleTranslation,
            List<String> synonyms,
            String difficulty) {
        return Map.ofEntries(
                Map.entry("id", id),
                Map.entry("word", word),
                Map.entry("pronunciation", pronunciation),
                Map.entry("translation", translation),
                Map.entry("meanings", fallbackMeanings(translation, definition, exampleSentence, exampleTranslation)),
                Map.entry("partOfSpeech", partOfSpeech),
                Map.entry("definition", definition),
                Map.entry("exampleSentence", exampleSentence),
                Map.entry("exampleTranslation", exampleTranslation),
                Map.entry("synonyms", synonyms),
                Map.entry("difficulty", difficulty));
    }

    private List<Map<String, String>> fallbackMeanings(
            String translation,
            String definition,
            String exampleSentence,
            String exampleTranslation) {
        return List.of(
                Map.of(
                        "translation", translation,
                        "sense", definition,
                        "exampleSentence", exampleSentence,
                        "exampleTranslation", exampleTranslation),
                Map.of(
                        "translation", translation,
                        "sense", "Common use in everyday English.",
                        "exampleSentence", exampleSentence,
                        "exampleTranslation", exampleTranslation));
    }

    private String resolveModelForScope(String scope) {
        if (aiModelRoutingService == null) {
            return null;
        }
        return aiModelRoutingService.resolveModelForScope(scope);
    }
}
