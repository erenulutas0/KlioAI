package com.ingilizce.calismaapp.controller;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ingilizce.calismaapp.entity.LanguageProfile;
import com.ingilizce.calismaapp.entity.Sentence;
import com.ingilizce.calismaapp.entity.Word;
import com.ingilizce.calismaapp.repository.LanguageProfileRepository;
import com.ingilizce.calismaapp.repository.SentenceRepository;
import com.ingilizce.calismaapp.repository.WordMeaningRepository;
import com.ingilizce.calismaapp.repository.WordRepository;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicLong;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * The promises V028 made to the client that is already on phones (v1.2.0), checked against
 * the real controllers, services and repositories on H2 with only Redis mocked.
 *
 * <p>Every request body here is the exact shape the shipped {@code ApiService} sends, and
 * the response keys asserted are the exact set the pre-V028 server emitted (a superset of
 * what {@code Word.fromJson} / {@code Sentence.fromJson} read). If any of these tests
 * fails, a learner who has not updated the app is broken -- which is why the bodies are
 * spelled out rather than built from the entities (an entity field rename would silently
 * rename the request too).
 *
 * <p>Two tests ({@code oldClientDeleteSentence_Returns200WithTheWord} and
 * {@code oldClientSubmitReview_Returns200WithTheWord}) pin a 200 that the pre-V028 code
 * did not deliver either in this configuration; see the notes on them.
 *
 * <p>Not {@code @Transactional}: the meaning-delete and word-delete paths depend on the
 * real flush/commit ordering, and the point of the "nothing is stored" assertions is to
 * read back through the repositories after the request has committed. Each test uses its
 * own user id instead of cleaning up.
 */
@SpringBootTest
@AutoConfigureMockMvc
@TestPropertySource(properties = {
        "GROQ_API_KEY=dummy-key",
        "spring.datasource.url=jdbc:h2:mem:shippedclientdb;DB_CLOSE_DELAY=-1;MODE=PostgreSQL",
        "spring.datasource.driver-class-name=org.h2.Driver"
})
class ShippedClientCompatibilityIntegrationTest {

    private static final AtomicLong NEXT_USER = new AtomicLong(9500);

    /**
     * Every key a word carried before V028 -- the exact set the pre-V028 server emitted,
     * taken from running that code, not from the client. v1.2.0's {@code Word.fromJson}
     * reads all of them except {@code userId}; the promise covers all of them anyway.
     */
    private static final List<String> PRE_V028_WORD_KEYS = List.of(
            "id", "userId", "englishWord", "turkishMeaning", "sourceMeaning", "learnedDate", "notes", "difficulty",
            "nextReviewDate", "reviewCount", "easeFactor", "lastReviewDate", "sentences");

    /** Every key a sentence carried before V028; v1.2.0's {@code Sentence.fromJson} reads all of them. */
    private static final List<String> PRE_V028_SENTENCE_KEYS = List.of(
            "id", "sentence", "translation", "sourceTranslation", "wordId", "difficulty");

    /** The documented shape of the new keys. */
    private static final List<String> MEANING_KEYS = List.of("id", "translation", "definition", "position");
    private static final List<String> PROFILE_KEYS = List.of(
            "id", "sourceLanguage", "targetLanguage", "level", "learningGoal", "isActive", "createdAt");

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
    private LanguageProfileRepository profileRepository;

    @Autowired
    private WordRepository wordRepository;

    @Autowired
    private WordMeaningRepository meaningRepository;

    @Autowired
    private SentenceRepository sentenceRepository;

    @MockBean
    private RedisTemplate<String, String> redisTemplate;

    // ---- helpers ----

    private static String user() {
        return Long.toString(NEXT_USER.incrementAndGet());
    }

    private JsonNode perform(MockHttpServletRequestBuilder request, String userId, int expectedStatus) throws Exception {
        MvcResult result = mockMvc.perform(request.header("X-User-Id", userId))
                .andExpect(status().is(expectedStatus))
                .andReturn();
        String content = result.getResponse().getContentAsString();
        return content.isEmpty() ? null : objectMapper.readTree(content);
    }

    private JsonNode getJson(String path, String userId, int expectedStatus) throws Exception {
        return perform(get(path), userId, expectedStatus);
    }

    private JsonNode postJson(String path, String userId, String body, int expectedStatus) throws Exception {
        return perform(post(path).contentType(MediaType.APPLICATION_JSON).content(body), userId, expectedStatus);
    }

    private JsonNode putJson(String path, String userId, String body, int expectedStatus) throws Exception {
        return perform(put(path).contentType(MediaType.APPLICATION_JSON).content(body), userId, expectedStatus);
    }

    private JsonNode deleteJson(String path, String userId, int expectedStatus) throws Exception {
        return perform(delete(path), userId, expectedStatus);
    }

