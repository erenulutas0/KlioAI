package com.ingilizce.calismaapp.controller;

import com.ingilizce.calismaapp.repository.SentencePracticeRepository;
import com.ingilizce.calismaapp.repository.SentenceRepository;
import com.ingilizce.calismaapp.repository.WordRepository;
import com.ingilizce.calismaapp.repository.WordReviewRepository;
import com.ingilizce.calismaapp.security.CurrentUserContext;
import com.ingilizce.calismaapp.security.JwtAuthenticationFilter;
import com.ingilizce.calismaapp.security.UserHeaderConsistencyFilter;
import com.ingilizce.calismaapp.service.AiRateLimitService;
import com.ingilizce.calismaapp.service.AiTokenQuotaService;
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
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
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

    @MockBean
    private AiTokenQuotaService aiTokenQuotaService;

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

    @Test
    void aiAbuseStatus_ShouldReturnActiveStatus() throws Exception {
        when(aiRateLimitService.getAbusePenaltyStatus(4L, "10.0.0.4"))
                .thenReturn(new AiRateLimitService.AbusePenaltyStatus(
                        true, true, true, false, 30, 0, "u:4", "ip:10.0.0.4"));

        mockMvc.perform(post("/api/admin/ai-abuse/status")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"userId\":4,\"clientIp\":\"10.0.0.4\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.userPenaltyActive").value(true))
                .andExpect(jsonPath("$.ipPenaltyActive").value(false))
                .andExpect(jsonPath("$.anyPenaltyActive").value(true))
                .andExpect(jsonPath("$.userRetryAfterSeconds").value(30))
                .andExpect(jsonPath("$.userSubject").value("u:4"));

        verify(aiRateLimitService).getAbusePenaltyStatus(4L, "10.0.0.4");
    }

    @Test
    void aiAbuseStats_ShouldReturnSnapshot() throws Exception {
        when(aiRateLimitService.getAbuseStats())
                .thenReturn(new AiRateLimitService.AbuseStats(
                        true,
                        true,
                        "memory",
                        false,
                        true,
                        900,
                        java.util.List.of(30L, 60L, 150L),
                        3,
                        1,
                        1,
                        20,
                        10));

        mockMvc.perform(get("/api/admin/ai-abuse/stats"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.enabled").value(true))
                .andExpect(jsonPath("$.redisEnabled").value(true))
                .andExpect(jsonPath("$.memoryPenaltySubjects").value(1))
                .andExpect(jsonPath("$.memoryActivePenaltySubjects").value(1))
                .andExpect(jsonPath("$.configuredScopeCount").value(3));

        verify(aiRateLimitService).getAbuseStats();
    }

    @Test
    void aiUsageStats_ShouldReturnCostSnapshot() throws Exception {
        when(aiTokenQuotaService.getUsageStats())
                .thenReturn(new AiTokenQuotaService.UsageStats(
                        true,
                        true,
                        "deny",
                        false,
                        "2026-05-03",
                        1500,
                        5000,
                        30000,
                        60000,
                        0.10,
                        2,
                        3,
                        12500,
                        4,
                        5,
                        22000,
                        34500,
                        0.0035));

        mockMvc.perform(get("/api/admin/ai-usage/stats"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.enabled").value(true))
                .andExpect(jsonPath("$.dateUtc").value("2026-05-03"))
                .andExpect(jsonPath("$.totalTokensUsed").value(34500))
                .andExpect(jsonPath("$.quotas.premiumDailyTokenQuotaPerUser").value(30000))
                .andExpect(jsonPath("$.memory.tokensUsed").value(12500))
                .andExpect(jsonPath("$.redis.tokensUsed").value(22000))
                .andExpect(jsonPath("$.cost.estimatedCostUsdPerMillionTokens").value(0.10))
                .andExpect(jsonPath("$.cost.estimatedCostUsd").value(0.0035));

        verify(aiTokenQuotaService).getUsageStats();
    }
}
