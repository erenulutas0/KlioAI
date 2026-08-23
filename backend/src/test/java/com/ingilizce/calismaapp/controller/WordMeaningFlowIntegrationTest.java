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
import com.ingilizce.calismaapp.service.SRSService;
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

import java.time.LocalDate;
import java.util.List;
import java.util.concurrent.atomic.AtomicLong;

import static org.hamcrest.Matchers.hasSize;
import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * The V028 word flows end to end: real controllers, services and repositories on H2, only
 * Redis mocked. The unit tests pin each rule; this proves the rules compose -- in particular
 * that a shipped-client request (no meanings, no profile, no meaningId) still works and
 * comes back with the new keys, and that deleting a meaning really leaves its sentences in
 * the database as unassigned.
 *
 * <p>Not {@code @Transactional}: the delete path depends on Hibernate's flush ordering
 * (sentence updates before the meaning delete), which a rolled-back test transaction would
 * not exercise. Each test uses its own user id instead.
 */
@SpringBootTest
@AutoConfigureMockMvc
@TestPropertySource(properties = {
        "GROQ_API_KEY=dummy-key",
        "spring.datasource.url=jdbc:h2:mem:meaningflowdb;DB_CLOSE_DELAY=-1;MODE=PostgreSQL",
        "spring.datasource.driver-class-name=org.h2.Driver"
})
class WordMeaningFlowIntegrationTest {

    private static final AtomicLong NEXT_USER = new AtomicLong(9100);

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

    @Autowired
    private SRSService srsService;

    @MockBean
    private RedisTemplate<String, String> redisTemplate;

    private static String user() {
        return Long.toString(NEXT_USER.incrementAndGet());
    }