    /** Exactly what v1.2.0's {@code ApiService.createWord} sends: no meanings, no profile, no origin. */
    private JsonNode createShippedWord(String userId, String english, String turkish, String learnedDate) throws Exception {
        return postJson("/api/words", userId, """
                {"englishWord":"%s","turkishMeaning":"%s","sourceMeaning":"%s","learnedDate":"%s","notes":"","difficulty":"easy"}
                """.formatted(english, turkish, turkish, learnedDate), 200);
    }

    /** Exactly what v1.2.0's {@code ApiService.addSentenceToWord} sends: no meaningId. */
    private JsonNode addShippedSentence(String userId, long wordId, String sentence, String translation, int expectedStatus)
            throws Exception {
        return postJson("/api/words/" + wordId + "/sentences", userId, """
                {"sentence":"%s","translation":"%s","sourceTranslation":"%s","difficulty":"easy"}
                """.formatted(sentence, translation, translation), expectedStatus);
    }

    private JsonNode addSentenceWithMeaning(String userId, long wordId, String sentence, String translation, long meaningId,
            int expectedStatus) throws Exception {
        return postJson("/api/words/" + wordId + "/sentences", userId, """
                {"sentence":"%s","translation":"%s","sourceTranslation":"%s","difficulty":"easy","meaningId":%d}
                """.formatted(sentence, translation, translation, meaningId), expectedStatus);
    }

    private JsonNode createProfile(String userId, String target, int expectedStatus) throws Exception {
        return postJson("/api/language-profiles", userId,
                "{\"sourceLanguage\":\"Turkish\",\"targetLanguage\":\"" + target + "\"}", expectedStatus);
    }

    private static void assertHasKeys(JsonNode node, List<String> keys, String what) {
        List<String> missing = new ArrayList<>();
        for (String key : keys) {
            if (!node.has(key)) {
                missing.add(key);
            }
        }
        assertTrue(missing.isEmpty(), what + " is missing keys " + missing + " in " + node);
    }

    private static void assertShippedWordKeys(JsonNode word) {
        assertHasKeys(word, PRE_V028_WORD_KEYS, "word");
        assertTrue(word.get("id").isIntegralNumber(), "id is a number");
        assertTrue(word.get("englishWord").isTextual());
        assertTrue(word.get("turkishMeaning").isTextual());
        assertEquals(word.get("turkishMeaning").asText(), word.get("sourceMeaning").asText(),
                "sourceMeaning is the same string as turkishMeaning; the client prefers it");
        assertDoesNotThrow(() -> LocalDate.parse(word.get("learnedDate").asText()), "learnedDate is an ISO date");
        assertTrue(word.get("reviewCount").isIntegralNumber());
        assertTrue(word.get("sentences").isArray());
        for (JsonNode sentence : word.get("sentences")) {
            assertShippedSentenceKeys(sentence);
        }
    }

    private static void assertShippedSentenceKeys(JsonNode sentence) {
        assertHasKeys(sentence, PRE_V028_SENTENCE_KEYS, "sentence");
        assertTrue(sentence.get("id").isIntegralNumber());
        assertTrue(sentence.get("wordId").isIntegralNumber(), "wordId is the first thing the client looks at");
        assertEquals(sentence.get("translation").asText(), sentence.get("sourceTranslation").asText());
    }

    private static void assertMeaningShape(JsonNode meaning) {
        assertHasKeys(meaning, MEANING_KEYS, "meaning");
        assertTrue(meaning.get("id").isIntegralNumber());
        assertTrue(meaning.get("translation").isTextual());
        assertTrue(meaning.get("position").isIntegralNumber());
        assertFalse(meaning.has("word"), "the back-reference to the word must not be serialised");
        assertFalse(meaning.has("hibernateLazyInitializer"), "no proxy internals in the JSON");
    }

    private static void assertProfileShape(JsonNode profile) {
        assertHasKeys(profile, PROFILE_KEYS, "language profile");
        assertTrue(profile.get("isActive").isBoolean(), "isActive is a JSON boolean under that exact name");
    }

    /** v1.2.0's {@code Word.isFromDailyWords}: the star in the legacy string is the only provenance it knows. */
    private static boolean shippedClientSeesDailyWords(JsonNode word) {
        String meaning = word.get("sourceMeaning").asText();
        return meaning.contains("⭐") || meaning.contains("★");
    }

    /** v1.2.0's {@code Word.displayMeaning}. */
    private static String shippedClientDisplayMeaning(JsonNode word) {
        return word.get("sourceMeaning").asText().replace("⭐", "").replace("★", "").trim();
    }

    private List<String> translationsOf(JsonNode word) {
        List<String> translations = new ArrayList<>();
        for (JsonNode meaning : word.get("meanings")) {
            translations.add(meaning.get("translation").asText());
        }
        return translations;
    }

    private long activeProfileId(String userId) {
        return profileRepository.findByUserIdAndIsActiveTrue(Long.parseLong(userId)).orElseThrow().getId();
    }

    private long countActiveProfiles(String userId) {
        return profileRepository.findByUserId(Long.parseLong(userId)).stream().filter(LanguageProfile::isActive).count();
    }

