package com.ingilizce.calismaapp.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ingilizce.calismaapp.entity.Sentence;
import com.ingilizce.calismaapp.entity.Word;
import com.ingilizce.calismaapp.service.WordService;
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
import java.util.Optional;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@TestPropertySource(properties = {
                "GROQ_API_KEY=dummy-key",
                "spring.datasource.url=jdbc:h2:mem:worddb;DB_CLOSE_DELAY=-1;MODE=PostgreSQL",
                "spring.datasource.driver-class-name=org.h2.Driver"
})
public class WordControllerTest {

        @Autowired
        private MockMvc mockMvc;

        @MockBean
        private WordService wordService;

        @Autowired
        private ObjectMapper objectMapper;

        @Test
        void testGetAllWords() throws Exception {
                when(wordService.getWordsPage(eq(1L), eq(0), eq(100)))
                                .thenReturn(new PageImpl<>(new ArrayList<>(), PageRequest.of(0, 100), 0));

                mockMvc.perform(get("/api/words")
                                .header("X-User-Id", "1"))
                                .andExpect(status().isOk());
    }

    @Test
    void testGetAllWords_ReturnsBadRequestWhenHeaderMissing() throws Exception {
            mockMvc.perform(get("/api/words"))
                            .andExpect(status().isBadRequest());

            verify(wordService, never()).getWordsPage(anyLong(), anyInt(), anyInt());
    }

        @Test
        void testGetAllWords_NormalizesPaging() throws Exception {
                when(wordService.getWordsPage(eq(1L), eq(0), eq(200)))
                                .thenReturn(new PageImpl<>(new ArrayList<>(), PageRequest.of(0, 200), 0));

                mockMvc.perform(get("/api/words")
                                .header("X-User-Id", "1")
                                .param("page", "-3")
                                .param("size", "999"))
                                .andExpect(status().isOk());

                verify(wordService).getWordsPage(1L, 0, 200);
        }

        @Test
        void testGetWordsPageEndpoint_NormalizesPaging() throws Exception {
                when(wordService.getWordsPage(eq(1L), eq(0), eq(200)))
                                .thenReturn(new PageImpl<>(new ArrayList<>(), PageRequest.of(0, 200), 0));

                mockMvc.perform(get("/api/words/paged")
                                .header("X-User-Id", "1")
                                .param("page", "-1")
                                .param("size", "1000"))
                                .andExpect(status().isOk());

                verify(wordService).getWordsPage(1L, 0, 200);
        }

        @Test
        void testCreateWord() throws Exception {
                Word word = new Word();
                word.setEnglishWord("Apple");
                word.setTurkishMeaning("Elma");

                when(wordService.saveWord(any())).thenReturn(word);

                mockMvc.perform(post("/api/words")
                                .header("X-User-Id", "1")
                                .contentType(MediaType.APPLICATION_JSON)
                                .content(objectMapper.writeValueAsString(word)))
                                .andExpect(status().isOk());
        }

    @Test
    void testCreateWord_InvalidHeaderReturnsBadRequest() throws Exception {
            Word word = new Word();
            word.setEnglishWord("Banana");
            word.setTurkishMeaning("Muz");

            mockMvc.perform(post("/api/words")
                                .header("X-User-Id", "invalid")
                                .contentType(MediaType.APPLICATION_JSON)
                                .content(objectMapper.writeValueAsString(word)))
                                .andExpect(status().isBadRequest());

            verify(wordService, never()).saveWord(any(Word.class));
    }

        @Test
        void testGetWordByIdFound() throws Exception {
                Word word = new Word();
                word.setId(5L);
                word.setEnglishWord("House");

                when(wordService.getWordByIdAndUserWithSentences(5L, 1L)).thenReturn(Optional.of(word));

                mockMvc.perform(get("/api/words/5").header("X-User-Id", "1"))
                                .andExpect(status().isOk())
                                .andExpect(jsonPath("$.id").value(5))
                                .andExpect(jsonPath("$.englishWord").value("House"));
        }

        @Test
        void testGetWordByIdNotFound() throws Exception {
                when(wordService.getWordByIdAndUserWithSentences(99L, 1L)).thenReturn(Optional.empty());

                mockMvc.perform(get("/api/words/99").header("X-User-Id", "1"))
                                .andExpect(status().isNotFound());
        }

        @Test
        void testGetWordSentencesFound() throws Exception {
                Word word = new Word();
                word.setId(7L);
                Sentence sentence = new Sentence();
                sentence.setId(70L);
                sentence.setSentence("A sample sentence");
                sentence.setWord(word);
                word.setSentences(List.of(sentence));

                when(wordService.getWordByIdAndUserWithSentences(7L, 1L)).thenReturn(Optional.of(word));

                mockMvc.perform(get("/api/words/7/sentences").header("X-User-Id", "1"))
                                .andExpect(status().isOk())
                                .andExpect(jsonPath("$[0].id").value(70))
                                .andExpect(jsonPath("$[0].sentence").value("A sample sentence"));
        }

