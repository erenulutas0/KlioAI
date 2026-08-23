package com.ingilizce.calismaapp.controller;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ingilizce.calismaapp.entity.LanguageProfile;
import com.ingilizce.calismaapp.entity.Sentence;
import com.ingilizce.calismaapp.entity.Word;
import com.ingilizce.calismaapp.entity.WordMeaning;
import com.ingilizce.calismaapp.repository.LanguageProfileRepository;
import com.ingilizce.calismaapp.repository.SentenceRepository;
import com.ingilizce.calismaapp.repository.UserRepository;
import com.ingilizce.calismaapp.repository.WordMeaningRepository;
import com.ingilizce.calismaapp.repository.WordRepository;
import com.ingilizce.calismaapp.service.LanguageProfileService;
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
import org.springframework.transaction.support.TransactionTemplate;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * The findings of the V028 review that changed main code, each pinned against the real
 * controllers, services and repositories on H2 with only Redis mocked:
 *
 * <ul>
 *   <li>POST /api/words with an {@code id} in the body must not merge over that row;</li>
 *   <li>PUT /api/words/{id} must keep {@code turkishMeaning} and the meanings together;</li>
 *   <li>a word with no profile must become visible again instead of vanishing for good;</li>
 *   <li>two first reads of a brand-new user must not race each other into an error;</li>
 *   <li>registration gives the user their default profile;</li>
 *   <li>review-words, submit-review and delete-sentence answer 200, not a serialisation 500.</li>
 * </ul>
 *
 * <p>Not {@code @Transactional}: the point is what is committed. Each test uses its own
 * user id instead of cleaning up.
 */
@SpringBootTest
@AutoConfigureMockMvc
@TestPropertySource(properties = {
        "GROQ_API_KEY=dummy-key",
        "spring.datasource.url=jdbc:h2:mem:v028reviewfixesdb;DB_CLOSE_DELAY=-1;MODE=PostgreSQL",
        "spring.datasource.driver-class-name=org.h2.Driver"
})
class V028ReviewFixesIntegrationTest {

    private static final AtomicLong NEXT_USER = new AtomicLong(12500);

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
    private LanguageProfileRepository profileRepository;

    @Autowired
    private LanguageProfileService languageProfileService;

    @Autowired
    private WordRepository wordRepository;

    @Autowired
    private WordMeaningRepository meaningRepository;

    @Autowired
    private SentenceRepository sentenceRepository;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private TransactionTemplate transactionTemplate;

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

    /** Exactly what v1.2.0's {@code ApiService.createWord} sends. */
    private JsonNode createShippedWord(String userId, String english, String turkish) throws Exception {
        return postJson("/api/words", userId, """
                {"englishWord":"%s","turkishMeaning":"%s","sourceMeaning":"%s","learnedDate":"2026-08-20","notes":"","difficulty":"easy"}
                """.formatted(english, turkish, turkish), 200);
    }

    private JsonNode addSentence(String userId, long wordId, String sentence, Long meaningId) throws Exception {
        String meaning = meaningId == null ? "" : ",\"meaningId\":" + meaningId;
        return postJson("/api/words/" + wordId + "/sentences", userId, """
                {"sentence":"%s","translation":"%s","difficulty":"easy"%s}
                """.formatted(sentence, sentence, meaning), 200);
    }

    private static List<String> translationsOf(JsonNode word) {
        List<String> translations = new ArrayList<>();
        for (JsonNode meaning : word.get("meanings")) {
            translations.add(meaning.get("translation").asText());
        }
        return translations;
    }

    private static long meaningId(JsonNode word, String translation) {
        for (JsonNode meaning : word.get("meanings")) {
            if (translation.equals(meaning.get("translation").asText())) {
                return meaning.get("id").asLong();
            }
        }
        throw new AssertionError("no meaning " + translation + " in " + word);
    }

    private static List<Long> idsOf(JsonNode word) {
        List<Long> ids = new ArrayList<>();
        for (JsonNode meaning : word.get("meanings")) {
            ids.add(meaning.get("id").asLong());
        }
        return ids;
    }

    // ---- POST /api/words with an id in the body ----

