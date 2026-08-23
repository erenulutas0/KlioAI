package com.ingilizce.calismaapp.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ingilizce.calismaapp.entity.Sentence;
import com.ingilizce.calismaapp.entity.Word;
import com.ingilizce.calismaapp.entity.WordMeaning;
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
                // The controller forwards the optional meaningId (V028); the shipped client
                // never sends one, so it arrives as null.
                when(wordService.addSentence(anyLong(), anyString(), anyString(), any(), anyLong(), isNull()))
                                .thenReturn(new Word());

                mockMvc.perform(post("/api/words/1/sentences")
                                .header("X-User-Id", "1")
                                .contentType(MediaType.APPLICATION_JSON)
                                .content("{\"sentence\":\"Test\", \"translation\":\"Test TR\"}"))
                                .andExpect(status().isOk());
        }

        @Test
        void testAddSentenceNotFound() throws Exception {
                when(wordService.addSentence(anyLong(), anyString(), anyString(), any(), anyLong(), isNull()))
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
        // ---- V028: meanings and profile scoping ----

        private static Word wordWithMeaning(long wordId, long meaningId, String translation) {
                Word word = new Word();
                word.setId(wordId);
                word.setUserId(1L);
                word.setEnglishWord("bank");
                word.setTurkishMeaning(translation);
                word.setOrigin("manual");
                WordMeaning meaning = new WordMeaning(null, translation, null, 0);
                meaning.setId(meaningId);
                word.addMeaning(meaning);
                return word;
        }

        @Test
        void getAllWords_WithLanguageProfileId_ScopesToThatProfile() throws Exception {
                when(wordService.getWordsPage(eq(1L), eq(600L), eq(0), eq(100)))
                                .thenReturn(new PageImpl<>(new ArrayList<>(), PageRequest.of(0, 100), 0));

                mockMvc.perform(get("/api/words")
                                .header("X-User-Id", "1")
                                .param("languageProfileId", "600"))
                                .andExpect(status().isOk());

                verify(wordService).getWordsPage(1L, 600L, 0, 100);
                verify(wordService, never()).getWordsPage(anyLong(), anyInt(), anyInt());
        }

        @Test
        void getAllWords_WithAProfileThatIsNotTheCallers_IsNotFound() throws Exception {
                when(wordService.getWordsPage(eq(1L), eq(601L), anyInt(), anyInt()))
                                .thenThrow(new java.util.NoSuchElementException("Language profile not found: 601"));

                mockMvc.perform(get("/api/words")
                                .header("X-User-Id", "1")
                                .param("languageProfileId", "601"))
                                .andExpect(status().isNotFound());
        }

        @Test
        void wordJson_CarriesTheNewKeys_NextToTheOldOnes() throws Exception {
                Word word = wordWithMeaning(3L, 30L, "banka");
                word.setSentences(new ArrayList<>());
                when(wordService.getWordByIdAndUserWithSentences(3L, 1L)).thenReturn(Optional.of(word));

                mockMvc.perform(get("/api/words/3").header("X-User-Id", "1"))
                                .andExpect(status().isOk())
                                .andExpect(jsonPath("$.englishWord").value("bank"))
                                .andExpect(jsonPath("$.turkishMeaning").value("banka"))
                                .andExpect(jsonPath("$.sourceMeaning").value("banka"))
                                .andExpect(jsonPath("$.origin").value("manual"))
                                .andExpect(jsonPath("$.languageProfileId").value(org.hamcrest.Matchers.nullValue()))
                                .andExpect(jsonPath("$.meanings[0].id").value(30))
                                .andExpect(jsonPath("$.meanings[0].translation").value("banka"))
                                .andExpect(jsonPath("$.meanings[0].position").value(0))
                                .andExpect(jsonPath("$.meanings[0].word").doesNotExist());
        }

        @Test
        void addSentence_PassesMeaningIdThrough() throws Exception {
                when(wordService.addSentence(eq(1L), eq("Test"), eq("Test TR"), isNull(), eq(1L), eq(30L)))
                                .thenReturn(wordWithMeaning(1L, 30L, "banka"));

                mockMvc.perform(post("/api/words/1/sentences")
                                .header("X-User-Id", "1")
                                .contentType(MediaType.APPLICATION_JSON)
                                .content("{\"sentence\":\"Test\", \"translation\":\"Test TR\", \"meaningId\": 30}"))
                                .andExpect(status().isOk());

                verify(wordService).addSentence(1L, "Test", "Test TR", null, 1L, 30L);
        }

        @Test
        void addSentence_WithAMeaningOfAnotherWord_IsBadRequest() throws Exception {
                when(wordService.addSentence(anyLong(), anyString(), anyString(), any(), anyLong(), eq(99L)))
                                .thenThrow(new IllegalArgumentException("meaningId does not belong to this word: 99"));

                mockMvc.perform(post("/api/words/1/sentences")
                                .header("X-User-Id", "1")
                                .contentType(MediaType.APPLICATION_JSON)
                                .content("{\"sentence\":\"Test\", \"translation\":\"Test TR\", \"meaningId\": 99}"))
                                .andExpect(status().isBadRequest());
        }

        @Test
        void addMeaning_Returns201WithTheWord() throws Exception {
                when(wordService.addMeaning(1L, 1L, "kıyı", "shore"))
                                .thenReturn(wordWithMeaning(1L, 30L, "banka"));

                mockMvc.perform(post("/api/words/1/meanings")
                                .header("X-User-Id", "1")
                                .contentType(MediaType.APPLICATION_JSON)
                                .content("{\"translation\":\"kıyı\",\"definition\":\"shore\"}"))
                                .andExpect(status().isCreated())
                                .andExpect(jsonPath("$.id").value(1))
                                .andExpect(jsonPath("$.meanings[0].id").value(30));
        }

        @Test
        void addMeaning_OnAWordThatIsNotTheCallers_IsNotFound() throws Exception {
                when(wordService.addMeaning(eq(5L), eq(1L), any(), any()))
                                .thenThrow(new java.util.NoSuchElementException("Word not found: 5"));

                mockMvc.perform(post("/api/words/5/meanings")
                                .header("X-User-Id", "1")
                                .contentType(MediaType.APPLICATION_JSON)
                                .content("{\"translation\":\"kıyı\"}"))
                                .andExpect(status().isNotFound());
        }

        @Test
        void addMeaning_WithABlankTranslation_IsBadRequest() throws Exception {
                when(wordService.addMeaning(eq(1L), eq(1L), any(), any()))
                                .thenThrow(new IllegalArgumentException("translation is required"));

                mockMvc.perform(post("/api/words/1/meanings")
                                .header("X-User-Id", "1")
                                .contentType(MediaType.APPLICATION_JSON)
                                .content("{\"translation\":\"  \"}"))
                                .andExpect(status().isBadRequest());
        }

        @Test
        void updateMeaning_Returns200WithTheWord_AndNullForFieldsNotSent() throws Exception {
                when(wordService.updateMeaning(1L, 30L, 1L, "banka (finans)", null))
                                .thenReturn(wordWithMeaning(1L, 30L, "banka (finans)"));

                mockMvc.perform(put("/api/words/1/meanings/30")
                                .header("X-User-Id", "1")
                                .contentType(MediaType.APPLICATION_JSON)
                                .content("{\"translation\":\"banka (finans)\"}"))
                                .andExpect(status().isOk())
                                .andExpect(jsonPath("$.meanings[0].translation").value("banka (finans)"));

                verify(wordService).updateMeaning(1L, 30L, 1L, "banka (finans)", null);
        }

        @Test
        void updateMeaning_Unknown_IsNotFound() throws Exception {
                when(wordService.updateMeaning(eq(1L), eq(99L), eq(1L), any(), any()))
                                .thenThrow(new java.util.NoSuchElementException("Meaning not found: 99"));

                mockMvc.perform(put("/api/words/1/meanings/99")
                                .header("X-User-Id", "1")
                                .contentType(MediaType.APPLICATION_JSON)
                                .content("{\"translation\":\"x\"}"))
                                .andExpect(status().isNotFound());
        }

        @Test
        void deleteMeaning_Returns200WithTheWord() throws Exception {
                when(wordService.deleteMeaning(1L, 31L, 1L)).thenReturn(wordWithMeaning(1L, 30L, "banka"));

                mockMvc.perform(delete("/api/words/1/meanings/31").header("X-User-Id", "1"))
                                .andExpect(status().isOk())
                                .andExpect(jsonPath("$.meanings.length()").value(1));
        }

        @Test
        void deleteMeaning_OfTheLastMeaning_IsBadRequestWithAMessage() throws Exception {
                when(wordService.deleteMeaning(1L, 30L, 1L)).thenThrow(new WordService.LastMeaningException());

                mockMvc.perform(delete("/api/words/1/meanings/30").header("X-User-Id", "1"))
                                .andExpect(status().isBadRequest())
                                .andExpect(jsonPath("$.error").value("A word must keep at least one meaning"));
        }

        @Test
        void deleteMeaning_Unknown_IsNotFound() throws Exception {
                when(wordService.deleteMeaning(1L, 99L, 1L))
                                .thenThrow(new java.util.NoSuchElementException("Meaning not found: 99"));

                mockMvc.perform(delete("/api/words/1/meanings/99").header("X-User-Id", "1"))
                                .andExpect(status().isNotFound());
        }
}
