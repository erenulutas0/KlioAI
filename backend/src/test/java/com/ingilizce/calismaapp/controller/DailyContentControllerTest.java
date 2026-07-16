package com.ingilizce.calismaapp.controller;

import com.ingilizce.calismaapp.service.DailyExamPackService;
import com.ingilizce.calismaapp.service.DailyReadingService;
import com.ingilizce.calismaapp.service.DailyWritingTopicService;
import com.ingilizce.calismaapp.service.DailyWordsService;
import com.ingilizce.calismaapp.service.AiTokenQuotaService;
import com.ingilizce.calismaapp.repository.UserRepository;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
public class DailyContentControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private DailyWordsService dailyWordsService;

    @MockBean
    private DailyExamPackService dailyExamPackService;

    @MockBean
    private DailyReadingService dailyReadingService;

    @MockBean
    private DailyWritingTopicService dailyWritingTopicService;

    @MockBean
    private AiTokenQuotaService aiTokenQuotaService;

    @MockBean
    private UserRepository userRepository;

    @Test
    void dailyWordsReturnsOkWithWordsArray() throws Exception {
        when(dailyWordsService.getDailyWords(any(LocalDate.class)))
                .thenReturn(List.of(
                        Map.of("id", 1, "word", "resilient"),
                        Map.of("id", 2, "word", "insight")
                ));

        mockMvc.perform(get("/api/content/daily-words")
                        .accept(MediaType.APPLICATION_JSON))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.words").isArray())
                .andExpect(jsonPath("$.words[0].word").value("resilient"));
    }

    @Test
    void dailyExamPackReturnsOkWithDataObject() throws Exception {
        when(dailyExamPackService.getDailyExamPack(any(LocalDate.class), eq("yds")))
                .thenReturn(Map.of("exam", "yds", "date", LocalDate.now().toString(), "topics", List.of()));

        mockMvc.perform(get("/api/content/daily-exam-pack?exam=yds")
                        .accept(MediaType.APPLICATION_JSON))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.data.exam").value("yds"))
                .andExpect(jsonPath("$.data.topics").isArray());
    }

    @Test
    void dailyReadingReturnsForbiddenWhenAiAccessDisabled() throws Exception {
        when(aiTokenQuotaService.getEntitlement(42L))
                .thenReturn(new AiTokenQuotaService.Entitlement(
                        "FREE",
                        false,
                        1500,
                        false,
                        0));
        when(userRepository.findById(42L)).thenReturn(Optional.empty());

        mockMvc.perform(get("/api/content/daily-reading?level=c2")
                        .header("X-User-Id", "42")
                        .accept(MediaType.APPLICATION_JSON))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.upgradeRequired").value(true))
                .andExpect(jsonPath("$.reason").value("ai-access-disabled"));
    }

    @Test
    void dailyReadingNormalizesLevelWhenAiAccessAllowed() throws Exception {
        when(aiTokenQuotaService.getEntitlement(7L))
                .thenReturn(new AiTokenQuotaService.Entitlement(
                        "PREMIUM",
                        true,
                        30000,
                        false,
                        0));
        when(dailyReadingService.getDailyReading(any(LocalDate.class), eq("B1")))
                .thenReturn(Map.of("title", "A clear plan", "text", "Short reading"));

        mockMvc.perform(get("/api/content/daily-reading?level=unknown")
                        .header("X-User-Id", "7")
                        .accept(MediaType.APPLICATION_JSON))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.level").value("B1"))
                .andExpect(jsonPath("$.data.title").value("A clear plan"));
    }

    @Test
    void dailyWritingTopicRejectsInvalidUserContext() throws Exception {
        mockMvc.perform(get("/api/content/daily-writing-topic?level=a2")
                        .header("X-User-Id", "0")
                        .accept(MediaType.APPLICATION_JSON))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.error").value("Invalid user context"));
    }

    @Test
    void dailyWritingTopicReturnsPayloadWhenAiAccessAllowed() throws Exception {
        when(aiTokenQuotaService.getEntitlement(9L))
                .thenReturn(new AiTokenQuotaService.Entitlement(
                        "FREE_TRIAL_7D",
                        true,
                        5000,
                        true,
                        6));
        when(dailyWritingTopicService.getDailyWritingTopic(any(LocalDate.class), eq("A2")))
                .thenReturn(Map.of("topic", "Write a short email", "wordCount", 80));

        mockMvc.perform(get("/api/content/daily-writing-topic?level=a2")
                        .header("X-User-Id", "9")
                        .accept(MediaType.APPLICATION_JSON))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.level").value("A2"))
                .andExpect(jsonPath("$.data.topic").value("Write a short email"));
    }
}