    // ---- old-client word creation ----

    @Test
    void oldClientCreateWord_ReturnsEveryKeyItReads_PlusMeaningsDerivedFromTheLegacyString() throws Exception {
        String userId = user();

        JsonNode created = createShippedWord(userId, "delay", "⭐ gecikme, ertelemek", "2026-08-20");

        // The old contract, key by key, with the old meaning of each.
        assertShippedWordKeys(created);
        assertEquals("delay", created.get("englishWord").asText());
        assertEquals("⭐ gecikme, ertelemek", created.get("turkishMeaning").asText(),
                "the legacy string comes back untouched: the star is what marks a daily word on the old client");
        assertEquals("2026-08-20", created.get("learnedDate").asText());
        assertEquals("", created.get("notes").asText());
        assertEquals("easy", created.get("difficulty").asText());
        assertEquals(0, created.get("reviewCount").asInt());
        assertEquals(2.5, created.get("easeFactor").asDouble(), 0.0001);
        assertFalse(created.get("nextReviewDate").isNull(), "a new word is scheduled, as before V028");
        assertTrue(created.get("lastReviewDate").isNull());
        assertEquals(0, created.get("sentences").size());
        assertTrue(shippedClientSeesDailyWords(created));
        assertEquals("gecikme, ertelemek", shippedClientDisplayMeaning(created));

        // The new keys, additive.
        assertEquals("daily_words", created.get("origin").asText());
        assertEquals(activeProfileId(userId), created.get("languageProfileId").asLong());
        JsonNode meanings = created.get("meanings");
        assertEquals(2, meanings.size(), "no meanings sent -> split from turkishMeaning");
        for (JsonNode meaning : meanings) {
            assertMeaningShape(meaning);
        }
        assertEquals(List.of("gecikme", "ertelemek"), translationsOf(created), "marker stripped, order kept");
        assertEquals(0, meanings.get(0).get("position").asInt());
        assertEquals(1, meanings.get(1).get("position").asInt());
        assertTrue(meanings.get(0).get("definition").isNull());
        assertFalse(created.has("languageProfile"), "the profile object itself is not part of a word");

        // Persisted, not just echoed.
        long wordId = created.get("id").asLong();
        assertEquals(2, meaningRepository.countByWordId(wordId));
        Word stored = wordRepository.findById(wordId).orElseThrow();
        assertEquals("⭐ gecikme, ertelemek", stored.getTurkishMeaning());
        assertEquals("daily_words", stored.getOrigin());

        // The same keys on the two reads the old client does.
        JsonNode byId = getJson("/api/words/" + wordId, userId, 200);
        assertShippedWordKeys(byId);
        assertEquals(List.of("gecikme", "ertelemek"), translationsOf(byId));

        JsonNode list = getJson("/api/words", userId, 200);
        assertEquals(1, list.size());
        assertShippedWordKeys(list.get(0));
        assertEquals(wordId, list.get(0).get("id").asLong());
        assertEquals(2, list.get(0).get("meanings").size());
    }

    @Test
    void oldClientCreateWord_WithoutAMarker_IsManual_AndASingleMeaningStaysSingle() throws Exception {
        String userId = user();

        JsonNode created = createShippedWord(userId, "canvas", "tuval", "2026-08-20");

        assertShippedWordKeys(created);
        assertEquals("tuval", created.get("turkishMeaning").asText());
        assertFalse(shippedClientSeesDailyWords(created));
        assertEquals("manual", created.get("origin").asText());
        assertEquals(List.of("tuval"), translationsOf(created));
        assertEquals(1, meaningRepository.countByWordId(created.get("id").asLong()));
    }

    @Test
    void oldClientCreateWord_ReplayedByOfflineSync_ReturnsTheSameWord_WithoutDuplicatingMeanings() throws Exception {
        // The shipped client replays queued creates after reconnecting; before V028 the second
        // POST returned the existing word. It still must, and it must not grow a second set of
        // meanings on the way.
        String userId = user();
        JsonNode first = createShippedWord(userId, "delay", "gecikme, ertelemek", "2026-08-20");
        JsonNode second = createShippedWord(userId, "delay", "gecikme, ertelemek", "2026-08-20");

        assertEquals(first.get("id").asLong(), second.get("id").asLong());
        assertShippedWordKeys(second);
        assertEquals(List.of("gecikme", "ertelemek"), translationsOf(second));
        assertEquals(2, meaningRepository.countByWordId(first.get("id").asLong()));
        assertEquals(1, getJson("/api/words", userId, 200).size());
    }

    // ---- old-client sentence creation ----

