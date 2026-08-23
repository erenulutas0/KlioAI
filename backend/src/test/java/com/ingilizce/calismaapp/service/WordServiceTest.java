package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.entity.LanguageProfile;
import com.ingilizce.calismaapp.entity.Word;
import com.ingilizce.calismaapp.entity.WordMeaning;
import com.ingilizce.calismaapp.entity.WordOrigin;
import com.ingilizce.calismaapp.entity.Sentence;
import com.ingilizce.calismaapp.dto.CreateWordRequest;
import com.ingilizce.calismaapp.repository.WordRepository;
import com.ingilizce.calismaapp.repository.SentenceRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
import org.mockito.Spy;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

class WordServiceTest {

    @InjectMocks
    private WordService wordService;

    @Mock
    private WordRepository wordRepository;

    @Mock
    private SentenceRepository sentenceRepository;

    // We mock other dependencies to avoid NPEs during context load if they are
    // autowired
    @Mock
    private ProgressService progressService;

    /// Every read path and every new word goes through the active language profile (V028);
    /// the stub hands back one fixed profile so the tests stay about words.
    @Mock
    private LanguageProfileService languageProfileService;

    private static final Long ACTIVE_PROFILE_ID = 500L;

    /// Real instance, not a mock: the point of the test below is that saveWord actually
    /// puts a schedule on the word, and a mock would happily record the call while leaving
    /// next_review_date null - which is the exact bug being fixed.
    @Spy
    private SRSService srsService = new SRSService();

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
        when(wordRepository.findByUserIdAndEnglishWord(anyLong(), anyString()))
                .thenReturn(Optional.empty());
        when(sentenceRepository.findByWordIdIn(anyList())).thenReturn(List.of());
        LanguageProfile activeProfile = LanguageProfile.defaultEnglishProfile(1L);
        activeProfile.setId(ACTIVE_PROFILE_ID);
        when(languageProfileService.ensureDefaultProfile(anyLong())).thenReturn(activeProfile);
    }

    @Test
    void saveWord_ShouldScheduleTheWordForReview() {
        // A new word used to be persisted with next_review_date null. The due query is
        // "next_review_date <= today", which NULL never satisfies, so the word could not
        // surface for review -- and a word only received a schedule by being reviewed.
        // Production had 18 of 20 words stranded that way before this was fixed.
        Word newWord = new Word();
        newWord.setUserId(100L);
        newWord.setEnglishWord("Serendipity");
        newWord.setTurkishMeaning("Mutlu Tesaduf");
        newWord.setLearnedDate(LocalDate.now());

        ArgumentCaptor<Word> persisted = ArgumentCaptor.forClass(Word.class);
        when(wordRepository.save(any(Word.class))).thenAnswer(inv -> inv.getArgument(0));

        wordService.saveWord(newWord);

        verify(wordRepository).save(persisted.capture());
        Word stored = persisted.getValue();
        assertNotNull(stored.getNextReviewDate(), "a new word must reach the scheduler");
        assertFalse(stored.getNextReviewDate().isBefore(LocalDate.now()),
                "the first review must not be scheduled in the past");
        assertEquals(0, stored.getReviewCount());
        assertEquals(2.5, stored.getEaseFactor());
    }

    @Test
    void saveWord_ShouldNotRescheduleAnExistingWord() {
        // Editing a word must not reset its SM-2 progress back to a fresh interval.
        LocalDate alreadyScheduled = LocalDate.now().plusDays(30);
        Word existing = new Word();
        existing.setId(7L);
        existing.setUserId(100L);
        existing.setEnglishWord("Serendipity");
        existing.setNextReviewDate(alreadyScheduled);
        existing.setReviewCount(4);
        existing.setEaseFactor(2.9);

        when(wordRepository.save(any(Word.class))).thenAnswer(inv -> inv.getArgument(0));

        wordService.saveWord(existing);

        ArgumentCaptor<Word> persisted = ArgumentCaptor.forClass(Word.class);
        verify(wordRepository).save(persisted.capture());
        assertEquals(alreadyScheduled, persisted.getValue().getNextReviewDate());
        assertEquals(4, persisted.getValue().getReviewCount());
        assertEquals(2.9, persisted.getValue().getEaseFactor());
    }

    @Test
    void saveWord_ShouldSaveWord_And_TriggerGamificationAndSocial() {
        // Arrange
        Long userId = 100L;
        Word newWord = new Word();
        newWord.setUserId(userId);
        newWord.setEnglishWord("Serendipity");
        newWord.setTurkishMeaning("Mutlu Tesadüf");
        newWord.setLearnedDate(LocalDate.now());

        Word savedWord = new Word();
        savedWord.setId(1L);
        savedWord.setUserId(userId);
        savedWord.setEnglishWord("Serendipity");

        // Mock Repository Behavior
        when(wordRepository.save(any(Word.class))).thenReturn(savedWord);

        // Act
        Word result = wordService.saveWord(newWord);

        // Assert
        assertNotNull(result);
        assertEquals(1L, result.getId());
        assertEquals("Serendipity", result.getEnglishWord());

        // Verify Repository was called
        verify(wordRepository, times(1)).save(newWord);
    }

    @Test
    void saveWord_ShouldReturnExistingWord_WithoutSideEffects_WhenDuplicate() {
        Long userId = 1L;
        Word existing = new Word();
        existing.setId(5L);
        existing.setUserId(userId);
        existing.setEnglishWord("Apple");

        Word incoming = new Word();
        incoming.setUserId(userId);
        incoming.setEnglishWord("Apple");
        incoming.setLearnedDate(LocalDate.now());

        when(wordRepository.findByUserIdAndEnglishWord(userId, "Apple"))
                .thenReturn(Optional.of(existing));

        Word result = wordService.saveWord(incoming);

        assertEquals(5L, result.getId());
        verify(wordRepository, never()).save(incoming);
        verify(progressService, never()).awardXp(anyLong(), anyInt(), anyString());
    }


    @Test
    void saveWord_WithSomeoneElsesId_CreatesOwnWordInsteadOfOverwriting() {
        // The attack the review caught: POST /api/words with another user's word id used to
        // JPA-merge straight over their row - new owner, meanings wiped by orphanRemoval,
        // profile nulled. An id that does not belong to the caller must never touch the row
        // it names.
        Word incoming = new Word();
        incoming.setId(777L);               // victim's row
        incoming.setUserId(4L);             // attacker's own account
        incoming.setEnglishWord("stolen");
        incoming.setTurkishMeaning("calinti");
        incoming.setLearnedDate(LocalDate.now());

        when(wordRepository.findByIdAndUserId(777L, 4L)).thenReturn(Optional.empty());
        when(wordRepository.findByUserIdAndEnglishWord(4L, "stolen")).thenReturn(Optional.empty());
        when(wordRepository.save(any(Word.class))).thenAnswer(inv -> inv.getArgument(0));

        Word saved = wordService.saveWord(incoming);

        // Created fresh under the caller, not merged over id 777.
        assertNull(saved.getId());
        verify(wordRepository).save(argThat(w -> w.getId() == null && w.getUserId().equals(4L)));
    }

    @Test
    void saveWord_WithOwnId_UpdatesFieldsWithoutWipingMeanings() {
        Word managed = new Word();
        managed.setId(5L);
        managed.setUserId(1L);
        managed.setEnglishWord("delay");
        managed.setTurkishMeaning("gecikme");
        managed.setLearnedDate(LocalDate.now().minusDays(3));
        WordMeaning meaning = new WordMeaning();
        meaning.setTranslation("gecikme");
        managed.addMeaning(meaning);

        Word incoming = new Word();
        incoming.setId(5L);
        incoming.setUserId(1L);
        incoming.setEnglishWord("delay");
        incoming.setTurkishMeaning("gecikme");
        incoming.setNotes("sik kullaniyorum");
        incoming.setLearnedDate(LocalDate.now());
        // The wire payload always carries an (empty) meanings list; under the old merge
        // that list replaced the real one and orphanRemoval deleted every meaning.

        when(wordRepository.findByIdAndUserId(5L, 1L)).thenReturn(Optional.of(managed));
        when(wordRepository.save(any(Word.class))).thenAnswer(inv -> inv.getArgument(0));

        Word saved = wordService.saveWord(incoming);

        assertEquals(5L, saved.getId());
        assertEquals("sik kullaniyorum", saved.getNotes());
        assertEquals(1, saved.getMeanings().size());
        assertEquals("gecikme", saved.getMeanings().get(0).getTranslation());
    }

    @Test
    void saveWord_ShouldThrow_WhenIncomingUserIdIsNull() {
        Word word = new Word();
        word.setUserId(null);
        word.setEnglishWord("FallbackUser");
        word.setLearnedDate(LocalDate.now());

        assertThrows(IllegalArgumentException.class, () -> wordService.saveWord(word));
        verify(wordRepository, never()).save(any(Word.class));
    }

    @Test
    void testGetMethods() {
        // Since V028 "all words" means the active profile's words, not every row of the user.
        when(wordRepository.findByUserIdAndLanguageProfileId(1L, ACTIVE_PROFILE_ID)).thenReturn(new java.util.ArrayList<>());
        assertNotNull(wordService.getAllWords(1L));
        verify(wordRepository).findByUserIdAndLanguageProfileId(1L, ACTIVE_PROFILE_ID);
        verify(wordRepository, never()).findByUserId(anyLong());

        when(wordRepository.findById(1L)).thenReturn(Optional.of(new Word()));
        assertTrue(wordService.getWordById(1L).isPresent());
    }

    @Test
    void getWordsPageAndDateQueries_ShouldDelegateToRepository() {
        LocalDate date = LocalDate.of(2026, 2, 11);
        Page<Word> page = new PageImpl<>(List.of(new Word()));
        when(wordRepository.findByUserIdAndLanguageProfileId(1L, ACTIVE_PROFILE_ID, PageRequest.of(0, 10))).thenReturn(page);
        when(wordRepository.findByUserIdAndLanguageProfileIdAndLearnedDate(1L, ACTIVE_PROFILE_ID, date)).thenReturn(List.of(new Word()));
        when(wordRepository.findByUserIdAndLanguageProfileIdAndDateRange(1L, ACTIVE_PROFILE_ID, date.minusDays(3), date)).thenReturn(List.of(new Word(), new Word()));
        when(wordRepository.findDistinctDatesByUserIdAndLanguageProfileId(1L, ACTIVE_PROFILE_ID)).thenReturn(List.of(date));

        Page<Word> pageResult = wordService.getWordsPage(1L, 0, 10);
        List<Word> byDate = wordService.getWordsByDate(1L, date);
        List<Word> byRange = wordService.getWordsByDateRange(1L, date.minusDays(3), date);
        List<LocalDate> distinct = wordService.getAllDistinctDates(1L);

        assertEquals(1, pageResult.getTotalElements());
        assertEquals(1, byDate.size());
        assertEquals(2, byRange.size());
        assertEquals(1, distinct.size());
    }

    @Test
    void createWord_ShouldMapRequestAndSave_WithDifficulty() {
        CreateWordRequest request = new CreateWordRequest("book", "kitap", "2026-02-10", "medium", "note");
        when(wordRepository.save(any(Word.class))).thenAnswer(invocation -> invocation.getArgument(0));

        Word result = wordService.createWord(request, 7L);

        assertEquals(7L, result.getUserId());
        assertEquals("book", result.getEnglishWord());
        assertEquals("kitap", result.getTurkishMeaning());
        assertEquals(LocalDate.of(2026, 2, 10), result.getLearnedDate());
        assertEquals("note", result.getNotes());
        assertEquals("medium", result.getDifficulty());
    }

    @Test
    void createWord_ShouldLeaveDifficultyNull_WhenNotProvided() {
        CreateWordRequest request = new CreateWordRequest("cat", "kedi", "2026-02-10", null, null);
        when(wordRepository.save(any(Word.class))).thenAnswer(invocation -> invocation.getArgument(0));

        Word result = wordService.createWord(request, 9L);

        assertNull(result.getDifficulty());
    }

    @Test
    void saveWord_ShouldSaveWithoutIdempotencyLookup_WhenEnglishWordNull() {
        Word incoming = new Word();
        incoming.setUserId(2L);
        incoming.setLearnedDate(LocalDate.now());

        Word saved = new Word();
        saved.setId(99L);
        saved.setUserId(2L);

        when(wordRepository.save(any(Word.class))).thenReturn(saved);

        Word result = wordService.saveWord(incoming);

        assertEquals(99L, result.getId());
        verify(wordRepository, never()).findByUserIdAndEnglishWord(anyLong(), anyString());
    }

    @Test
    void saveWord_ShouldSkipSideEffects_WhenUpdatingExistingWord() {
        Word existing = new Word();
        existing.setId(50L);
        existing.setUserId(3L);
        existing.setEnglishWord("existing");
        existing.setLearnedDate(LocalDate.now());

        // The update path now proves ownership before touching the row; a save with an id
        // only proceeds when findByIdAndUserId finds it under the caller.
        when(wordRepository.findByIdAndUserId(50L, 3L)).thenReturn(Optional.of(existing));
        when(wordRepository.save(existing)).thenReturn(existing);

        Word result = wordService.saveWord(existing);

        assertEquals(50L, result.getId());
        verify(progressService, never()).awardXp(anyLong(), anyInt(), anyString());
        verify(progressService, never()).updateStreak(anyLong());
    }

    @Test
    void saveWord_ShouldAwardXpAndStreak_ForANewWord() {
        // Was saveWord_ShouldNotFail_IfActivityPublisherFails, guarding a social-feed
        // publisher that no longer exists. What it still proves is worth keeping: adding a
        // word is what feeds XP and the streak, and those are the two rewards a learner
        // notices immediately.
        Word incoming = new Word();
        incoming.setUserId(4L);
        incoming.setEnglishWord("resilience");
        incoming.setLearnedDate(LocalDate.now());

        Word saved = new Word();
        saved.setId(7L);
        saved.setUserId(4L);
        saved.setEnglishWord("resilience");

        when(wordRepository.save(any(Word.class))).thenReturn(saved);
        assertDoesNotThrow(() -> wordService.saveWord(incoming));
        verify(progressService).awardXp(eq(4L), eq(10), contains("resilience"));
        verify(progressService).updateStreak(4L);
    }

    @Test
    void testUpdateWord() {
        Word existing = new Word();
        existing.setUserId(1L);
        existing.setEnglishWord("Old");

        Word details = new Word();
        details.setEnglishWord("New");

        when(wordRepository.findByIdAndUserId(1L, 1L)).thenReturn(Optional.of(existing));
        when(wordRepository.save(any())).thenReturn(existing);

        Word result = wordService.updateWord(1L, details, 1L);
        assertEquals("New", result.getEnglishWord());
    }

    @Test
    void updateWord_ShouldReturnNull_WhenWordNotFoundForUser() {
        when(wordRepository.findByIdAndUserId(77L, 2L)).thenReturn(Optional.empty());

        Word result = wordService.updateWord(77L, new Word(), 2L);

        assertNull(result);
        verify(wordRepository, never()).save(any());
    }

    @Test
    void testDeleteWord() {
        Word existing = new Word();
        existing.setUserId(1L);
        when(wordRepository.findByIdAndUserId(1L, 1L)).thenReturn(Optional.of(existing));

        wordService.deleteWord(1L, 1L);
        verify(wordRepository).deleteById(1L);
    }

    @Test
    void deleteWord_ShouldDoNothing_WhenWordNotOwnedOrMissing() {
        when(wordRepository.findByIdAndUserId(3L, 99L)).thenReturn(Optional.empty());

        wordService.deleteWord(3L, 99L);

        verify(wordRepository, never()).deleteById(anyLong());
    }

    @Test
    void testAddSentence() {
        Word word = new Word();
        word.setUserId(1L);
        word.setId(1L);

        when(wordRepository.findByIdAndUserId(1L, 1L)).thenReturn(Optional.of(word));
        when(wordRepository.save(any())).thenReturn(word);

        Word result = wordService.addSentence(1L, "Test", "Test TR", "easy", 1L);
        assertNotNull(result);
        verify(progressService).awardXp(eq(1L), eq(5), anyString());
    }

    @Test
    void addSentence_ShouldUseEasyDifficulty_WhenDifficultyNull() {
        Word word = new Word();
        word.setUserId(1L);
        word.setId(1L);
        word.setEnglishWord("hello");
        Sentence savedSentence = new Sentence("Hello world", "Merhaba dunya", "easy", word);
        savedSentence.setId(100L);

        when(wordRepository.findByIdAndUserId(1L, 1L)).thenReturn(Optional.of(word));
        when(wordRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));
        when(sentenceRepository.findByWordIdIn(anyList())).thenReturn(List.of(savedSentence));

        Word result = wordService.addSentence(1L, "Hello world", "Merhaba dunya", null, 1L);

        assertNotNull(result);
        assertEquals(1, result.getSentences().size());
        assertEquals("easy", result.getSentences().get(0).getDifficulty());
    }

    @Test
    void addSentence_ShouldReturnNull_WhenWordNotFoundForUser() {
        when(wordRepository.findByIdAndUserId(1L, 1L)).thenReturn(Optional.empty());

        Word result = wordService.addSentence(1L, "x", "y", "hard", 1L);

        assertNull(result);
        verify(progressService, never()).awardXp(anyLong(), anyInt(), anyString());
    }

    @Test
    void addSentence_ShouldReturnWordWithoutSideEffects_WhenDuplicateSentence() {
        Word word = new Word();
        word.setUserId(1L);
        word.setId(1L);

        when(wordRepository.findByIdAndUserId(1L, 1L)).thenReturn(Optional.of(word));
        when(sentenceRepository.findByWordIdAndSentenceAndTranslation(1L, "Hello", "Merhaba"))
                .thenReturn(List.of(new Sentence()));

        Word result = wordService.addSentence(1L, "Hello", "Merhaba", "easy", 1L);

        assertNotNull(result);
        verify(wordRepository, never()).save(any());
        verify(progressService, never()).awardXp(anyLong(), anyInt(), anyString());
    }

    @Test
    void addSentence_ShouldBypassDuplicateCheck_WhenSentenceNull() {
        Word word = new Word();
        word.setUserId(1L);
        word.setId(1L);
        word.setEnglishWord("null-path");

        when(wordRepository.findByIdAndUserId(1L, 1L)).thenReturn(Optional.of(word));
        when(wordRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));

        Word result = wordService.addSentence(1L, null, "ceviri", "hard", 1L);

        assertNotNull(result);
        verify(sentenceRepository, never()).findByWordIdAndSentenceAndTranslation(anyLong(), any(), any());
        verify(progressService).awardXp(eq(1L), eq(5), contains("null-path"));
    }

    @Test
    void deleteSentence_ShouldDelete_WhenWordAndSentenceMatchAndOwned() {
        Word word = new Word();
        word.setId(1L);
        word.setUserId(1L);

        Sentence sentence = new Sentence();
        sentence.setId(10L);
        sentence.setWord(word);
        word.setSentences(new java.util.ArrayList<>(List.of(sentence)));

        when(sentenceRepository.findByIdAndWordUserId(10L, 1L)).thenReturn(Optional.of(sentence));

        Word result = wordService.deleteSentence(1L, 10L, 1L);

        assertNotNull(result);
        assertEquals(0, result.getSentences().size());
        verify(sentenceRepository).delete(sentence);
        verify(wordRepository, never()).save(any());
    }

    @Test
    void deleteSentence_ShouldReturnNull_WhenSentenceNotFound() {
        when(sentenceRepository.findByIdAndWordUserId(99L, 1L)).thenReturn(Optional.empty());

        Word result = wordService.deleteSentence(1L, 99L, 1L);

        assertNull(result);
        verify(sentenceRepository, never()).delete(any());
    }

    @Test
    void deleteSentence_ShouldDelete_EvenIfWordIdMismatches_WhenSentenceOwned() {
        Word differentWord = new Word();
        differentWord.setId(2L);
        differentWord.setUserId(1L);

        Sentence sentence = new Sentence();
        sentence.setId(15L);
        sentence.setWord(differentWord);
        differentWord.setSentences(new java.util.ArrayList<>(List.of(sentence)));

        when(sentenceRepository.findByIdAndWordUserId(15L, 1L)).thenReturn(Optional.of(sentence));

        Word result = wordService.deleteSentence(1L, 15L, 1L);

        assertNotNull(result);
        assertEquals(2L, result.getId());
        assertEquals(0, result.getSentences().size());
        verify(sentenceRepository).delete(sentence);
        verify(wordRepository, never()).save(any());
    }

    @Test
    void deleteSentence_ShouldReturnNull_WhenSentenceNotOwnedByUser() {
        when(sentenceRepository.findByIdAndWordUserId(21L, 1L)).thenReturn(Optional.empty());

        Word result = wordService.deleteSentence(1L, 21L, 1L);

        assertNull(result);
        verify(sentenceRepository, never()).delete(any());
    }

    @Test
    void deleteSentence_ShouldNotSaveWordEntity() {
        Word word = new Word();
        word.setId(1L);
        word.setUserId(1L);

        Sentence sentence = new Sentence();
        sentence.setId(22L);
        sentence.setWord(word);
        word.setSentences(new java.util.ArrayList<>(List.of(sentence)));

        when(sentenceRepository.findByIdAndWordUserId(22L, 1L)).thenReturn(Optional.of(sentence));

        Word result = wordService.deleteSentence(1L, 22L, 1L);

        assertNotNull(result);
        verify(sentenceRepository).delete(sentence);
        verify(wordRepository, never()).save(any());
    }

    // ---- V028: language profiles and meanings ----

    @Test
    void saveWord_ShouldAssignTheActiveProfile_Origin_AndMeaningsSplitFromTheLegacyString() {
        // The shipped client sends only turkishMeaning; the star in it is how it marks a word
        // saved from the daily-words flow. The server has to derive everything else.
        Word incoming = new Word();
        incoming.setUserId(1L);
        incoming.setEnglishWord("bank");
        incoming.setTurkishMeaning("⭐ banka; kıyı / Banka, , banka");
        incoming.setLearnedDate(LocalDate.now());
        when(wordRepository.save(any(Word.class))).thenAnswer(inv -> inv.getArgument(0));

        Word saved = wordService.saveWord(incoming);

        assertEquals(ACTIVE_PROFILE_ID, saved.getLanguageProfileId());
        assertEquals(WordOrigin.DAILY_WORDS, saved.getOrigin());
        assertEquals("⭐ banka; kıyı / Banka, , banka", saved.getTurkishMeaning(),
                "the legacy string is what the shipped client reads; it is not rewritten");
        List<String> translations = saved.getMeanings().stream().map(WordMeaning::getTranslation).toList();
        assertEquals(List.of("banka", "kıyı"), translations,
                "split on , ; and ' / ', star stripped, blanks dropped, case-insensitive duplicates dropped");
        assertEquals(List.of(0, 1), saved.getMeanings().stream().map(WordMeaning::getPosition).toList());
        for (WordMeaning meaning : saved.getMeanings()) {
            assertSame(saved, meaning.getWord());
        }
    }

    @Test
    void saveWord_ShouldKeepExplicitMeanings_AndFillTheLegacyStringFromThem() {
        Word incoming = new Word();
        incoming.setUserId(1L);
        incoming.setEnglishWord("run");
        incoming.setLearnedDate(LocalDate.now());
        incoming.addMeaning(new WordMeaning(null, " koşmak ", "to move fast", 7));
        incoming.addMeaning(new WordMeaning(null, "", null, 0));
        incoming.addMeaning(new WordMeaning(null, "çalıştırmak", " ", 0));
        incoming.addMeaning(new WordMeaning(null, "KOŞMAK", null, 0));
        when(wordRepository.save(any(Word.class))).thenAnswer(inv -> inv.getArgument(0));

        Word saved = wordService.saveWord(incoming);

        assertEquals(List.of("koşmak", "çalıştırmak"),
                saved.getMeanings().stream().map(WordMeaning::getTranslation).toList());
        assertEquals(List.of(0, 1), saved.getMeanings().stream().map(WordMeaning::getPosition).toList(),
                "positions are renumbered in the order given, whatever the client sent");
        assertEquals("to move fast", saved.getMeanings().get(0).getDefinition());
        assertNull(saved.getMeanings().get(1).getDefinition(), "a blank definition is stored as null");
        assertEquals("koşmak, çalıştırmak", saved.getTurkishMeaning(),
                "a client that sends only meanings still produces the string the old client reads");
        assertEquals(WordOrigin.MANUAL, saved.getOrigin());
    }

    @Test
    void saveWord_ShouldNotTouchProfileOrMeanings_WhenUpdatingAnExistingWord() {
        Word existing = new Word();
        existing.setId(50L);
        existing.setUserId(3L);
        existing.setEnglishWord("existing");
        existing.setTurkishMeaning("mevcut");
        existing.setLearnedDate(LocalDate.now());
        when(wordRepository.findByIdAndUserId(50L, 3L)).thenReturn(Optional.of(existing));
        when(wordRepository.save(existing)).thenReturn(existing);

        wordService.saveWord(existing);

        assertNull(existing.getLanguageProfile());
        assertTrue(existing.getMeanings().isEmpty());
        verify(languageProfileService, never()).ensureDefaultProfile(anyLong());
    }

    @Test
    void saveWord_WithABlankMeaningString_ShouldCreateNoMeanings() {
        Word incoming = new Word();
        incoming.setUserId(1L);
        incoming.setEnglishWord("blank");
        incoming.setTurkishMeaning("  ⭐ ");
        incoming.setLearnedDate(LocalDate.now());
        when(wordRepository.save(any(Word.class))).thenAnswer(inv -> inv.getArgument(0));

        Word saved = wordService.saveWord(incoming);

        assertTrue(saved.getMeanings().isEmpty());
        assertEquals(WordOrigin.DAILY_WORDS, saved.getOrigin());
    }

    @Test
    void splitMeaningString_FollowsTheBackfillRule() {
        assertEquals(List.of("koşmak", "çalıştırmak"), WordService.splitMeaningString("koşmak, çalıştırmak"));
        assertEquals(List.of("a/b", "c", "d", "e"), WordService.splitMeaningString("a/b, c / d,, e"),
                "a slash without spaces around it is part of the word");
        assertEquals(List.of("yıldız"), WordService.splitMeaningString("yıldız ★"));
        assertEquals(List.of(), WordService.splitMeaningString(null));
        assertEquals(List.of(), WordService.splitMeaningString("   "));
    }

    @Test
    void getAllWords_ShouldUseTheProfileGivenByTheCaller() {
        LanguageProfile german = new LanguageProfile(1L, "Turkish", "German", "A1", null, false);
        german.setId(600L);
        when(languageProfileService.getProfile(1L, 600L)).thenReturn(Optional.of(german));
        when(wordRepository.findByUserIdAndLanguageProfileId(1L, 600L)).thenReturn(List.of(new Word()));

        assertEquals(1, wordService.getAllWords(1L, 600L).size());
        verify(languageProfileService, never()).ensureDefaultProfile(anyLong());
    }

    @Test
    void getAllWords_WithAProfileThatIsNotTheCallers_ShouldBeNotFound() {
        when(languageProfileService.getProfile(1L, 601L)).thenReturn(Optional.empty());

        assertThrows(java.util.NoSuchElementException.class, () -> wordService.getAllWords(1L, 601L));
        verify(wordRepository, never()).findByUserIdAndLanguageProfileId(anyLong(), anyLong());
    }

    private Word wordWithMeanings(String turkishMeaning, String... translations) {
        Word word = new Word();
        word.setId(1L);
        word.setUserId(1L);
        word.setEnglishWord("bank");
        word.setTurkishMeaning(turkishMeaning);
        for (int i = 0; i < translations.length; i++) {
            WordMeaning meaning = new WordMeaning(null, translations[i], null, i);
            meaning.setId(100L + i);
            word.addMeaning(meaning);
        }
        when(wordRepository.findByIdAndUserId(1L, 1L)).thenReturn(Optional.of(word));
        when(wordRepository.save(any(Word.class))).thenAnswer(inv -> inv.getArgument(0));
        return word;
    }

    /** The sentences on the word at the moment it is saved; hydration replaces the list afterwards. */
    private List<Sentence> sentencesAtSave() {
        List<Sentence> atSave = new ArrayList<>();
        when(wordRepository.save(any(Word.class))).thenAnswer(inv -> {
            Word word = inv.getArgument(0);
            atSave.addAll(word.getSentences());
            return word;
        });
        return atSave;
    }

    @Test
    void addSentence_WithAMeaningId_ShouldAttachTheSentenceToThatMeaning() {
        Word word = wordWithMeanings("banka, kıyı", "banka", "kıyı");
        List<Sentence> atSave = sentencesAtSave();

        wordService.addSentence(1L, "We sat on the river bank.", "Nehir kıyısında oturduk.", "easy", 1L, 101L);

        assertEquals(1, atSave.size());
        assertSame(word.getMeanings().get(1), atSave.get(0).getMeaning());
        assertEquals(101L, atSave.get(0).getMeaningId());
    }

    @Test
    void addSentence_WithoutAMeaningId_ShouldLeaveTheSentenceUnassigned() {
        wordWithMeanings("banka, kıyı", "banka", "kıyı");
        List<Sentence> atSave = sentencesAtSave();

        wordService.addSentence(1L, "I went to the bank.", "Bankaya gittim.", "easy", 1L);

        assertEquals(1, atSave.size());
        assertNull(atSave.get(0).getMeaning());
    }

    @Test
    void addSentence_WithAMeaningOfAnotherWord_ShouldBeRejectedBeforeAnythingIsSaved() {
        wordWithMeanings("banka, kıyı", "banka", "kıyı");

        assertThrows(IllegalArgumentException.class,
                () -> wordService.addSentence(1L, "x", "y", "easy", 1L, 999L));
        verify(wordRepository, never()).save(any());
        verify(progressService, never()).awardXp(anyLong(), anyInt(), anyString());
    }

    @Test
    void addSentence_DuplicateOfAnUnassignedSentence_ShouldAdoptTheMeaningNowGiven() {
        Word word = wordWithMeanings("banka, kıyı", "banka", "kıyı");
        Sentence existing = new Sentence("I went to the bank.", "Bankaya gittim.", "easy", word);
        existing.setId(7L);
        when(sentenceRepository.findByWordIdAndSentenceAndTranslation(1L, "I went to the bank.", "Bankaya gittim."))
                .thenReturn(List.of(existing));

        wordService.addSentence(1L, "I went to the bank.", "Bankaya gittim.", "easy", 1L, 100L);

        assertSame(word.getMeanings().get(0), existing.getMeaning());
        verify(wordRepository, never()).save(any());
        verify(progressService, never()).awardXp(anyLong(), anyInt(), anyString());
    }

    @Test
    void addMeaning_ShouldAppendAtTheEnd_AndRewriteTheLegacyStringKeepingTheStar() {
        Word word = wordWithMeanings("⭐ banka", "banka");

        Word result = wordService.addMeaning(1L, 1L, "  kıyı ", "  ");

        assertEquals(2, result.getMeanings().size());
        WordMeaning added = result.getMeanings().get(1);
        assertEquals("kıyı", added.getTranslation());
        assertNull(added.getDefinition());
        assertEquals(1, added.getPosition());
        assertSame(word, added.getWord());
        assertEquals("⭐ banka, kıyı", result.getTurkishMeaning(),
                "the old client reads provenance from the star, so it must survive a rewrite");
    }

    @Test
    void addMeaning_WithATranslationTheWordAlreadyHas_ShouldChangeNothing() {
        wordWithMeanings("banka", "banka");

        Word result = wordService.addMeaning(1L, 1L, "BANKA", null);

        assertEquals(1, result.getMeanings().size());
        verify(wordRepository, never()).save(any());
    }

    @Test
    void addMeaning_BlankTranslation_IsRejected_AndUnknownWordIsNotFound() {
        wordWithMeanings("banka", "banka");
        assertThrows(IllegalArgumentException.class, () -> wordService.addMeaning(1L, 1L, " ⭐ ", null));

        when(wordRepository.findByIdAndUserId(2L, 1L)).thenReturn(Optional.empty());
        assertThrows(java.util.NoSuchElementException.class, () -> wordService.addMeaning(2L, 1L, "x", null));
        verify(wordRepository, never()).save(any());
    }

    @Test
    void updateMeaning_ShouldChangeOnlyWhatWasSent_AndResyncTheLegacyString() {
        Word word = wordWithMeanings("banka, kıyı", "banka", "kıyı");
        word.getMeanings().get(0).setDefinition("financial institution");

        Word result = wordService.updateMeaning(1L, 100L, 1L, "banka (finans)", null);
        assertEquals("banka (finans)", result.getMeanings().get(0).getTranslation());
        assertEquals("financial institution", result.getMeanings().get(0).getDefinition());
        assertEquals("banka (finans), kıyı", result.getTurkishMeaning());

        wordService.updateMeaning(1L, 100L, 1L, null, "");
        assertNull(word.getMeanings().get(0).getDefinition(), "a blank definition clears it");

        assertThrows(IllegalArgumentException.class, () -> wordService.updateMeaning(1L, 100L, 1L, "", null));
        assertThrows(java.util.NoSuchElementException.class,
                () -> wordService.updateMeaning(1L, 999L, 1L, "x", null));
    }

    @Test
    void deleteMeaning_ShouldUnassignItsSentences_RemoveIt_AndResyncTheLegacyString() {
        Word word = wordWithMeanings("banka, kıyı", "banka", "kıyı");
        WordMeaning shore = word.getMeanings().get(1);
        Sentence onShore = new Sentence("We sat on the bank.", "Kıyıda oturduk.", "easy", word);
        onShore.setId(8L);
        onShore.setMeaning(shore);
        when(sentenceRepository.findByMeaningId(101L)).thenReturn(List.of(onShore));

        Word result = wordService.deleteMeaning(1L, 101L, 1L);

        assertNull(onShore.getMeaning(), "the learner's sentence survives as unassigned");
        assertEquals(List.of("banka"), result.getMeanings().stream().map(WordMeaning::getTranslation).toList());
        assertEquals("banka", result.getTurkishMeaning());
        verify(wordRepository).save(word);
    }

    @Test
    void deleteMeaning_OfTheLastMeaning_IsRefused() {
        wordWithMeanings("banka", "banka");

        assertThrows(WordService.LastMeaningException.class, () -> wordService.deleteMeaning(1L, 100L, 1L));
        verify(wordRepository, never()).save(any());
        verify(sentenceRepository, never()).findByMeaningId(anyLong());
    }

    @Test
    void deleteMeaning_OfAMeaningTheWordDoesNotHave_IsNotFound() {
        wordWithMeanings("banka, kıyı", "banka", "kıyı");

        assertThrows(java.util.NoSuchElementException.class, () -> wordService.deleteMeaning(1L, 999L, 1L));
        verify(wordRepository, never()).save(any());
    }
}