    private JsonNode postJson(String path, String userId, String body, int expectedStatus) throws Exception {
        MvcResult result = mockMvc.perform(post(path)
                        .header("X-User-Id", userId)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body))
                .andExpect(status().is(expectedStatus))
                .andReturn();
        String content = result.getResponse().getContentAsString();
        return content.isEmpty() ? null : objectMapper.readTree(content);
    }

    @Test
    void shippedClientCreate_GetsAProfileOriginAndMeaningsDerived_AndTheListIsScopedToThatProfile() throws Exception {
        String userId = user();
        assertTrue(profileRepository.findByUserId(Long.parseLong(userId)).isEmpty(), "no backfill row for this user");

        JsonNode created = postJson("/api/words", userId, """
                {"englishWord":"bank","turkishMeaning":"⭐ banka, kıyı","sourceMeaning":"⭐ banka, kıyı",
                 "learnedDate":"2026-08-20","notes":"","difficulty":"easy"}
                """, 200);

        // Old keys, same meaning.
        assertEquals("bank", created.get("englishWord").asText());
        assertEquals("⭐ banka, kıyı", created.get("turkishMeaning").asText());
        assertEquals("⭐ banka, kıyı", created.get("sourceMeaning").asText());
        assertTrue(created.get("sentences").isArray());
        // New keys, additive.
        assertEquals("daily_words", created.get("origin").asText());
        LanguageProfile profile = profileRepository.findByUserIdAndIsActiveTrue(Long.parseLong(userId)).orElseThrow();
        assertEquals(profile.getId(), created.get("languageProfileId").asLong());
        assertEquals("Turkish", profile.getSourceLanguage());
        assertEquals("English", profile.getTargetLanguage());
        JsonNode meanings = created.get("meanings");
        assertEquals(2, meanings.size());
        assertEquals("banka", meanings.get(0).get("translation").asText());
        assertEquals(0, meanings.get(0).get("position").asInt());
        assertEquals("kıyı", meanings.get(1).get("translation").asText());
        assertEquals(1, meanings.get(1).get("position").asInt());
        assertTrue(meanings.get(0).get("definition").isNull());
        assertNotNull(meanings.get(0).get("id"));
        assertNull(meanings.get(0).get("word"), "no nested word in a meaning");

        long wordId = created.get("id").asLong();
        assertEquals(2, meaningRepository.countByWordId(wordId));

        // The default list is the active profile's words.
        mockMvc.perform(get("/api/words").header("X-User-Id", userId))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].meanings", hasSize(2)));

        // A second profile sees none of them until a word is created under it.
        JsonNode german = postJson("/api/language-profiles", userId,
                "{\"sourceLanguage\":\"Turkish\",\"targetLanguage\":\"German\",\"level\":\"A1\"}", 201);
        assertFalse(german.get("isActive").asBoolean(), "creating a profile does not switch to it");
        mockMvc.perform(get("/api/words").header("X-User-Id", userId).param("languageProfileId", german.get("id").asText()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(0)));

        // Activate it: the default list (and the SRS due list) follow the active profile.
        postJson("/api/language-profiles/" + german.get("id").asLong() + "/activate", userId, "", 200);
        mockMvc.perform(get("/api/words").header("X-User-Id", userId))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(0)));
        assertTrue(srsService.getWordsForReview(Long.parseLong(userId)).isEmpty());
        assertEquals(0L, srsService.getStats(Long.parseLong(userId)).get("totalWords"));

        List<LanguageProfile> profiles = profileRepository.findByUserId(Long.parseLong(userId));
        assertEquals(1, profiles.stream().filter(LanguageProfile::isActive).count(), "exactly one active");

        postJson("/api/language-profiles/" + profile.getId() + "/activate", userId, "", 200);
        // A fresh word is scheduled for tomorrow; pull it back so it is due.
        Word stored = wordRepository.findById(wordId).orElseThrow();
        stored.setNextReviewDate(LocalDate.now().minusDays(1));
        wordRepository.save(stored);
        assertEquals(1, srsService.getWordsForReview(Long.parseLong(userId)).size(),
                "the due list is scoped like the word list");
        assertEquals(1L, srsService.getStats(Long.parseLong(userId)).get("totalWords"));
        assertEquals(1, srsService.getStats(Long.parseLong(userId)).get("dueToday"));

        // Same target language twice is a conflict, not a second row.
        postJson("/api/language-profiles", userId,
                "{\"sourceLanguage\":\"Turkish\",\"targetLanguage\":\"German\"}", 409);
    }

    @Test
    void sentencesAttachToMeanings_AndDeletingAMeaningLeavesThemUnassigned() throws Exception {
        String userId = user();
        JsonNode created = postJson("/api/words", userId, """
                {"englishWord":"bank","turkishMeaning":"banka, kıyı","learnedDate":"2026-08-20"}
                """, 200);
        long wordId = created.get("id").asLong();
        long bankMeaning = created.get("meanings").get(0).get("id").asLong();
        long shoreMeaning = created.get("meanings").get(1).get("id").asLong();

        // Shipped-client shape: no meaningId -> unassigned.
        JsonNode afterFirst = postJson("/api/words/" + wordId + "/sentences", userId,
                "{\"sentence\":\"I went to the bank.\",\"translation\":\"Bankaya gittim.\",\"difficulty\":\"easy\"}", 200);
        assertTrue(afterFirst.get("sentences").get(0).get("meaningId").isNull());
        assertEquals(wordId, afterFirst.get("sentences").get(0).get("wordId").asLong());

        // New shape: attached.
        JsonNode afterSecond = postJson("/api/words/" + wordId + "/sentences", userId,
                "{\"sentence\":\"We sat on the river bank.\",\"translation\":\"Nehir kıyısında oturduk.\",\"meaningId\":"
                        + shoreMeaning + "}", 200);
        JsonNode attached = afterSecond.get("sentences").get(1);
        assertEquals(shoreMeaning, attached.get("meaningId").asLong());

        // A meaning of some other word is refused.
        postJson("/api/words/" + wordId + "/sentences", userId,
                "{\"sentence\":\"Nope.\",\"translation\":\"Hayır.\",\"meaningId\":999999}", 400);

        // Edit the meaning: the legacy string follows.
        mockMvc.perform(put("/api/words/" + wordId + "/meanings/" + bankMeaning)
                        .header("X-User-Id", userId)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"definition\":\"a financial institution\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.meanings[0].definition").value("a financial institution"))
                .andExpect(jsonPath("$.turkishMeaning").value("banka, kıyı"));

        // Delete the meaning the second sentence hangs on.
        mockMvc.perform(delete("/api/words/" + wordId + "/meanings/" + shoreMeaning).header("X-User-Id", userId))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.meanings", hasSize(1)))
                .andExpect(jsonPath("$.turkishMeaning").value("banka"))
                .andExpect(jsonPath("$.sentences", hasSize(2)))
                .andExpect(jsonPath("$.sentences[1].meaningId").value(org.hamcrest.Matchers.nullValue()));

        // Through the repositories, after commit: meaning gone, both sentences there, unassigned.
        assertTrue(meaningRepository.findById(shoreMeaning).isEmpty());
        List<Sentence> stored = sentenceRepository.findByWordId(wordId);
        assertEquals(2, stored.size());
        for (Sentence sentence : stored) {
            assertNull(sentence.getMeaning());
        }
        Word reloaded = wordRepository.findById(wordId).orElseThrow();
        assertEquals("banka", reloaded.getTurkishMeaning());

        // The last meaning stays.
        mockMvc.perform(delete("/api/words/" + wordId + "/meanings/" + bankMeaning).header("X-User-Id", userId))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("A word must keep at least one meaning"));
        assertEquals(1, meaningRepository.countByWordId(wordId));

        // Add one back: 201, appended, string resynced.
        mockMvc.perform(post("/api/words/" + wordId + "/meanings")
                        .header("X-User-Id", userId)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"translation\":\"kıyı\",\"definition\":\"the land beside a river\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.meanings", hasSize(2)))
                .andExpect(jsonPath("$.meanings[1].translation").value("kıyı"))
                .andExpect(jsonPath("$.meanings[1].position").value(1))
                .andExpect(jsonPath("$.turkishMeaning").value("banka, kıyı"));

        // Another user cannot touch it.
        mockMvc.perform(post("/api/words/" + wordId + "/meanings")
                        .header("X-User-Id", user())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"translation\":\"x\"}"))
                .andExpect(status().isNotFound());
    }

    @Test
    void createWithExplicitMeanings_StoresThem_AndFillsTheLegacyString() throws Exception {
        String userId = user();
        JsonNode created = postJson("/api/words", userId, """
                {"englishWord":"run","learnedDate":"2026-08-20",
                 "meanings":[{"translation":"koşmak","definition":"move fast on foot"},{"translation":"çalıştırmak"}]}
                """, 200);

        assertEquals("koşmak, çalıştırmak", created.get("turkishMeaning").asText());
        assertEquals("manual", created.get("origin").asText());
        assertEquals(2, created.get("meanings").size());
        assertEquals("move fast on foot", created.get("meanings").get(0).get("definition").asText());
        assertEquals(2, meaningRepository.countByWordId(created.get("id").asLong()));
        assertEquals(LocalDate.of(2026, 8, 20).toString(), created.get("learnedDate").asText());
    }
}