    @Test
    void oldClientAddSentence_StoresItUnassigned_AndReturnsTheSentenceKeysItReads() throws Exception {
        String userId = user();
        long wordId = createShippedWord(userId, "delay", "gecikme, ertelemek", "2026-08-20").get("id").asLong();

        JsonNode word = addShippedSentence(userId, wordId, "The train was delayed.", "Tren gecikti.", 200);

        assertShippedWordKeys(word);
        assertEquals(1, word.get("sentences").size());
        JsonNode sentence = word.get("sentences").get(0);
        assertShippedSentenceKeys(sentence);
        assertEquals("The train was delayed.", sentence.get("sentence").asText());
        assertEquals("Tren gecikti.", sentence.get("translation").asText());
        assertEquals("easy", sentence.get("difficulty").asText());
        assertEquals(wordId, sentence.get("wordId").asLong());
        assertTrue(sentence.has("meaningId"), "the new key is present");
        assertTrue(sentence.get("meaningId").isNull(), "no meaningId sent -> unassigned, never guessed");
        assertFalse(sentence.has("meaning"), "the meaning object is not nested in a sentence");

        List<Sentence> stored = sentenceRepository.findByWordId(wordId);
        assertEquals(1, stored.size());
        assertNull(stored.get(0).getMeaning(), "unassigned in the database too");

        // The word's own sentence list (the other read the old client does) says the same.
        JsonNode sentences = getJson("/api/words/" + wordId + "/sentences", userId, 200);
        assertEquals(1, sentences.size());
        assertShippedSentenceKeys(sentences.get(0));
        assertTrue(sentences.get(0).get("meaningId").isNull());

        // And it is still idempotent, as before.
        JsonNode again = addShippedSentence(userId, wordId, "The train was delayed.", "Tren gecikti.", 200);
        assertEquals(1, again.get("sentences").size());
        assertEquals(1, sentenceRepository.findByWordId(wordId).size());
    }

    @Test
    void addSentence_WithAMeaningOfAnotherWord_IsRejected_AndNothingIsStored() throws Exception {
        String userId = user();
        String otherUser = user();
        long wordA = createShippedWord(userId, "delay", "gecikme, ertelemek", "2026-08-20").get("id").asLong();
        JsonNode wordB = createShippedWord(userId, "canvas", "tuval", "2026-08-20");
        long meaningOfB = wordB.get("meanings").get(0).get("id").asLong();
        JsonNode wordC = createShippedWord(otherUser, "delay", "gecikme", "2026-08-20");
        long meaningOfC = wordC.get("meanings").get(0).get("id").asLong();

        // A meaning that exists but belongs to another word of the same user.
        addSentenceWithMeaning(userId, wordA, "Nope.", "Hayır.", meaningOfB, 400);
        // A meaning that belongs to another user's word.
        addSentenceWithMeaning(userId, wordA, "Nope.", "Hayır.", meaningOfC, 400);
        // A meaning that does not exist at all.
        addSentenceWithMeaning(userId, wordA, "Nope.", "Hayır.", 987654321L, 400);
        // A word that is not the caller's keeps the old answer: 404, not 403.
        addShippedSentence(otherUser, wordA, "Nope.", "Hayır.", 404);

        assertTrue(sentenceRepository.findByWordId(wordA).isEmpty(), "a rejected sentence is not stored");
        assertTrue(sentenceRepository.findByWordId(wordB.get("id").asLong()).isEmpty());
        assertTrue(sentenceRepository.findByWordId(wordC.get("id").asLong()).isEmpty());

        // The meaning's own word still accepts it.
        JsonNode attached = addSentenceWithMeaning(userId, wordB.get("id").asLong(), "A blank canvas.", "Boş bir tuval.",
                meaningOfB, 200);
        assertEquals(meaningOfB, attached.get("sentences").get(0).get("meaningId").asLong());
        assertShippedSentenceKeys(attached.get("sentences").get(0));
    }

    // ---- meaning deletion ----

