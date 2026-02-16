package com.ingilizce.calismaapp.controller;

import com.ingilizce.calismaapp.repository.SentencePracticeRepository;
import com.ingilizce.calismaapp.repository.SentenceRepository;
import com.ingilizce.calismaapp.repository.WordRepository;
import com.ingilizce.calismaapp.repository.WordReviewRepository;
import com.ingilizce.calismaapp.security.CurrentUserContext;
import com.ingilizce.calismaapp.security.JwtAuthenticationFilter;
import com.ingilizce.calismaapp.security.UserHeaderConsistencyFilter;
import com.ingilizce.calismaapp.service.AiRateLimitService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(controllers = AdminController.class)
@AutoConfigureMockMvc(addFilters = false)
class AdminControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private WordReviewRepository wordReviewRepository;

    @MockBean
    private SentencePracticeRepository sentencePracticeRepository;

    @MockBean
    private SentenceRepository sentenceRepository;

    @MockBean
    private WordRepository wordRepository;

    @MockBean
    private CurrentUserContext currentUserContext;

    @MockBean
    private JwtAuthenticationFilter jwtAuthenticationFilter;

    @MockBean
    private UserHeaderConsistencyFilter userHeaderConsistencyFilter;

    @MockBean
    private AiRateLimitService aiRateLimitService;

    @Test
    void resetData_ShouldDeleteRepositoriesAndReturnSuccessMessage() throws Exception {
        mockMvc.perform(post("/api/admin/reset-data"))
                .andExpect(status().isOk())
                .andExpect(content().string("Mock data (Words, Sentences, Reviews) reset successful."));

        verify(wordReviewRepository).deleteAll();
        verify(sentencePracticeRepository).deleteAll();
        verify(sentenceRepository).deleteAll();
        verify(wordRepository).deleteAll();
    }

    @Test
    void resetData_ShouldReturnErrorMessage_WhenDeleteFails() throws Exception {
        doThrow(new RuntimeException("db-fail")).when(wordReviewRepository).deleteAll();

        mockMvc.perform(post("/api/admin/reset-data"))
                .andExpect(status().isOk())
                .andExpect(content().string("Error resetting data: db-fail"));
    }

    @Test
    void clearAiAbusePenalty_ShouldReturnSuccess_WhenUserIdProvided() throws Exception {
        when(aiRateLimitService.clearAbusePenalty(4L, null))
                .thenReturn(new AiRateLimitService.UnbanResult(
                        true, false, true, false, "u:4", null));

        mockMvc.perform(post("/api/admin/ai-abuse/unban")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"userId\":4}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.userPenaltyCleared").value(true))
                .andExpect(jsonPath("$.ipPenaltyCleared").value(false))
                .andExpect(jsonPath("$.userSubject").value("u:4"));

        verify(aiRateLimitService).clearAbusePenalty(4L, null);
    }

    @Test
    void clearAiAbusePenalty_ShouldReturnBadRequest_WhenPayloadMissingTargets() throws Exception {
        mockMvc.perform(post("/api/admin/ai-abuse/unban")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void clearAiAbusePenalty_ShouldReturnForbidden_WhenAdminRoleMissing() throws Exception {
        when(currentUserContext.shouldEnforceAuthz()).thenReturn(true);
        when(currentUserContext.hasRole("ADMIN")).thenReturn(false);

        mockMvc.perform(post("/api/admin/ai-abuse/unban")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"userId\":4}"))
                .andExpect(status().isForbidden());
    }
}
