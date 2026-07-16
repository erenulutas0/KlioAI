package com.ingilizce.calismaapp.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ingilizce.calismaapp.entity.Sentence;
import com.ingilizce.calismaapp.entity.SentencePractice;
import com.ingilizce.calismaapp.entity.Word;
import com.ingilizce.calismaapp.service.SentencePracticeService;
import com.ingilizce.calismaapp.repository.SentenceRepository;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Optional;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.hamcrest.Matchers.hasSize;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@TestPropertySource(properties = {
        "GROQ_API_KEY=dummy-key",
        "spring.datasource.url=jdbc:h2:mem:practicedb;DB_CLOSE_DELAY=-1;MODE=PostgreSQL",
        "spring.datasource.driver-class-name=org.h2.Driver"
})
public class SentencePracticeControllerTest {

    private Locale originalDefaultLocale;

    @BeforeEach
    void captureDefaultLocale() {
        originalDefaultLocale = Locale.getDefault();
    }

    @AfterEach
    void restoreDefaultLocale() {
        Locale.setDefault(originalDefaultLocale);
    }

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private SentencePracticeService sentencePracticeService;

    @MockBean
    private SentenceRepository sentenceRepository;

    @Autowired
    private ObjectMapper objectMapper;

    @Test
    void testGetAllSentences() throws Exception {
        SentencePractice practice = new SentencePractice();
        practice.setId(10L);
        practice.setEnglishSentence("Practice sentence");
        practice.setTurkishTranslation("Alistirma cumlesi");
        practice.setDifficulty(SentencePractice.DifficultyLevel.MEDIUM);
        practice.setCreatedDate(LocalDate.now());

        Word word = new Word();
        word.setId(20L);
        word.setEnglishWord("hello");
        word.setTurkishMeaning("merhaba");
        word.setLearnedDate(LocalDate.now());

        Sentence sentence = new Sentence();
        sentence.setId(30L);
        sentence.setSentence("Hello world");
        sentence.setTranslation("Merhaba dunya");
        sentence.setDifficulty(null); // fallback branch -> "easy"
        sentence.setWord(word);

        when(sentencePracticeService.getPracticeSentencesPage(eq(1L), eq(0), eq(100)))
                .thenReturn(new PageImpl<>(List.of(practice), PageRequest.of(0, 100), 1));
        when(sentenceRepository.findAllWithWordByUserId(eq(1L), any(PageRequest.class)))
                .thenReturn(new PageImpl<>(List.of(sentence), PageRequest.of(0, 100), 1));

        mockMvc.perform(get("/api/sentences")
                .header("X-User-Id", "1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(2)));
    }

    @Test
    void testGetAllSentences_ReturnsBadRequestWhenHeaderMissing() throws Exception {
        mockMvc.perform(get("/api/sentences"))
                .andExpect(status().isBadRequest());

        verify(sentencePracticeService, never()).getPracticeSentencesPage(anyLong(), anyInt(), anyInt());
    }

    @Test
    void testGetPracticeSentencesPaged() throws Exception {
        SentencePractice practice = new SentencePractice();
        practice.setId(1L);
        practice.setEnglishSentence("Paged sentence");
        practice.setDifficulty(SentencePractice.DifficultyLevel.EASY);

        when(sentencePracticeService.getPracticeSentencesPage(eq(1L), eq(0), eq(2)))
                .thenReturn(new PageImpl<>(List.of(practice), PageRequest.of(0, 2), 1));

        mockMvc.perform(get("/api/sentences/practice/paged")
                .header("X-User-Id", "1")
                .param("page", "0")
                .param("size", "2"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.content", hasSize(1)));
    }

    @Test
    void testGetPracticeSentencesPaged_ReturnsBadRequestWhenHeaderInvalid() throws Exception {
        mockMvc.perform(get("/api/sentences/practice/paged")
                .header("X-User-Id", "not-a-number")
                .param("page", "-5")
                .param("size", "999"))
                .andExpect(status().isBadRequest());

        verify(sentencePracticeService, never()).getPracticeSentencesPage(anyLong(), anyInt(), anyInt());
    }

    @Test
    void testCreateSentence() throws Exception {
        SentencePractice sp = new SentencePractice();
        sp.setEnglishSentence("Test");
        sp.setDifficulty(SentencePractice.DifficultyLevel.EASY);

        when(sentencePracticeService.saveSentence(any(SentencePractice.class))).thenReturn(sp);

        mockMvc.perform(post("/api/sentences")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(sp)))
                .andExpect(status().isOk());
    }

    @Test
    void testGetSentenceById_NotFound() throws Exception {
        when(sentencePracticeService.getSentenceByIdAndUser(eq(999L), eq(1L))).thenReturn(Optional.empty());

        mockMvc.perform(get("/api/sentences/999").header("X-User-Id", "1"))
                .andExpect(status().isNotFound());
    }

    @Test
    void testUpdateSentence_NotFound() throws Exception {
        SentencePractice update = new SentencePractice();
        update.setEnglishSentence("Updated");
        update.setDifficulty(SentencePractice.DifficultyLevel.MEDIUM);

        when(sentencePracticeService.updateSentence(eq(77L), any(SentencePractice.class), eq(1L))).thenReturn(null);

        mockMvc.perform(put("/api/sentences/77")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(update)))
                .andExpect(status().isNotFound());
    }

    @Test
    void testUpdateSentence_Success() throws Exception {
        SentencePractice update = new SentencePractice();
        update.setEnglishSentence("Updated");
        update.setDifficulty(SentencePractice.DifficultyLevel.MEDIUM);

        SentencePractice saved = new SentencePractice();
        saved.setId(77L);
        saved.setEnglishSentence("Updated");
        saved.setDifficulty(SentencePractice.DifficultyLevel.MEDIUM);

        when(sentencePracticeService.updateSentence(eq(77L), any(SentencePractice.class), eq(1L))).thenReturn(saved);

        mockMvc.perform(put("/api/sentences/77")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(update)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.englishSentence").value("Updated"));
    }

    @Test
    void testDeleteSentence_InvalidId() throws Exception {
        mockMvc.perform(delete("/api/sentences/not-a-number")
                .header("X-User-Id", "1"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void testDeleteSentence_PracticePrefix_Success() throws Exception {
        when(sentencePracticeService.deleteSentence(eq(15L), eq(1L))).thenReturn(true);

        mockMvc.perform(delete("/api/sentences/practice_15")
                .header("X-User-Id", "1"))
                .andExpect(status().isOk());
    }

    @Test
    void testDeleteSentence_PracticePrefix_NotFound() throws Exception {
        when(sentencePracticeService.deleteSentence(eq(15L), eq(1L))).thenReturn(false);

        mockMvc.perform(delete("/api/sentences/practice_15")
                .header("X-User-Id", "1"))
                .andExpect(status().isNotFound());
    }

    @Test
    void testDeleteSentence_WordPrefix_Success() throws Exception {
        Sentence ownedSentence = new Sentence();
        ownedSentence.setId(42L);
        when(sentenceRepository.findByIdAndWordUserId(42L, 1L)).thenReturn(Optional.of(ownedSentence));

        mockMvc.perform(delete("/api/sentences/word_42")
                .header("X-User-Id", "1"))
                .andExpect(status().isOk());

        verify(sentenceRepository).delete(ownedSentence);
    }

    @Test
    void testDeleteSentence_WordPrefix_NotFound_WhenNotOwnedOrMissing() throws Exception {
        when(sentenceRepository.findByIdAndWordUserId(42L, 1L)).thenReturn(Optional.empty());

        mockMvc.perform(delete("/api/sentences/word_42")
                .header("X-User-Id", "1"))
                .andExpect(status().isNotFound());
    }

    @Test
    void testDeleteSentence_WordPrefix_InternalServerError() throws Exception {
        Sentence ownedSentence = new Sentence();
        ownedSentence.setId(42L);
        when(sentenceRepository.findByIdAndWordUserId(42L, 1L)).thenReturn(Optional.of(ownedSentence));
        doThrow(new RuntimeException("db error")).when(sentenceRepository).delete(ownedSentence);

        mockMvc.perform(delete("/api/sentences/word_42")
                .header("X-User-Id", "1"))
                .andExpect(status().isInternalServerError());
    }

    @Test
    void testDeleteSentence_NumericId_ReturnsBadRequestWhenHeaderInvalid() throws Exception {
        mockMvc.perform(delete("/api/sentences/25")
                .header("X-User-Id", "invalid-user"))
                .andExpect(status().isBadRequest());

        verify(sentencePracticeService, never()).deleteSentence(anyLong(), anyLong());
    }

    @Test
    void testDeleteSentence_NumericId_NotFound() throws Exception {
        when(sentencePracticeService.deleteSentence(eq(25L), eq(1L))).thenReturn(false);

        mockMvc.perform(delete("/api/sentences/25")
                .header("X-User-Id", "1"))
                .andExpect(status().isNotFound());
    }

    @Test
    void testGetSentencesByDifficulty_Success() throws Exception {
        SentencePractice sp = new SentencePractice();
        sp.setId(3L);
        sp.setDifficulty(SentencePractice.DifficultyLevel.HARD);
        when(sentencePracticeService.getSentencesByDifficulty(1L, SentencePractice.DifficultyLevel.HARD))
                .thenReturn(List.of(sp));

        mockMvc.perform(get("/api/sentences/difficulty/hard")
                .header("X-User-Id", "1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)));
    }

    @Test
    void testGetSentencesByDifficulty_MediumSucceeds_OnTurkishLocaleJvm() throws Exception {
        // Regression test: on a JVM whose default locale is Turkish,
        // "medium".toUpperCase() (without Locale.ROOT) used to produce "MEDİUM"
        // (dotted capital I), which never matched DifficultyLevel.MEDIUM and
        // caused this endpoint to always return 400 for medium-difficulty
        // lookups. CI runners default to en_US, so this bug was invisible there.
        Locale.setDefault(new Locale("tr", "TR"));

        SentencePractice sp = new SentencePractice();
        sp.setId(4L);
        sp.setDifficulty(SentencePractice.DifficultyLevel.MEDIUM);
        when(sentencePracticeService.getSentencesByDifficulty(1L, SentencePractice.DifficultyLevel.MEDIUM))
                .thenReturn(List.of(sp));

        mockMvc.perform(get("/api/sentences/difficulty/medium")
                .header("X-User-Id", "1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)));
    }

    @Test
    void testGetSentencesByDifficulty_InvalidDifficulty() throws Exception {
        mockMvc.perform(get("/api/sentences/difficulty/invalid")
                .header("X-User-Id", "1"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void testGetSentencesByDate_Success() throws Exception {
        when(sentencePracticeService.getSentencesByDate(1L, LocalDate.of(2026, 2, 10)))
                .thenReturn(List.of(new SentencePractice()));

        mockMvc.perform(get("/api/sentences/date/2026-02-10")
                .header("X-User-Id", "1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)));
    }

    @Test
    void testGetSentencesByDate_InvalidDate() throws Exception {
        mockMvc.perform(get("/api/sentences/date/not-a-date")
                .header("X-User-Id", "1"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void testGetAllDistinctDates_Success() throws Exception {
        when(sentencePracticeService.getAllDistinctDates(1L)).thenReturn(List.of(LocalDate.of(2026, 2, 10)));

        mockMvc.perform(get("/api/sentences/dates")
                .header("X-User-Id", "1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0]").value("2026-02-10"));
    }

    @Test
    void testGetSentencesByDateRange_Success() throws Exception {
        when(sentencePracticeService.getSentencesByDateRange(1L, LocalDate.of(2026, 2, 1), LocalDate.of(2026, 2, 10)))
                .thenReturn(List.of(new SentencePractice()));

        mockMvc.perform(get("/api/sentences/date-range")
                .header("X-User-Id", "1")
                .param("startDate", "2026-02-01")
                .param("endDate", "2026-02-10"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)));
    }

    @Test
    void testGetSentencesByDateRange_InvalidDates() throws Exception {
        mockMvc.perform(get("/api/sentences/date-range")
                .header("X-User-Id", "1")
                .param("startDate", "2026-01-01")
                .param("endDate", "invalid"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void testGetAllSentences_WordDifficultyLowercase_WithoutWordInfo() throws Exception {
        Sentence sentence = new Sentence();
        sentence.setId(99L);
        sentence.setSentence("A hard sentence");
        sentence.setTranslation("Zor bir cumle");
        sentence.setDifficulty("HARD");
        sentence.setWord(null);

        when(sentencePracticeService.getPracticeSentencesPage(eq(1L), eq(0), eq(100)))
                .thenReturn(new PageImpl<>(List.of(), PageRequest.of(0, 100), 0));
        when(sentenceRepository.findAllWithWordByUserId(eq(1L), any(PageRequest.class)))
                .thenReturn(new PageImpl<>(List.of(sentence), PageRequest.of(0, 100), 1));

        mockMvc.perform(get("/api/sentences")
                .header("X-User-Id", "1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].id").value("word_99"))
                .andExpect(jsonPath("$[0].difficulty").value("hard"))
                .andExpect(jsonPath("$[0].word").doesNotExist());
    }

    @Test
    void testGetStatistics() throws Exception {
        when(sentencePracticeService.getTotalSentenceCount(anyLong())).thenReturn(10L);
        when(sentencePracticeService.getSentenceCountByDifficulty(anyLong(), eq(SentencePractice.DifficultyLevel.EASY)))
                .thenReturn(3L);
        when(sentencePracticeService.getSentenceCountByDifficulty(anyLong(), eq(SentencePractice.DifficultyLevel.MEDIUM)))
                .thenReturn(4L);
        when(sentencePracticeService.getSentenceCountByDifficulty(anyLong(), eq(SentencePractice.DifficultyLevel.HARD)))
                .thenReturn(3L);
        when(sentenceRepository.countByUserId(anyLong())).thenReturn(5L);
        when(sentenceRepository.countByDifficultyAndUserId(eq("easy"), anyLong())).thenReturn(2L);
        when(sentenceRepository.countByDifficultyAndUserId(eq("medium"), anyLong())).thenReturn(2L);
        when(sentenceRepository.countByDifficultyAndUserId(eq("hard"), anyLong())).thenReturn(1L);

        mockMvc.perform(get("/api/sentences/stats")
                .header("X-User-Id", "1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.total").value(15))
                .andExpect(jsonPath("$.easy").value(5))
                .andExpect(jsonPath("$.medium").value(6))
                .andExpect(jsonPath("$.hard").value(4));
    }
}