    @Test
    void postWord_WithAnotherUsersWordId_CreatesTheCallersOwnWord_AndLeavesTheVictimsUntouched() throws Exception {
        String victim = user();
        String attacker = user();
        JsonNode victimWord = createShippedWord(victim, "bank", "⭐ banka, kıyı");
        long victimWordId = victimWord.get("id").asLong();
        long victimProfileId = victimWord.get("languageProfileId").asLong();

        JsonNode response = postJson("/api/words", attacker, """
                {"id":%d,"englishWord":"bank","turkishMeaning":"stolen","learnedDate":"2026-08-21","notes":"","difficulty":"easy"}
                """.formatted(victimWordId), 200);

        assertNotEquals(victimWordId, response.get("id").asLong(), "the attacker gets a row of their own");
        assertEquals(Long.parseLong(attacker), response.get("userId").asLong());
        assertEquals(List.of("stolen"), translationsOf(response));

        Word stored = wordRepository.findById(victimWordId).orElseThrow();
        assertEquals(Long.parseLong(victim), stored.getUserId(), "owner unchanged");
        assertEquals("⭐ banka, kıyı", stored.getTurkishMeaning());
        assertEquals("daily_words", stored.getOrigin());
        assertEquals(victimProfileId, stored.getLanguageProfileId());
        assertNotNull(stored.getNextReviewDate(), "the SRS schedule is not reset");
        assertEquals(2, meaningRepository.countByWordId(victimWordId), "no meaning was deleted");

        JsonNode victimList = getJson("/api/words", victim, 200);
        assertEquals(1, victimList.size(), "the victim still sees their word");
        assertEquals(victimWordId, victimList.get(0).get("id").asLong());
    }

    @Test
    void postWord_WithTheOwnersOwnId_IsTheIdempotentCreate_NotAMerge() throws Exception {
        String userId = user();
        JsonNode created = createShippedWord(userId, "run", "koşmak, çalıştırmak");
        long wordId = created.get("id").asLong();

        JsonNode replayed = postJson("/api/words", userId, """
                {"id":%d,"englishWord":"run","turkishMeaning":"wiped","learnedDate":"2026-08-21","notes":"","difficulty":"easy"}
                """.formatted(wordId), 200);

        assertEquals(wordId, replayed.get("id").asLong());
        assertEquals("koşmak, çalıştırmak", replayed.get("turkishMeaning").asText());
        assertEquals(List.of("koşmak", "çalıştırmak"), translationsOf(replayed));
        assertEquals(2, meaningRepository.countByWordId(wordId));
        assertNotNull(wordRepository.findById(wordId).orElseThrow().getLanguageProfileId());
    }

    // ---- PUT /api/words/{id} ----

    @Test
    void putWord_WithANewMeaningString_RebuildsTheMeanings_KeepingSurvivorsAndTheirSentences() throws Exception {
        String userId = user();
        JsonNode created = createShippedWord(userId, "run", "koşmak, çalıştırmak");
        long wordId = created.get("id").asLong();
        long kosmakId = meaningId(created, "koşmak");
        long calistirmakId = meaningId(created, "çalıştırmak");
        addSentence(userId, wordId, "I run every morning.", kosmakId);
        addSentence(userId, wordId, "Run the program.", calistirmakId);

        JsonNode updated = putJson("/api/words/" + wordId, userId, """
                {"englishWord":"run","turkishMeaning":"koşmak, kaçmak","learnedDate":"2026-08-20","notes":"edited"}
                """, 200);

        assertEquals("koşmak, kaçmak", updated.get("turkishMeaning").asText());
        assertEquals(List.of("koşmak", "kaçmak"), translationsOf(updated));
        assertEquals(kosmakId, meaningId(updated, "koşmak"), "a surviving translation keeps its row");
        assertEquals("edited", updated.get("notes").asText());

        List<Sentence> sentences = sentenceRepository.findByWordIdIn(List.of(wordId));
        assertEquals(2, sentences.size(), "no sentence is deleted by a meaning edit");
        for (Sentence sentence : sentences) {
            if (sentence.getSentence().startsWith("I run")) {
                assertEquals(kosmakId, sentence.getMeaningId(), "still attached to the surviving meaning");
            } else {
                assertNull(sentence.getMeaningId(), "unassigned once its meaning is gone");
            }
        }
        assertFalse(meaningRepository.existsById(calistirmakId));

        JsonNode reread = getJson("/api/words/" + wordId, userId, 200);
        assertEquals("koşmak, kaçmak", reread.get("turkishMeaning").asText());
        assertEquals(List.of("koşmak", "kaçmak"), translationsOf(reread));
    }

