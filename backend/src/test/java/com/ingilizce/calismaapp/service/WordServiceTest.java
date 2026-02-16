package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.entity.Word;
import com.ingilizce.calismaapp.entity.Sentence;
import com.ingilizce.calismaapp.dto.CreateWordRequest;
import com.ingilizce.calismaapp.repository.WordRepository;
import com.ingilizce.calismaapp.repository.SentenceRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
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

    @Mock
    private LeaderboardService leaderboardService;

    @Mock
    private ActivityPublisher activityPublisher;

    // We mock other dependencies to avoid NPEs during context load if they are
    // autowired
    @Mock
    private ProgressService progressService;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
        when(wordRepository.findByUserIdAndEnglishWord(anyLong(), anyString()))
                .thenReturn(Optional.empty());
        when(sentenceRepository.findByWordIdIn(anyList())).thenReturn(List.of());
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

        // Verify Leaderboard was updated (+10 points)
        verify(leaderboardService, times(1)).incrementScore(eq(userId), eq(10.0));

        // Verify Social Feed logged the activity
        verify(activityPublisher, times(1)).publishWordAdded(eq(userId), eq("Serendipity"));
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
        verify(leaderboardService, never()).incrementScore(anyLong(), anyDouble());
        verify(activityPublisher, never()).publishWordAdded(anyLong(), anyString());
        verify(progressService, never()).awardXp(anyLong(), anyInt(), anyString());
    }

    @Test
    void saveWord_ShouldNotFail_IfLeaderboardServiceFails() {
        // Arrange: Simulate Leaderboard acting up (e.g. Redis down)
        Word word = new Word();
        word.setUserId(1L);
        word.setEnglishWord("Test");

        when(wordRepository.save(any(Word.class))).thenReturn(word);
        doThrow(new RuntimeException("Redis Down")).when(leaderboardService).incrementScore(anyLong(), anyDouble());

        // Act & Assert: Should NOT throw exception
        assertDoesNotThrow(() -> wordService.saveWord(word));

        // Verify essential save still happened
        verify(wordRepository, times(1)).save(word);
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
        when(wordRepository.findByUserId(1L)).thenReturn(new java.util.ArrayList<>());
        assertNotNull(wordService.getAllWords(1L));

        when(wordRepository.findById(1L)).thenReturn(Optional.of(new Word()));
        assertTrue(wordService.getWordById(1L).isPresent());
    }

    @Test
    void getWordsPageAndDateQueries_ShouldDelegateToRepository() {
        LocalDate date = LocalDate.of(2026, 2, 11);
        Page<Word> page = new PageImpl<>(List.of(new Word()));
        when(wordRepository.findByUserId(1L, PageRequest.of(0, 10))).thenReturn(page);
        when(wordRepository.findByUserIdAndLearnedDate(1L, date)).thenReturn(List.of(new Word()));
        when(wordRepository.findByUserIdAndDateRange(1L, date.minusDays(3), date)).thenReturn(List.of(new Word(), new Word()));
        when(wordRepository.findDistinctDatesByUserId(1L)).thenReturn(List.of(date));

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
        verify(leaderboardService).incrementScore(2L, 10.0);
    }

    @Test
    void saveWord_ShouldSkipSideEffects_WhenUpdatingExistingWord() {
        Word existing = new Word();
        existing.setId(50L);
        existing.setUserId(3L);
        existing.setEnglishWord("existing");
        existing.setLearnedDate(LocalDate.now());

        when(wordRepository.save(existing)).thenReturn(existing);

        Word result = wordService.saveWord(existing);

        assertEquals(50L, result.getId());
        verify(leaderboardService, never()).incrementScore(anyLong(), anyDouble());
        verify(activityPublisher, never()).publishWordAdded(anyLong(), anyString());
        verify(progressService, never()).awardXp(anyLong(), anyInt(), anyString());
        verify(progressService, never()).updateStreak(anyLong());
    }

    @Test
    void saveWord_ShouldNotFail_IfActivityPublisherFails() {
        Word incoming = new Word();
        incoming.setUserId(4L);
        incoming.setEnglishWord("resilience");
        incoming.setLearnedDate(LocalDate.now());

        Word saved = new Word();
        saved.setId(7L);
        saved.setUserId(4L);
        saved.setEnglishWord("resilience");

        when(wordRepository.save(any(Word.class))).thenReturn(saved);
        doThrow(new RuntimeException("feed down")).when(activityPublisher)
                .publishWordAdded(eq(4L), anyString());

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
}