    @Test
    void deleteMeaning_RefusesTheLastOne_AndLeavesTheOthersSentencesUnassigned() throws Exception {
        String userId = user();
        JsonNode created = createShippedWord(userId, "delay", "⭐ gecikme, ertelemek", "2026-08-20");
        long wordId = created.get("id").asLong();
        long delayMeaning = created.get("meanings").get(0).get("id").asLong();
        long postponeMeaning = created.get("meanings").get(1).get("id").asLong();

        long attachedToDelay = addSentenceWithMeaning(userId, wordId, "The train was delayed.", "Tren gecikti.",
                delayMeaning, 200).get("sentences").get(0).get("id").asLong();
        long attachedToPostpone = addSentenceWithMeaning(userId, wordId, "They delayed the meeting.",
                "Toplantıyı ertelediler.", postponeMeaning, 200).get("sentences").get(1).get("id").asLong();
        long unassigned = addShippedSentence(userId, wordId, "Sorry for the delay.", "Gecikme için üzgünüm.", 200)
                .get("sentences").get(2).get("id").asLong();

        // Delete a non-last meaning: its sentences survive, now unassigned; the others are untouched.
        JsonNode afterDelete = deleteJson("/api/words/" + wordId + "/meanings/" + postponeMeaning, userId, 200);
        assertShippedWordKeys(afterDelete);
        assertEquals(List.of("gecikme"), translationsOf(afterDelete));
        assertEquals(3, afterDelete.get("sentences").size(), "no sentence is deleted with its meaning");
        for (JsonNode sentence : afterDelete.get("sentences")) {
            long id = sentence.get("id").asLong();
            if (id == attachedToPostpone) {
                assertTrue(sentence.get("meaningId").isNull(), "the deleted meaning's sentence is unassigned");
            } else if (id == attachedToDelay) {
                assertEquals(delayMeaning, sentence.get("meaningId").asLong(), "the other meaning keeps its sentence");
            } else {
                assertEquals(unassigned, id);
                assertTrue(sentence.get("meaningId").isNull());
            }
        }
        // The legacy string follows the meanings, and the old client still sees a daily word.
        assertTrue(shippedClientSeesDailyWords(afterDelete), "the star survives a meaning edit");
        assertEquals("gecikme", shippedClientDisplayMeaning(afterDelete));

        // After commit, through the repositories.
        assertTrue(meaningRepository.findById(postponeMeaning).isEmpty());
        assertTrue(meaningRepository.findById(delayMeaning).isPresent());
        List<Sentence> stored = sentenceRepository.findByWordId(wordId);
        assertEquals(3, stored.size());
        for (Sentence sentence : stored) {
            if (sentence.getId() == attachedToDelay) {
                assertNotNull(sentence.getMeaning());
                assertEquals(delayMeaning, sentence.getMeaning().getId());
            } else {
                assertNull(sentence.getMeaning());
            }
        }
        assertEquals("⭐ gecikme", wordRepository.findById(wordId).orElseThrow().getTurkishMeaning());

        // The last meaning cannot go: 400 with a message, and nothing changes.
        JsonNode refused = deleteJson("/api/words/" + wordId + "/meanings/" + delayMeaning, userId, 400);
        assertNotNull(refused);
        assertTrue(refused.has("error"), "the client shows this message");
        assertEquals(1, meaningRepository.countByWordId(wordId));
        assertTrue(meaningRepository.findById(delayMeaning).isPresent());
        Sentence stillAttached = sentenceRepository.findById(attachedToDelay).orElseThrow();
        assertNotNull(stillAttached.getMeaning(), "a refused delete has no side effects on the sentences");
        assertEquals(delayMeaning, stillAttached.getMeaning().getId());
        assertEquals("⭐ gecikme", wordRepository.findById(wordId).orElseThrow().getTurkishMeaning());

        // Another user cannot delete it either, and gets no confirmation the id exists.
        deleteJson("/api/words/" + wordId + "/meanings/" + delayMeaning, user(), 404);
        assertEquals(1, meaningRepository.countByWordId(wordId));
    }

    // ---- old-client deletes and review ----

    /**
     * Same request, no expectation on the status: for the two endpoints below the status
     * is pinned by its own test, because it was already a 500 before V028 (see there).
     */
    private int statusOf(MockHttpServletRequestBuilder request, String userId) throws Exception {
        return mockMvc.perform(request.header("X-User-Id", userId)).andReturn().getResponse().getStatus();
    }

    @Test
    void oldClientDeletes_StillTakeEffect_WhenMeaningsAndAttachedSentencesExist() throws Exception {
        String userId = user();
        JsonNode created = createShippedWord(userId, "delay", "gecikme, ertelemek", "2026-08-20");
        long wordId = created.get("id").asLong();
        long delayMeaning = created.get("meanings").get(0).get("id").asLong();
        long attached = addSentenceWithMeaning(userId, wordId, "The train was delayed.", "Tren gecikti.", delayMeaning, 200)
                .get("sentences").get(0).get("id").asLong();
        addShippedSentence(userId, wordId, "Sorry for the delay.", "Gecikme için üzgünüm.", 200);

        // DELETE /api/words/{wordId}/sentences/{sentenceId}: an attached sentence goes, its meaning stays.
        int sentenceDeleteStatus = statusOf(delete("/api/words/" + wordId + "/sentences/" + attached), userId);
        assertTrue(sentenceDeleteStatus < 400 || sentenceDeleteStatus >= 500,
                "the old request shape is not rejected as a client error: " + sentenceDeleteStatus);
        assertTrue(sentenceRepository.findById(attached).isEmpty(), "the sentence is gone");
        assertEquals(1, sentenceRepository.findByWordId(wordId).size(), "the other sentence stays");
        assertEquals(2, meaningRepository.countByWordId(wordId), "deleting a sentence never deletes a meaning");
        JsonNode afterSentenceDelete = getJson("/api/words/" + wordId, userId, 200);
        assertShippedWordKeys(afterSentenceDelete);
        assertEquals(1, afterSentenceDelete.get("sentences").size());
        assertEquals(2, afterSentenceDelete.get("meanings").size());

        // DELETE /api/words/{id}: the word and everything under it go, meanings and attached sentences included.
        addSentenceWithMeaning(userId, wordId, "The train was delayed.", "Tren gecikti.", delayMeaning, 200);
        deleteJson("/api/words/" + wordId, userId, 200);
        assertTrue(wordRepository.findById(wordId).isEmpty());
        assertEquals(0, meaningRepository.countByWordId(wordId), "meanings go with the word");
        assertTrue(sentenceRepository.findByWordId(wordId).isEmpty(), "sentences go with the word");
        assertEquals(0, getJson("/api/words", userId, 200).size());
        getJson("/api/words/" + wordId, userId, 404);
    }

