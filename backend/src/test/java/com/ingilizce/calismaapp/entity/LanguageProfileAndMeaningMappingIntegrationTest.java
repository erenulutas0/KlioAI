package com.ingilizce.calismaapp.entity;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ingilizce.calismaapp.repository.LanguageProfileRepository;
import com.ingilizce.calismaapp.repository.SentenceRepository;
import com.ingilizce.calismaapp.repository.WordMeaningRepository;
import com.ingilizce.calismaapp.repository.WordRepository;
import jakarta.persistence.EntityManager;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * The V028 mapping, exercised against the generated H2 schema.
 *
 * <p>Hibernate logs a failed CREATE TABLE under create-drop and carries on, so a context that
 * boots proves nothing about the new tables. This round-trips rows through them, loads a word
 * the way the controllers do (sentences fetch-joined, meanings eager), and serialises it with
 * the real ObjectMapper after detaching -- the situation the word endpoints are in with
 * open-in-view off.
 */
@SpringBootTest
@ActiveProfiles("test")
@Transactional
class LanguageProfileAndMeaningMappingIntegrationTest {

    private static final Long USER_ID = 4242L;

    @Autowired
    private LanguageProfileRepository profileRepository;

    @Autowired
    private WordRepository wordRepository;

    @Autowired
    private WordMeaningRepository meaningRepository;

    @Autowired
    private SentenceRepository sentenceRepository;

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
    private EntityManager entityManager;

    @Test
    void wordWithMeaningsRoundTripsAndSerialisesWithPlainIds() throws Exception {
        LanguageProfile profile = profileRepository.save(LanguageProfile.defaultEnglishProfile(USER_ID));

        Word word = new Word("run", "koşmak, çalıştırmak", LocalDate.of(2026, 8, 1));
        word.setUserId(USER_ID);
        word.setLanguageProfile(profile);
        word.setOrigin(WordOrigin.MANUAL);
        WordMeaning first = new WordMeaning(null, "koşmak", "to move fast on foot", 0);
        WordMeaning second = new WordMeaning(null, "çalıştırmak", null, 1);
        word.addMeaning(first);
        word.addMeaning(second);

        Sentence assigned = new Sentence("I run every morning.", "Her sabah koşarım.", "easy", null);
        assigned.setMeaning(first);
        word.addSentence(assigned);
        word.addSentence(new Sentence("Run the script.", "Betiği çalıştır.", "easy", null));

        Long wordId = wordRepository.save(word).getId();
        entityManager.flush();
        entityManager.clear();

        Word loaded = wordRepository.findByIdAndUserIdWithSentences(wordId, USER_ID).orElseThrow();
        assertEquals(profile.getId(), loaded.getLanguageProfileId());
        assertEquals(WordOrigin.MANUAL, loaded.getOrigin());
        assertEquals(List.of("koşmak", "çalıştırmak"),
                loaded.getMeanings().stream().map(WordMeaning::getTranslation).toList());
        assertEquals(2, loaded.getSentences().size());

        // Detach so any lazy association that serialisation touches would throw.
        entityManager.detach(loaded);
        JsonNode json = objectMapper.readTree(objectMapper.writeValueAsString(loaded));

        assertEquals(profile.getId().longValue(), json.get("languageProfileId").asLong());
        assertEquals("manual", json.get("origin").asText());
        assertEquals("koşmak, çalıştırmak", json.get("turkishMeaning").asText());
        assertFalse(json.has("languageProfile"), "profile must not be nested in the word JSON");

        JsonNode meanings = json.get("meanings");
        assertEquals(2, meanings.size());
        assertEquals("koşmak", meanings.get(0).get("translation").asText());
        assertEquals("to move fast on foot", meanings.get(0).get("definition").asText());
        assertEquals(0, meanings.get(0).get("position").asInt());
        assertTrue(meanings.get(0).has("id"));
        assertFalse(meanings.get(0).has("word"), "meaning must not recurse into its word");

        JsonNode sentences = json.get("sentences");
        assertEquals(2, sentences.size());
        JsonNode assignedJson = sentences.get(0).get("sentence").asText().startsWith("I run")
                ? sentences.get(0) : sentences.get(1);
        JsonNode unassignedJson = assignedJson == sentences.get(0) ? sentences.get(1) : sentences.get(0);
        assertEquals(meanings.get(0).get("id").asLong(), assignedJson.get("meaningId").asLong());
        assertTrue(unassignedJson.get("meaningId").isNull());
        assertFalse(assignedJson.has("meaning"), "sentence must not nest its meaning");
        assertEquals(wordId.longValue(), assignedJson.get("wordId").asLong());
    }

