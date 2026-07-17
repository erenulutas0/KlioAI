package com.ingilizce.calismaapp.controller;

import com.ingilizce.calismaapp.security.CurrentUserContext;
import com.ingilizce.calismaapp.service.AiTokenQuotaService;
import com.ingilizce.calismaapp.service.GrammarCheckService;
import com.ingilizce.calismaapp.service.ProgressService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;

import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.nullable;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@TestPropertySource(properties = {
        "GROQ_API_KEY=dummy-key",
        "spring.datasource.url=jdbc:h2:mem:grammardb;DB_CLOSE_DELAY=-1;MODE=PostgreSQL",
        "spring.datasource.driver-class-name=org.h2.Driver"
})
class GrammarControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private GrammarCheckService grammarCheckService;

    @MockBean
    private ProgressService progressService;

    @MockBean
    private CurrentUserContext currentUserContext;

    @MockBean
    private AiTokenQuotaService aiTokenQuotaService;

    @BeforeEach
    void setUp() {
        when(aiTokenQuotaService.check(any(), anyString(), nullable(String.class), anyString()))
                .thenReturn(AiTokenQuotaService.Decision.allowed());
    }

    @Test
    void checkGrammarReturnsOk() throws Exception {
        when(grammarCheckService.checkGrammar("I goes to school"))
                .thenReturn(Map.of("hasErrors", true, "errorCount", 1, "errors", List.of(Map.of("message", "err"))));

        mockMvc.perform(post("/api/grammar/check")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"sentence\":\"I goes to school\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.hasErrors").value(true))
                .andExpect(jsonPath("$.errorCount").value(1));
    }

    @Test
    void checkGrammarReturns429_WhenDailyTokenQuotaExceeded() throws Exception {
        when(aiTokenQuotaService.check(any(), eq("grammar-check"), nullable(String.class), anyString()))
                .thenReturn(AiTokenQuotaService.Decision.blocked("daily-token-quota", 300, 50000, 50000));

        mockMvc.perform(post("/api/grammar/check")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"sentence\":\"I goes to school\"}"))
                .andExpect(status().isTooManyRequests())
                .andExpect(jsonPath("$.reason").value("daily-token-quota"));

        verify(grammarCheckService, never()).checkGrammar(anyString());
    }

    @Test
    void checkGrammarConsumesEstimatedTokens_OnSuccess() throws Exception {
        when(currentUserContext.getCurrentUserId()).thenReturn(Optional.of(1L));
        when(aiTokenQuotaService.check(any(), eq("grammar-check"), nullable(String.class), anyString()))
                .thenReturn(AiTokenQuotaService.Decision.allowed());
        when(grammarCheckService.checkGrammar("I goes to school"))
                .thenReturn(Map.of("hasErrors", true, "errorCount", 1, "errors", List.of(Map.of("message", "err"))));

        mockMvc.perform(post("/api/grammar/check")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"sentence\":\"I goes to school\"}"))
                .andExpect(status().isOk());

        verify(aiTokenQuotaService).consume(eq(1L), eq("grammar-check"), eq(400L), nullable(String.class), anyString());
    }

    @Test
    void checkGrammarCreditsDailyStreakForAuthenticatedUser() throws Exception {
        when(currentUserContext.getCurrentUserId()).thenReturn(Optional.of(1L));
        when(grammarCheckService.checkGrammar("I goes to school"))
                .thenReturn(Map.of("hasErrors", true, "errorCount", 1, "errors", List.of(Map.of("message", "err"))));

        mockMvc.perform(post("/api/grammar/check")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"sentence\":\"I goes to school\"}"))
                .andExpect(status().isOk());

        verify(progressService).updateStreak(1L);
    }

    @Test
    void checkGrammarReturnsBadRequestForEmptySentence() throws Exception {
        mockMvc.perform(post("/api/grammar/check")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"sentence\":\"   \"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Empty sentence provided"));
    }

    @Test
    void checkGrammarReturnsInternalServerErrorWhenServiceThrows() throws Exception {
        when(currentUserContext.getCurrentUserId()).thenReturn(Optional.of(1L));
        when(grammarCheckService.checkGrammar(any())).thenThrow(new RuntimeException("broken"));

        mockMvc.perform(post("/api/grammar/check")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"sentence\":\"Test\"}"))
                .andExpect(status().isInternalServerError())
                .andExpect(jsonPath("$.message").value("Grammar check failed: broken"));

        verify(progressService, never()).updateStreak(anyLong());
    }

    @Test
    void checkMultipleSentencesReturnsOk() throws Exception {
        when(grammarCheckService.checkMultipleSentences(List.of("One", "Two")))
                .thenReturn(Map.of("One", List.of(Map.of("message", "m1"))));

        mockMvc.perform(post("/api/grammar/check-multiple")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"sentences\":[\"One\",\"Two\"]}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.One[0].message").value("m1"));
    }

    @Test
    void checkMultipleSentencesCreditsDailyStreakForAuthenticatedUser() throws Exception {
        when(currentUserContext.getCurrentUserId()).thenReturn(Optional.of(1L));
        when(grammarCheckService.checkMultipleSentences(List.of("One", "Two")))
                .thenReturn(Map.of("One", List.of(Map.of("message", "m1"))));

        mockMvc.perform(post("/api/grammar/check-multiple")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"sentences\":[\"One\",\"Two\"]}"))
                .andExpect(status().isOk());

        verify(progressService).updateStreak(1L);
    }

    @Test
    void checkMultipleSentencesReturns429_WhenDailyTokenQuotaExceeded() throws Exception {
        when(aiTokenQuotaService.check(any(), eq("grammar-check-multiple"), nullable(String.class), anyString()))
                .thenReturn(AiTokenQuotaService.Decision.blocked("daily-token-quota", 300, 50000, 50000));

        mockMvc.perform(post("/api/grammar/check-multiple")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"sentences\":[\"One\",\"Two\"]}"))
                .andExpect(status().isTooManyRequests());

        verify(grammarCheckService, never()).checkMultipleSentences(any());
    }

    @Test
    void checkMultipleSentencesConsumesTokensScaledBySentenceCount_OnSuccess() throws Exception {
        when(currentUserContext.getCurrentUserId()).thenReturn(Optional.of(1L));
        when(aiTokenQuotaService.check(any(), eq("grammar-check-multiple"), nullable(String.class), anyString()))
                .thenReturn(AiTokenQuotaService.Decision.allowed());
        when(grammarCheckService.checkMultipleSentences(List.of("One", "Two")))
                .thenReturn(Map.of("One", List.of(Map.of("message", "m1"))));

        mockMvc.perform(post("/api/grammar/check-multiple")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"sentences\":[\"One\",\"Two\"]}"))
                .andExpect(status().isOk());

        verify(aiTokenQuotaService).consume(eq(1L), eq("grammar-check-multiple"), eq(800L), nullable(String.class), anyString());
    }

    @Test
    void checkMultipleSentencesReturnsBadRequestForEmptyList() throws Exception {
        mockMvc.perform(post("/api/grammar/check-multiple")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"sentences\":[]}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void checkMultipleSentencesReturnsInternalServerErrorWhenServiceThrows() throws Exception {
        when(currentUserContext.getCurrentUserId()).thenReturn(Optional.of(1L));
        when(grammarCheckService.checkMultipleSentences(any())).thenThrow(new RuntimeException("broken"));

        mockMvc.perform(post("/api/grammar/check-multiple")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"sentences\":[\"One\"]}"))
                .andExpect(status().isInternalServerError());

        verify(progressService, never()).updateStreak(anyLong());
    }

    @Test
    void getStatusReturnsOk() throws Exception {
        when(grammarCheckService.isEnabled()).thenReturn(true);

        mockMvc.perform(get("/api/grammar/status"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.enabled").value(true))
                .andExpect(jsonPath("$.service").value("AI Grammar Checker"))
                .andExpect(jsonPath("$.targetLanguage").value("English"))
                .andExpect(jsonPath("$.strategy").value("english-learning-only"));
    }

    @Test
    void toggleGrammarCheckUpdatesValue() throws Exception {
        when(grammarCheckService.isEnabled()).thenReturn(true);

        mockMvc.perform(post("/api/grammar/toggle")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"enabled\":true}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.enabled").value(true))
                .andExpect(jsonPath("$.message").value("Grammar checking enabled"));

        verify(grammarCheckService).setEnabled(eq(true));
    }

    @Test
    void toggleGrammarCheckHandlesMissingEnabledField() throws Exception {
        when(grammarCheckService.isEnabled()).thenReturn(false);

        mockMvc.perform(post("/api/grammar/toggle")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.enabled").value(false))
                .andExpect(jsonPath("$.message").value("Grammar checking disabled"));

        verify(grammarCheckService, never()).setEnabled(anyBoolean());
    }
}
