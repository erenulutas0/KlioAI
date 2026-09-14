package com.ingilizce.calismaapp.service;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.http.HttpEntity;
import org.springframework.http.ResponseEntity;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestTemplate;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

@ExtendWith(OutputCaptureExtension.class)
class TelegramNotifierTest {

    private static final String TOKEN = "123456:SECRET-bot-token";

    private RestTemplate restTemplate;
    private TelegramNotifier notifier;

    @BeforeEach
    void setUp() {
        restTemplate = mock(RestTemplate.class);
        notifier = new TelegramNotifier(restTemplate);
        ReflectionTestUtils.setField(notifier, "botToken", TOKEN);
        ReflectionTestUtils.setField(notifier, "chatId", "987654");
    }

    @Test
    void anUnconfiguredBotSendsNothing() {
        ReflectionTestUtils.setField(notifier, "botToken", "");

        assertFalse(notifier.isConfigured());
        assertFalse(notifier.send("hello"));
        verifyNoInteractions(restTemplate);
    }

    @Test
    @SuppressWarnings("unchecked")
    void theMessageGoesToTheChatAsPlainText() {
        when(restTemplate.postForEntity(anyString(), any(), eq(String.class)))
                .thenReturn(ResponseEntity.ok("{\"ok\":true}"));

        assertTrue(notifier.send("KlioAI · 4,5 *not bold*"));

        ArgumentCaptor<HttpEntity<Map<String, Object>>> body = ArgumentCaptor.forClass(HttpEntity.class);
        verify(restTemplate).postForEntity(
                eq("https://api.telegram.org/bot" + TOKEN + "/sendMessage"), body.capture(), eq(String.class));
        assertEquals("987654", body.getValue().getBody().get("chat_id"));
        assertEquals("KlioAI · 4,5 *not bold*", body.getValue().getBody().get("text"));
        // No parse_mode: a learner's asterisk must not be able to break the message.
        assertFalse(body.getValue().getBody().containsKey("parse_mode"));
    }

    @Test
    void aFailureNeverWritesTheTokenToTheLog(CapturedOutput output) {
        // Spring quotes the request URL in an I/O exception's message, and the URL has the token.
        when(restTemplate.postForEntity(anyString(), any(), eq(String.class)))
                .thenThrow(new ResourceAccessException(
                        "I/O error on POST request for \"https://api.telegram.org/bot" + TOKEN + "/sendMessage\""));

        assertFalse(notifier.send("hello"));

        assertFalse(output.getAll().contains(TOKEN), output.getAll());
        assertTrue(output.getAll().contains("ResourceAccessException"), output.getAll());
    }
}