    @Test
    void oldClientDeleteSentence_Returns200WithTheWord() throws Exception {
        // v1.2.0 accepts 200, 204 or 404 here and throws on anything else. Pre-V028 this
        // endpoint already answered 500 after deleting the row (the word comes back as a
        // lazy Hibernate proxy and Jackson trips on hibernateLazyInitializer), so a failure
        // here is inherited, not introduced -- but it is a shipped-client endpoint.
        String userId = user();
        long wordId = createShippedWord(userId, "delay", "gecikme, ertelemek", "2026-08-20").get("id").asLong();
        long sentenceId = addShippedSentence(userId, wordId, "The train was delayed.", "Tren gecikti.", 200)
                .get("sentences").get(0).get("id").asLong();

        JsonNode word = deleteJson("/api/words/" + wordId + "/sentences/" + sentenceId, userId, 200);

        assertShippedWordKeys(word);
        assertEquals(0, word.get("sentences").size());
        assertEquals(2, word.get("meanings").size());
    }

    @Test
    void oldClientSubmitReview_RecordsTheReview_AndKeepsTheMeanings() throws Exception {
        String userId = user();
        JsonNode created = createShippedWord(userId, "delay", "gecikme, ertelemek", "2026-08-20");
        long wordId = created.get("id").asLong();

        int status = statusOf(post("/api/srs/submit-review").contentType(MediaType.APPLICATION_JSON)
                .content("{\"wordId\":" + wordId + ",\"quality\":4}"), userId);
        assertTrue(status < 400 || status >= 500, "the old request shape is not rejected as a client error: " + status);

        Word stored = wordRepository.findById(wordId).orElseThrow();
        assertEquals(1, stored.getReviewCount(), "the review is recorded");
        assertEquals(LocalDate.now(), stored.getLastReviewDate());
        assertEquals(2, meaningRepository.countByWordId(wordId), "reviewing does not touch the meanings");
        JsonNode reread = getJson("/api/words/" + wordId, userId, 200);
        assertShippedWordKeys(reread);
        assertEquals(1, reread.get("reviewCount").asInt());
        assertEquals(List.of("gecikme", "ertelemek"), translationsOf(reread));
        assertEquals(1, getJson("/api/srs/stats", userId, 200).get("reviewedWords").asInt());
    }

    @Test
    void oldClientSubmitReview_Returns200WithTheWord() throws Exception {
        // v1.2.0 parses the Word out of a 200 and throws on anything else. Pre-V028 this
        // endpoint already answered 500 after committing the review (the returned word's
        // lazy sentences are serialised with no session open), so a failure here is
        // inherited, not introduced -- but it is the review screen's endpoint.
        String userId = user();
        long wordId = createShippedWord(userId, "delay", "gecikme, ertelemek", "2026-08-20").get("id").asLong();

        JsonNode reviewed = postJson("/api/srs/submit-review", userId,
                "{\"wordId\":" + wordId + ",\"quality\":4}", 200);

        assertShippedWordKeys(reviewed);
        assertEquals(1, reviewed.get("reviewCount").asInt());
        assertEquals(List.of("gecikme", "ertelemek"), translationsOf(reviewed));
    }

    // ---- language profiles ----

    @Test
    void freshUser_GetsTheDefaultEnglishProfile_OnTheFirstListCall() throws Exception {
        String userId = user();
        assertTrue(profileRepository.findByUserId(Long.parseLong(userId)).isEmpty(), "no backfill row for this user");

        JsonNode profiles = getJson("/api/language-profiles", userId, 200);

        assertEquals(1, profiles.size(), "never an empty list");
        JsonNode profile = profiles.get(0);
        assertProfileShape(profile);
        assertEquals("Turkish", profile.get("sourceLanguage").asText());
        assertEquals("English", profile.get("targetLanguage").asText());
        assertEquals("B1", profile.get("level").asText());
        assertTrue(profile.get("learningGoal").isNull());
        assertTrue(profile.get("isActive").asBoolean());
        assertFalse(profile.get("createdAt").isNull());

        List<LanguageProfile> rows = profileRepository.findByUserId(Long.parseLong(userId));
        assertEquals(1, rows.size(), "created once");
        assertEquals(profile.get("id").asLong(), rows.get(0).getId());

        // Listing again does not create a second one.
        assertEquals(1, getJson("/api/language-profiles", userId, 200).size());
        assertEquals(1, profileRepository.findByUserId(Long.parseLong(userId)).size());
    }