    @Test
    void putWord_WithTheSameMeaningString_DoesNotTouchTheMeanings() throws Exception {
        String userId = user();
        JsonNode created = createShippedWord(userId, "delay", "gecikme, ertelemek");
        long wordId = created.get("id").asLong();
        putJson("/api/words/" + wordId + "/meanings/" + meaningId(created, "gecikme"), userId,
                "{\"definition\":\"a period of waiting\"}", 200);

        JsonNode updated = putJson("/api/words/" + wordId, userId, """
                {"englishWord":"delay","turkishMeaning":"gecikme, ertelemek","learnedDate":"2026-08-20","notes":"n"}
                """, 200);

        assertEquals(idsOf(created), idsOf(updated), "same rows, same ids");
        assertEquals("a period of waiting", updated.get("meanings").get(0).get("definition").asText());
        assertEquals("gecikme, ertelemek", updated.get("turkishMeaning").asText());
    }

    @Test
    void putWord_WithExplicitMeanings_UsesThem_AndRewritesTheLegacyString() throws Exception {
        String userId = user();
        JsonNode created = createShippedWord(userId, "delay", "⭐ gecikme, ertelemek");
        long wordId = created.get("id").asLong();

        JsonNode updated = putJson("/api/words/" + wordId, userId, """
                {"englishWord":"delay","turkishMeaning":"ignored","learnedDate":"2026-08-20",
                 "meanings":[{"translation":"ertelemek","definition":"to postpone"},{"translation":"gecikme"}]}
                """, 200);

        assertEquals(List.of("ertelemek", "gecikme"), translationsOf(updated));
        assertEquals("to postpone", updated.get("meanings").get(0).get("definition").asText());
        assertEquals("⭐ ertelemek, gecikme", updated.get("turkishMeaning").asText(),
                "the legacy string follows the meanings and keeps its daily-words star");
        assertEquals(2, meaningRepository.countByWordId(wordId));
    }

    @Test
    void putWord_WithABlankMeaningString_KeepsTheMeanings() throws Exception {
        String userId = user();
        JsonNode created = createShippedWord(userId, "delay", "gecikme, ertelemek");
        long wordId = created.get("id").asLong();

        JsonNode updated = putJson("/api/words/" + wordId, userId, """
                {"englishWord":"delay","turkishMeaning":"   ","learnedDate":"2026-08-20"}
                """, 200);

        assertEquals(List.of("gecikme", "ertelemek"), translationsOf(updated));
        assertEquals("gecikme, ertelemek", updated.get("turkishMeaning").asText());
    }

    // ---- words with no profile ----

    @Test
    void wordWithNoProfile_IsAdoptedOnTheNextRead_AndCountsAgain() throws Exception {
        String userId = user();
        long wordId = createShippedWord(userId, "anchor", "çapa").get("id").asLong();
        // What pre-V028 code writes against the V028 schema (the documented rollback path):
        // no profile, no origin, no meaning rows.
        transactionTemplate.executeWithoutResult(status -> {
            Word word = wordRepository.findById(wordId).orElseThrow();
            word.setLanguageProfile(null);
            word.setOrigin(null);
            word.getMeanings().clear();
            wordRepository.save(word);
        });
        assertEquals(0, meaningRepository.countByWordId(wordId));

        JsonNode list = getJson("/api/words", userId, 200);

        assertEquals(1, list.size(), "the word is listed again");
        JsonNode word = list.get(0);
        long profileId = profileRepository.findByUserIdAndIsActiveTrue(Long.parseLong(userId)).orElseThrow().getId();
        assertEquals(profileId, word.get("languageProfileId").asLong());
        assertEquals("manual", word.get("origin").asText());
        assertEquals(List.of("çapa"), translationsOf(word));
        assertEquals(1, getJson("/api/srs/stats", userId, 200).get("totalWords").asInt());
    }

    @Test
    void wordWithNoProfile_GoesToTheEnglishProfile_EvenWhenAnotherOneIsActive() throws Exception {
        String userId = user();
        long wordId = createShippedWord(userId, "anchor", "çapa").get("id").asLong();
        long englishProfileId = profileRepository.findByUserIdAndIsActiveTrue(Long.parseLong(userId)).orElseThrow().getId();
        long germanProfileId = postJson("/api/language-profiles", userId,
                "{\"sourceLanguage\":\"Turkish\",\"targetLanguage\":\"German\"}", 201).get("id").asLong();
        postJson("/api/language-profiles/" + germanProfileId + "/activate", userId, "", 200);
        transactionTemplate.executeWithoutResult(status -> {
            Word word = wordRepository.findById(wordId).orElseThrow();
            word.setLanguageProfile(null);
            wordRepository.save(word);
        });

        assertEquals(0, getJson("/api/words", userId, 200).size(), "not in the German profile");
        assertEquals(englishProfileId, wordRepository.findById(wordId).orElseThrow().getLanguageProfileId());
        assertEquals(1, getJson("/api/words?languageProfileId=" + englishProfileId, userId, 200).size());
    }

