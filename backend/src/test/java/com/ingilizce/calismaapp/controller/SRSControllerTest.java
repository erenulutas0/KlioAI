package com.ingilizce.calismaapp.controller;

import com.ingilizce.calismaapp.entity.Word;
import com.ingilizce.calismaapp.service.SRSService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;

import java.util.ArrayList;
import java.util.HashMap;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@TestPropertySource(properties = {
        "GROQ_API_KEY=dummy-key",
        "spring.datasource.url=jdbc:h2:mem:srsdb;DB_CLOSE_DELAY=-1;MODE=PostgreSQL",
        "spring.datasource.driver-class-name=org.h2.Driver"
})
public class SRSControllerTest {

    private static final String USER_ID_HEADER = "X-User-Id";
    private static final Long USER_ID = 1L;

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private SRSService srsService;

    @Test
    void testGetDueWords() throws Exception {
        when(srsService.getWordsForReview(USER_ID)).thenReturn(new ArrayList<>());

        mockMvc.perform(get("/api/srs/review-words")
                .header(USER_ID_HEADER, USER_ID))
                .andExpect(status().isOk());
    }

    @Test
    void testGetDueWords_ShouldReturnInternalServerError_WhenServiceFails() throws Exception {
        when(srsService.getWordsForReview(USER_ID)).thenThrow(new RuntimeException("db fail"));

        mockMvc.perform(get("/api/srs/review-words")
                .header(USER_ID_HEADER, USER_ID))
                .andExpect(status().isInternalServerError());
    }

    @Test
    void testEvaluateWord() throws Exception {
        // The controller now passes the originating screen and the answer time through to
        // the review log, so the five-argument overload is the one actually called.
        when(srsService.submitReview(eq(USER_ID), eq(1L), eq(4), any(), any()))
                .thenReturn(new Word());

        mockMvc.perform(post("/api/srs/submit-review")
                .header(USER_ID_HEADER, USER_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"wordId\":1, \"quality\":4}"))
                .andExpect(status().isOk());
    }

    @Test
    void testEvaluateWord_ShouldReturnBadRequest_WhenInputIsInvalid() throws Exception {
        when(srsService.submitReview(anyLong(), anyLong(), anyInt(), any(), any()))
                .thenThrow(new IllegalArgumentException("invalid"));

        mockMvc.perform(post("/api/srs/submit-review")
                .header(USER_ID_HEADER, USER_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"wordId\":1, \"quality\":4}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void testEvaluateWord_ShouldReturnInternalServerError_WhenServiceFails() throws Exception {
        when(srsService.submitReview(anyLong(), anyLong(), anyInt(), any(), any()))
                .thenThrow(new RuntimeException("unexpected"));

        mockMvc.perform(post("/api/srs/submit-review")
                .header(USER_ID_HEADER, USER_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"wordId\":1, \"quality\":4}"))
                .andExpect(status().isInternalServerError());
    }

    @Test
    void testGetStats() throws Exception {
        when(srsService.getStats(USER_ID)).thenReturn(new HashMap<>());

        mockMvc.perform(get("/api/srs/stats")
                .header(USER_ID_HEADER, USER_ID))
                .andExpect(status().isOk());
    }

    @Test
    void testGetStats_ShouldReturnInternalServerError_WhenServiceFails() throws Exception {
        when(srsService.getStats(USER_ID)).thenThrow(new RuntimeException("stats fail"));

        mockMvc.perform(get("/api/srs/stats")
                .header(USER_ID_HEADER, USER_ID))
                .andExpect(status().isInternalServerError());
    }
}