    @Test
    void freshUser_WhoseFirstRequestIsTheWordList_GetsAnEmptyListAndTheDefaultProfile() throws Exception {
        // The guard the spec asks for: a user with no profile row must not 500 on a read.
        String userId = user();

        JsonNode words = getJson("/api/words", userId, 200);

        assertEquals(0, words.size());
        List<LanguageProfile> rows = profileRepository.findByUserId(Long.parseLong(userId));
        assertEquals(1, rows.size());
        assertEquals("English", rows.get(0).getTargetLanguage());
        assertTrue(rows.get(0).isActive());

        // A word created right after lands in that profile.
        JsonNode created = createShippedWord(userId, "delay", "gecikme", "2026-08-20");
        assertEquals(rows.get(0).getId(), created.get("languageProfileId").asLong());
        assertEquals(1, profileRepository.findByUserId(Long.parseLong(userId)).size(), "still one profile");
    }

    @Test
    void createProfile_DuplicateTargetIs409_AndDoesNotAddARow() throws Exception {
        String userId = user();
        getJson("/api/language-profiles", userId, 200); // default English exists now

        JsonNode conflict = createProfile(userId, "English", 409);
        assertNotNull(conflict);
        assertTrue(conflict.has("error"));
        assertEquals(1, profileRepository.findByUserId(Long.parseLong(userId)).size());

        // Spelling does not make it a different language.
        createProfile(userId, "english", 409);
        assertEquals(1, profileRepository.findByUserId(Long.parseLong(userId)).size());

        // A different target is fine and comes back inactive, with the documented shape.
        JsonNode german = createProfile(userId, "German", 201);
        assertProfileShape(german);
        assertEquals("German", german.get("targetLanguage").asText());
        assertFalse(german.get("isActive").asBoolean(), "creating a profile does not switch to it");
        assertEquals("B1", german.get("level").asText(), "level defaults when omitted");
        assertEquals(2, profileRepository.findByUserId(Long.parseLong(userId)).size());
        assertEquals(1, countActiveProfiles(userId));

        // And the same target again is a conflict again.
        createProfile(userId, "German", 409);
        assertEquals(2, profileRepository.findByUserId(Long.parseLong(userId)).size());

        // Another user may have their own German profile; the key is per user.
        createProfile(user(), "German", 201);
    }

    @Test
    void activate_FlipsExactlyOneProfile_AndOnlyForTheCaller() throws Exception {
        String userId = user();
        long english = getJson("/api/language-profiles", userId, 200).get(0).get("id").asLong();
        long german = createProfile(userId, "German", 201).get("id").asLong();
        long french = createProfile(userId, "French", 201).get("id").asLong();
        assertEquals(english, activeProfileId(userId));

        JsonNode activated = postJson("/api/language-profiles/" + german + "/activate", userId, "", 200);
        assertProfileShape(activated);
        assertEquals(german, activated.get("id").asLong());
        assertTrue(activated.get("isActive").asBoolean());

        assertEquals(german, activeProfileId(userId));
        assertEquals(1, countActiveProfiles(userId), "exactly one active per user");
        JsonNode list = getJson("/api/language-profiles", userId, 200);
        assertEquals(3, list.size());
        for (JsonNode profile : list) {
            assertProfileShape(profile);
            assertEquals(profile.get("id").asLong() == german, profile.get("isActive").asBoolean(),
                    "only the activated profile is active: " + profile);
        }

        // Activating the active one changes nothing.
        postJson("/api/language-profiles/" + german + "/activate", userId, "", 200);
        assertEquals(german, activeProfileId(userId));
        assertEquals(1, countActiveProfiles(userId));

        // Flip again, to the third one, then back to English.
        postJson("/api/language-profiles/" + french + "/activate", userId, "", 200);
        assertEquals(french, activeProfileId(userId));
        assertEquals(1, countActiveProfiles(userId));
        postJson("/api/language-profiles/" + english + "/activate", userId, "", 200);
        assertEquals(english, activeProfileId(userId));
        assertEquals(1, countActiveProfiles(userId));

        // Another user cannot activate this user's profile, and their own active one stays put.
        String otherUser = user();
        long otherEnglish = getJson("/api/language-profiles", otherUser, 200).get(0).get("id").asLong();
        postJson("/api/language-profiles/" + german + "/activate", otherUser, "", 404);
        assertEquals(otherEnglish, activeProfileId(otherUser));
        assertEquals(english, activeProfileId(userId));
        assertEquals(1, countActiveProfiles(userId));

        // Nor edit it; and an unknown id is 404 too.
        putJson("/api/language-profiles/" + german, otherUser, "{\"level\":\"C2\"}", 404);
        postJson("/api/language-profiles/987654321/activate", userId, "", 404);
        assertEquals("B1", profileRepository.findById(german).orElseThrow().getLevel());
    }

