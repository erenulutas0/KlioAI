package com.ingilizce.calismaapp.controller;

import com.ingilizce.calismaapp.service.AiRateLimitService;
import com.ingilizce.calismaapp.service.PiperTtsService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.nullable;
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
        "spring.datasource.url=jdbc:h2:mem:ttsdb;DB_CLOSE_DELAY=-1;MODE=PostgreSQL",
        "spring.datasource.driver-class-name=org.h2.Driver",
        "app.tts.max-text-length=400"
})
class TtsControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private PiperTtsService piperTtsService;

    @MockBean
    private AiRateLimitService aiRateLimitService;

    @BeforeEach
    void allowRateLimitByDefault() {
        when(aiRateLimitService.checkAndConsume(nullable(Long.class), anyString(), eq("tts-synthesize")))
                .thenReturn(AiRateLimitService.Decision.allowed());
    }

    @Test
    void synthesizeReturnsBadRequestWhenTextMissing() throws Exception {
        mockMvc.perform(post("/api/tts/synthesize")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"voice\":\"amy\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("Text is required"));
    }

    @Test
    void synthesizeReturnsServiceUnavailableWhenPiperUnavailable() throws Exception {
        when(piperTtsService.isAvailable()).thenReturn(false);

        mockMvc.perform(post("/api/tts/synthesize")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"text\":\"hello\",\"voice\":\"amy\"}"))
                .andExpect(status().isServiceUnavailable())
                .andExpect(jsonPath("$.available").value(false));
    }

    @Test
    void synthesizeReturnsAudioWhenSuccessful() throws Exception {
        when(piperTtsService.isAvailable()).thenReturn(true);
        when(piperTtsService.synthesizeSpeech(eq("hello world"), eq("amy"))).thenReturn("BASE64_AUDIO");

        mockMvc.perform(post("/api/tts/synthesize")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"text\":\"  hello world  \",\"voice\":\"amy\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.audio").value("BASE64_AUDIO"));

        verify(piperTtsService).synthesizeSpeech("hello world", "amy");
    }

    @Test
    void synthesizeReturnsInternalServerErrorWhenSynthesisFails() throws Exception {
        when(piperTtsService.isAvailable()).thenReturn(true);
        when(piperTtsService.synthesizeSpeech(anyString(), anyString())).thenThrow(new RuntimeException("failed"));

        mockMvc.perform(post("/api/tts/synthesize")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"text\":\"hello\",\"voice\":\"amy\"}"))
                .andExpect(status().isInternalServerError())
                .andExpect(jsonPath("$.error").value("Failed to synthesize: failed"));
    }

    @Test
    void synthesizeRejectsTextOverMaxLength() throws Exception {
        String longText = "a".repeat(401);

        mockMvc.perform(post("/api/tts/synthesize")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"text\":\"" + longText + "\",\"voice\":\"amy\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("Text is too long for speech synthesis"))
                .andExpect(jsonPath("$.maxTextLength").value(400));

        verify(piperTtsService, never()).synthesizeSpeech(anyString(), anyString());
    }

    @Test
    void synthesizeReturns429WhenRateLimited() throws Exception {
        when(aiRateLimitService.checkAndConsume(nullable(Long.class), anyString(), eq("tts-synthesize")))
                .thenReturn(new AiRateLimitService.Decision(true, 42, "scope-window", 0, 0));

        mockMvc.perform(post("/api/tts/synthesize")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"text\":\"hello\",\"voice\":\"amy\"}"))
                .andExpect(status().isTooManyRequests())
                .andExpect(jsonPath("$.error").value("TTS request limit reached. Please try again later."))
                .andExpect(jsonPath("$.reason").value("scope-window"))
                .andExpect(jsonPath("$.retryAfterSeconds").value(42));

        verify(piperTtsService, never()).synthesizeSpeech(anyString(), anyString());
    }

    @Test
    void synthesizeUsesUserIdHeaderForRateLimitSubject() throws Exception {
        when(piperTtsService.isAvailable()).thenReturn(true);
        when(piperTtsService.synthesizeSpeech(anyString(), any())).thenReturn("BASE64_AUDIO");

        mockMvc.perform(post("/api/tts/synthesize")
                .header("X-User-Id", "7")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"text\":\"hello\",\"voice\":\"amy\"}"))
                .andExpect(status().isOk());

        verify(aiRateLimitService).checkAndConsume(eq(7L), anyString(), eq("tts-synthesize"));
    }

    @Test
    void getStatusReturnsAvailabilityAndVoices() throws Exception {
        when(piperTtsService.isAvailable()).thenReturn(true);
        when(piperTtsService.getSupportedVoices()).thenReturn(new String[] { "default", "ryan" });

        mockMvc.perform(get("/api/tts/status"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.available").value(true))
                .andExpect(jsonPath("$.voices[0]").value("default"))
                .andExpect(jsonPath("$.voices[1]").value("ryan"));
    }
}