        @Test
        void testGetWordSentencesNotFound() throws Exception {
                when(wordService.getWordByIdAndUserWithSentences(8L, 1L)).thenReturn(Optional.empty());

                mockMvc.perform(get("/api/words/8/sentences").header("X-User-Id", "1"))
                                .andExpect(status().isNotFound());
        }

    @Test
    void testGetWordsByDate_ReturnsBadRequestWhenHeaderInvalid() throws Exception {
            mockMvc.perform(get("/api/words/date/2026-02-01").header("X-User-Id", "abc"))
                                .andExpect(status().isBadRequest());

            verify(wordService, never()).getWordsByDate(anyLong(), any(LocalDate.class));
    }

        @Test
        void testGetAllDistinctDates() throws Exception {
                when(wordService.getAllDistinctDates(1L)).thenReturn(List.of(LocalDate.of(2026, 2, 1)));

                mockMvc.perform(get("/api/words/dates").header("X-User-Id", "1"))
                                .andExpect(status().isOk())
                                .andExpect(jsonPath("$[0]").value("2026-02-01"));
        }

        @Test
        void testGetWordsByDateRange() throws Exception {
                when(wordService.getWordsByDateRange(eq(1L), eq(LocalDate.of(2026, 1, 1)), eq(LocalDate.of(2026, 1, 2))))
                                .thenReturn(List.of());

                mockMvc.perform(get("/api/words/range")
                                .header("X-User-Id", "1")
                                .param("startDate", "2026-01-01")
                                .param("endDate", "2026-01-02"))
                                .andExpect(status().isOk());

                verify(wordService).getWordsByDateRange(1L, LocalDate.of(2026, 1, 1), LocalDate.of(2026, 1, 2));
        }

        @Test
        void testUpdateWordFound() throws Exception {
                Word updated = new Word();
                updated.setId(9L);
                updated.setEnglishWord("Updated");

                when(wordService.updateWord(eq(9L), any(Word.class), eq(1L))).thenReturn(updated);

                mockMvc.perform(put("/api/words/9")
                                .header("X-User-Id", "1")
                                .contentType(MediaType.APPLICATION_JSON)
                                .content(objectMapper.writeValueAsString(updated)))
                                .andExpect(status().isOk())
                                .andExpect(jsonPath("$.englishWord").value("Updated"));
        }

        @Test
        void testUpdateWordNotFound() throws Exception {
                Word input = new Word();
                input.setEnglishWord("Unknown");
                when(wordService.updateWord(eq(55L), any(Word.class), eq(1L))).thenReturn(null);

                mockMvc.perform(put("/api/words/55")
                                .header("X-User-Id", "1")
                                .contentType(MediaType.APPLICATION_JSON)
                                .content(objectMapper.writeValueAsString(input)))
                                .andExpect(status().isNotFound());
        }

        @Test
        void testDeleteWord() throws Exception {
                mockMvc.perform(delete("/api/words/1")
                                .header("X-User-Id", "1"))
                                .andExpect(status().isOk());
        }

    @Test
    void testDeleteWord_InvalidHeaderReturnsBadRequest() throws Exception {
            mockMvc.perform(delete("/api/words/1")
                                .header("X-User-Id", "oops"))
                                .andExpect(status().isBadRequest());

            verify(wordService, never()).deleteWord(anyLong(), anyLong());
    }

        @Test
        void testAddSentence() throws Exception {
                when(wordService.addSentence(anyLong(), anyString(), anyString(), any(), anyLong()))
                                .thenReturn(new Word());

                mockMvc.perform(post("/api/words/1/sentences")
                                .header("X-User-Id", "1")
                                .contentType(MediaType.APPLICATION_JSON)
                                .content("{\"sentence\":\"Test\", \"translation\":\"Test TR\"}"))
                                .andExpect(status().isOk());
        }

        @Test
        void testAddSentenceNotFound() throws Exception {
                when(wordService.addSentence(anyLong(), anyString(), anyString(), any(), anyLong()))
                                .thenReturn(null);

                mockMvc.perform(post("/api/words/1/sentences")
                                .header("X-User-Id", "1")
                                .contentType(MediaType.APPLICATION_JSON)
                                .content("{\"sentence\":\"Test\", \"translation\":\"Test TR\"}"))
                                .andExpect(status().isNotFound());
        }

        @Test
        void testDeleteSentenceFound() throws Exception {
                when(wordService.deleteSentence(1L, 2L, 1L)).thenReturn(new Word());

                mockMvc.perform(delete("/api/words/1/sentences/2")
                                .header("X-User-Id", "1"))
                                .andExpect(status().isOk());
        }

        @Test
        void testDeleteSentenceNotFound() throws Exception {
                when(wordService.deleteSentence(1L, 3L, 1L)).thenReturn(null);

                mockMvc.perform(delete("/api/words/1/sentences/3")
                                .header("X-User-Id", "1"))
                                .andExpect(status().isNotFound());
        }
}