    @Test
    void updateProfile_ChangesLevelAndGoal_AndTheListShowsIt() throws Exception {
        String userId = user();
        long english = getJson("/api/language-profiles", userId, 200).get(0).get("id").asLong();

        JsonNode updated = putJson("/api/language-profiles/" + english, userId,
                "{\"level\":\"B2\",\"learningGoal\":\"Travel\"}", 200);
        assertProfileShape(updated);
        assertEquals("B2", updated.get("level").asText());
        assertEquals("Travel", updated.get("learningGoal").asText());
        assertTrue(updated.get("isActive").asBoolean(), "editing does not touch the active flag");

        JsonNode listed = getJson("/api/language-profiles", userId, 200).get(0);
        assertEquals("B2", listed.get("level").asText());
        assertEquals("Travel", listed.get("learningGoal").asText());
    }

    // ---- word list scoping ----

    @Test
    void wordList_WithoutAProfileParameter_IsTheActiveProfilesWords() throws Exception {
        String userId = user();
        long englishWord = createShippedWord(userId, "delay", "gecikme", "2026-08-19").get("id").asLong();
        long english = activeProfileId(userId);
        long german = createProfile(userId, "German", 201).get("id").asLong();

        // Still English: the German profile exists but is not active, so nothing changes.
        JsonNode beforeSwitch = getJson("/api/words", userId, 200);
        assertEquals(1, beforeSwitch.size());
        assertEquals(englishWord, beforeSwitch.get(0).get("id").asLong());

        postJson("/api/language-profiles/" + german + "/activate", userId, "", 200);
        JsonNode germanCreated = createShippedWord(userId, "Verspätung", "gecikme", "2026-08-20");
        long germanWord = germanCreated.get("id").asLong();
        assertEquals(german, germanCreated.get("languageProfileId").asLong(), "a new word joins the active profile");

        // Every list the shipped client calls, with no parameter, now shows only German.
        JsonNode list = getJson("/api/words", userId, 200);
        assertEquals(1, list.size());
        assertEquals(germanWord, list.get(0).get("id").asLong());
        assertShippedWordKeys(list.get(0));

        JsonNode paged = getJson("/api/words/paged", userId, 200);
        assertEquals(1, paged.get("content").size());
        assertEquals(germanWord, paged.get("content").get(0).get("id").asLong());
        assertEquals(1, paged.get("totalElements").asInt());

        assertEquals(1, getJson("/api/words/date/2026-08-20", userId, 200).size());
        assertEquals(0, getJson("/api/words/date/2026-08-19", userId, 200).size(),
                "the English word's date shows nothing while German is active");

        JsonNode dates = getJson("/api/words/dates", userId, 200);
        assertEquals(1, dates.size());
        assertEquals("2026-08-20", dates.get(0).asText());

        JsonNode range = getJson("/api/words/range?startDate=2026-08-01&endDate=2026-08-31", userId, 200);
        assertEquals(1, range.size());
        assertEquals(germanWord, range.get(0).get("id").asLong());

        // SRS counts are of the same set. Make both words due first.
        for (long id : new long[] { englishWord, germanWord }) {
            Word stored = wordRepository.findById(id).orElseThrow();
            stored.setNextReviewDate(LocalDate.now().minusDays(1));
            wordRepository.save(stored);
        }
        JsonNode stats = getJson("/api/srs/stats", userId, 200);
        assertEquals(1, stats.get("dueToday").asInt());
        assertEquals(1, stats.get("totalWords").asInt());
        assertEquals(0, stats.get("reviewedWords").asInt());

        // The explicit parameter is additive: it reaches the other profile without switching.
        JsonNode explicit = getJson("/api/words?languageProfileId=" + english, userId, 200);
        assertEquals(1, explicit.size());
        assertEquals(englishWord, explicit.get(0).get("id").asLong());
        assertEquals(german, activeProfileId(userId), "reading with a parameter does not activate");
        // ...but only to the caller's own profiles.
        long someoneElses = getJson("/api/language-profiles", user(), 200).get(0).get("id").asLong();
        getJson("/api/words?languageProfileId=" + someoneElses, userId, 404);

        // Switch back: the English word returns, the German one disappears.
        postJson("/api/language-profiles/" + english + "/activate", userId, "", 200);
        JsonNode afterSwitchBack = getJson("/api/words", userId, 200);
        assertEquals(1, afterSwitchBack.size());
        assertEquals(englishWord, afterSwitchBack.get(0).get("id").asLong());
        assertEquals("2026-08-19", getJson("/api/words/dates", userId, 200).get(0).asText());
        assertEquals(1, getJson("/api/srs/stats", userId, 200).get("totalWords").asInt());
        assertEquals(1, getJson("/api/srs/stats", userId, 200).get("dueToday").asInt());

        // Nothing was lost in the switching: both words still exist for the user.
        assertTrue(wordRepository.findById(germanWord).isPresent());
        assertTrue(wordRepository.findById(englishWord).isPresent());
    }
}