    // ---- the first-read race of a brand-new user ----

    @Test
    void concurrentFirstReads_OfANewUser_CreateExactlyOneProfile_AndNeitherFails() throws Exception {
        ExecutorService pool = Executors.newFixedThreadPool(2);
        try {
            for (int round = 0; round < 25; round++) {
                long userId = Long.parseLong(user());
                CountDownLatch go = new CountDownLatch(1);
                List<Future<LanguageProfile>> results = new ArrayList<>();
                for (int t = 0; t < 2; t++) {
                    results.add(pool.submit(() -> {
                        go.await(5, TimeUnit.SECONDS);
                        return languageProfileService.ensureDefaultProfile(userId);
                    }));
                }
                go.countDown();
                for (Future<LanguageProfile> result : results) {
                    LanguageProfile profile = result.get(30, TimeUnit.SECONDS);
                    assertNotNull(profile.getId());
                    assertEquals(userId, profile.getUserId());
                }
                assertEquals(1, profileRepository.findByUserId(userId).size(), "one profile for user " + userId);
            }
        } finally {
            pool.shutdownNow();
        }
    }

    @Test
    void concurrentShippedClientStartup_StatsAndWords_BothSucceed() throws Exception {
        ExecutorService pool = Executors.newFixedThreadPool(2);
        try {
            for (int round = 0; round < 10; round++) {
                String userId = user();
                CountDownLatch go = new CountDownLatch(1);
                Future<Integer> stats = pool.submit(() -> {
                    go.await(5, TimeUnit.SECONDS);
                    return mockMvc.perform(get("/api/srs/stats").header("X-User-Id", userId))
                            .andReturn().getResponse().getStatus();
                });
                Future<Integer> words = pool.submit(() -> {
                    go.await(5, TimeUnit.SECONDS);
                    return mockMvc.perform(get("/api/words").header("X-User-Id", userId))
                            .andReturn().getResponse().getStatus();
                });
                go.countDown();
                assertEquals(200, stats.get(30, TimeUnit.SECONDS), "/srs/stats for user " + userId);
                assertEquals(200, words.get(30, TimeUnit.SECONDS), "/words for user " + userId);
                assertEquals(1, profileRepository.findByUserId(Long.parseLong(userId)).size());
            }
        } finally {
            pool.shutdownNow();
        }
    }

    // ---- the other endpoint that serialised a lazy collection with no session ----

    @Test
    void reviewWords_ReturnsDueWordsWithTheirSentences() throws Exception {
        String userId = user();
        long wordId = createShippedWord(userId, "anchor", "çapa").get("id").asLong();
        addSentence(userId, wordId, "Drop the anchor.", null);
        transactionTemplate.executeWithoutResult(status -> {
            Word word = wordRepository.findById(wordId).orElseThrow();
            word.setNextReviewDate(java.time.LocalDate.now().minusDays(1));
            wordRepository.save(word);
        });

        JsonNode due = getJson("/api/srs/review-words", userId, 200);

        assertEquals(1, due.size());
        assertEquals(wordId, due.get(0).get("id").asLong());
        assertEquals(1, due.get(0).get("sentences").size());
        assertEquals(List.of("çapa"), translationsOf(due.get(0)));
    }

    // ---- registration ----

    @Test
    void register_CreatesTheDefaultProfile_BeforeAnyRead() throws Exception {
        MvcResult result = mockMvc.perform(post("/api/auth/register").contentType(MediaType.APPLICATION_JSON).content("""
                {"email":"v028-fixes-%d@test.com","password":"password123","displayName":"Fixes"}
                """.formatted(NEXT_USER.incrementAndGet())))
                .andExpect(status().isOk())
                .andReturn();
        JsonNode response = objectMapper.readTree(result.getResponse().getContentAsString());
        long userId = response.get("user").get("id").asLong();

        List<LanguageProfile> profiles = profileRepository.findByUserId(userId);
        assertEquals(1, profiles.size());
        assertEquals("English", profiles.get(0).getTargetLanguage());
        assertTrue(profiles.get(0).isActive());
        assertTrue(userRepository.existsById(userId));
    }
}
