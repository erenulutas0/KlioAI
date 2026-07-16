package com.ingilizce.calismaapp.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ingilizce.calismaapp.config.GooglePlayRtdnProperties;
import com.ingilizce.calismaapp.service.GooglePlayRtdnService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.util.Map;

import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class GooglePlayRtdnControllerTest {

    private final ObjectMapper objectMapper = new ObjectMapper();
    private GooglePlayRtdnProperties properties;
    private GooglePlayRtdnService rtdnService;
    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        properties = new GooglePlayRtdnProperties();
        properties.setEnabled(true);
        properties.setSharedSecret("secret-1");
        rtdnService = mock(GooglePlayRtdnService.class);
        mockMvc = MockMvcBuilders
                .standaloneSetup(new GooglePlayRtdnController(properties, rtdnService))
                .build();
    }

    @Test
    void receive_shouldRejectMissingSecretWhenConfigured() throws Exception {
        mockMvc.perform(post("/api/subscription/google-play/rtdn")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(envelope())))
                .andExpect(status().isUnauthorized());

        verifyNoInteractions(rtdnService);
    }

    @Test
    void receive_shouldProcessWhenHeaderSecretMatches() throws Exception {
        mockMvc.perform(post("/api/subscription/google-play/rtdn")
                        .header("X-KlioAI-RTDN-Secret", "secret-1")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(envelope())))
                .andExpect(status().isNoContent());

        verify(rtdnService).processPubSubPush(anyMap());
    }

    @Test
    void receive_shouldReturnNotFoundWhenDisabled() throws Exception {
        properties.setEnabled(false);

        mockMvc.perform(post("/api/subscription/google-play/rtdn")
                        .header("X-KlioAI-RTDN-Secret", "secret-1")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(envelope())))
                .andExpect(status().isNotFound());

        verifyNoInteractions(rtdnService);
    }

    private Map<String, Object> envelope() {
        return Map.of("message", Map.of("data", "e30="));
    }
}