    @Test
    void deletingMeaningLeavesItsSentencesUnassigned() {
        LanguageProfile profile = profileRepository.save(LanguageProfile.defaultEnglishProfile(USER_ID));

        Word word = new Word("bank", "banka, kıyı", LocalDate.of(2026, 8, 1));
        word.setUserId(USER_ID);
        word.setLanguageProfile(profile);
        WordMeaning bank = new WordMeaning(null, "banka", null, 0);
        WordMeaning shore = new WordMeaning(null, "kıyı", null, 1);
        word.addMeaning(bank);
        word.addMeaning(shore);
        Sentence onShore = new Sentence("We sat on the river bank.", "Nehir kıyısında oturduk.", "easy", null);
        onShore.setMeaning(shore);
        word.addSentence(onShore);
        Long wordId = wordRepository.save(word).getId();
        entityManager.flush();
        entityManager.clear();

        Word loaded = wordRepository.findByIdAndUserIdWithSentences(wordId, USER_ID).orElseThrow();
        WordMeaning toDelete = loaded.getMeanings().get(1);
        Long deletedId = toDelete.getId();
        assertEquals(1, sentenceRepository.findByMeaningId(deletedId).size());

        sentenceRepository.clearMeaningByMeaningId(deletedId);
        loaded.removeMeaning(toDelete);
        entityManager.flush();
        entityManager.clear();

        assertTrue(meaningRepository.findById(deletedId).isEmpty());
        assertEquals(1, meaningRepository.countByWordId(wordId));
        assertEquals(0, meaningRepository.findMaxPositionByWordId(wordId));
        Sentence survivor = sentenceRepository.findByWordId(wordId).get(0);
        assertNull(survivor.getMeaningId(), "sentence is kept and becomes unassigned");
    }

    @Test
    void profileRepositoryFindsActiveAndScopesWords() {
        LanguageProfile english = profileRepository.save(LanguageProfile.defaultEnglishProfile(USER_ID));
        LanguageProfile german = profileRepository.save(
                new LanguageProfile(USER_ID, "Turkish", "German", "A1", "travel", false));

        Optional<LanguageProfile> active = profileRepository.findByUserIdAndIsActiveTrue(USER_ID);
        assertTrue(active.isPresent());
        assertEquals(english.getId(), active.get().getId());
        assertEquals("B1", active.get().getLevel());
        assertNotNull(active.get().getCreatedAt());
        assertTrue(profileRepository.findByUserIdAndTargetLanguage(USER_ID, "German").isPresent());
        assertTrue(profileRepository.existsByUserIdAndTargetLanguage(USER_ID, "English"));
        assertEquals(2, profileRepository.findByUserId(USER_ID).size());

        Word englishWord = new Word("house", "ev", LocalDate.of(2026, 8, 1));
        englishWord.setUserId(USER_ID);
        englishWord.setLanguageProfile(english);
        englishWord.setNextReviewDate(LocalDate.of(2026, 8, 2));
        wordRepository.save(englishWord);
        Word germanWord = new Word("Haus", "ev", LocalDate.of(2026, 8, 1));
        germanWord.setUserId(USER_ID);
        germanWord.setLanguageProfile(german);
        germanWord.setNextReviewDate(LocalDate.of(2026, 8, 2));
        wordRepository.save(germanWord);
        entityManager.flush();
        entityManager.clear();

        assertEquals(2, wordRepository.findByUserId(USER_ID).size());
        assertEquals(1, wordRepository.findByUserIdAndLanguageProfileId(USER_ID, english.getId()).size());
        assertEquals(1, wordRepository.countByUserIdAndLanguageProfileId(USER_ID, german.getId()));
        assertEquals(1, wordRepository.findByUserIdAndLanguageProfileIdAndNextReviewDateLessThanEqual(
                USER_ID, english.getId(), LocalDate.of(2026, 8, 10)).size());
        assertEquals(1, wordRepository.countByUserIdAndLanguageProfileIdAndNextReviewDateLessThanEqual(
                USER_ID, english.getId(), LocalDate.of(2026, 8, 10)));
        assertEquals(0, wordRepository.findByUserIdAndLanguageProfileIdAndNextReviewDateLessThanEqual(
                USER_ID, english.getId(), LocalDate.of(2026, 8, 1)).size());
        assertEquals(List.of(LocalDate.of(2026, 8, 1)),
                wordRepository.findDistinctDatesByUserIdAndLanguageProfileId(USER_ID, german.getId()));
        assertTrue(wordRepository.findByUserIdAndLanguageProfileIsNull(USER_ID).isEmpty());

        // Activation: clear first, then flag, so exactly one is active at the end.
        assertEquals(1, profileRepository.deactivateAllByUserId(USER_ID));
        entityManager.clear();
        LanguageProfile target = profileRepository.findById(german.getId()).orElseThrow();
        target.setActive(true);
        profileRepository.save(target);
        entityManager.flush();
        entityManager.clear();
        assertEquals(german.getId(), profileRepository.findByUserIdAndIsActiveTrue(USER_ID).orElseThrow().getId());
    }

    @Test
    void profileSerialisesIsActiveUnderThatName() throws Exception {
        LanguageProfile profile = new LanguageProfile(USER_ID, "Turkish", "English", "B2", "exam", true);
        JsonNode json = objectMapper.readTree(objectMapper.writeValueAsString(profile));
        assertTrue(json.get("isActive").asBoolean());
        assertFalse(json.has("active"));
        assertEquals("B2", json.get("level").asText());
        assertEquals("exam", json.get("learningGoal").asText());
    }
}
