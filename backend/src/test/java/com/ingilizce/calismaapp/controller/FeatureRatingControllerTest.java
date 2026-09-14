package com.ingilizce.calismaapp.controller;

import com.ingilizce.calismaapp.service.FeatureRatingService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;

import java.util.Map;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.ArgumentMatchers.nullable;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@TestPropertySource(properties = {
        "GROQ_API_KEY=dummy-key",
        "spring.datasource.url=jdbc:h2:mem:ratingsdb;DB_CLOSE_DELAY=-1;MODE=PostgreSQL",
        "spring.datasource.driver-class-name=org.h2.Driver"
})
class FeatureRatingControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private FeatureRatingService service;

    @Test
    void aRatingIsCreated_WithItsContextStoredAsJson() throws Exception {
        when(service.submit(eq(7L), eq("TUTOR"), eq(4), eq("Nice"), eq("restaurant_order"),
                eq("tr"), eq("1.4.1+484"), eq("{\"turns\":6}")))
                .thenReturn(Map.of("id", 1, "feature", "TUTOR", "stars", 4));

        mockMvc.perform(post("/api/feedback/ratings")
                        .header("X-User-Id", "7")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"feature\":\"TUTOR\",\"stars\":4,\"note\":\"Nice\","
                                + "\"sceneId\":\"restaurant_order\",\"locale\":\"tr\","
                                + "\"appVersion\":\"1.4.1+484\",\"context\":{\"turns\":6}}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.stars").value(4));
    }

    @Test
    void starsThatAreNotAWholeNumberAreNotARating() throws Exception {
        when(service.submit(anyLong(), nullable(String.class), isNull(), nullable(String.class),
                nullable(String.class), nullable(String.class), nullable(String.class), nullable(String.class)))
                .thenThrow(new IllegalArgumentException("INVALID_STARS"));

        mockMvc.perform(post("/api/feedback/ratings")
                        .header("X-User-Id", "7")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"feature\":\"TUTOR\",\"stars\":4.5}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void theDailyCeilingIsA429() throws Exception {
        when(service.submit(anyLong(), nullable(String.class), anyInt(), nullable(String.class),
                nullable(String.class), nullable(String.class), nullable(String.class), nullable(String.class)))
                .thenThrow(new IllegalStateException("DAILY_LIMIT_REACHED"));

        mockMvc.perform(post("/api/feedback/ratings")
                        .header("X-User-Id", "7")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"feature\":\"TUTOR\",\"stars\":5}"))
                .andExpect(status().isTooManyRequests());
    }

    @Test
    void aRatingWithoutAUserIsRefused() throws Exception {
        mockMvc.perform(post("/api/feedback/ratings")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"feature\":\"TUTOR\",\"stars\":5}"))
                .andExpect(status().is4xxClientError());

        verify(service, never()).submit(any(), any(), any(), any(), any(), any(), any(), any());
    }
}
