package com.ingilizce.calismaapp.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClientResponseException;
import org.springframework.web.client.RestTemplate;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Sends a plain-text message to one Telegram chat: the developer's.
 *
 * <p>Unconfigured is a normal state -- a local run, a test, a server where the bot has not
 * been set up -- and means nothing is sent. Nothing here throws: a digest that fails to
 * arrive must not take anything else down with it.
 *
 * <p>The bot token is part of the request URL, and Spring's I/O exceptions quote the URL in
 * their message. So a failure is logged by status or exception type only, never by message:
 * one careless {@code e.getMessage()} would write the token into every log line after an
 * outage.
 */
@Service
public class TelegramNotifier {

    private static final Logger log = LoggerFactory.getLogger(TelegramNotifier.class);

    @Value("${app.feedback.digest.telegram.bot-token:}")
    private String botToken;

    @Value("${app.feedback.digest.telegram.chat-id:}")
    private String chatId;

    @Value("${app.feedback.digest.telegram.api-base:https://api.telegram.org}")
    private String apiBase = "https://api.telegram.org";

    private final RestTemplate restTemplate;

    public TelegramNotifier() {
        this(defaultRestTemplate());
    }

    TelegramNotifier(RestTemplate restTemplate) {
        this.restTemplate = restTemplate;
    }

    private static RestTemplate defaultRestTemplate() {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(5_000);
        factory.setReadTimeout(10_000);
        return new RestTemplate(factory);
    }

    public boolean isConfigured() {
        return botToken != null && !botToken.isBlank() && chatId != null && !chatId.isBlank();
    }

    /** True when Telegram accepted the message. */
    public boolean send(String text) {
        if (!isConfigured() || text == null || text.isBlank()) {
            return false;
        }
        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            Map<String, Object> body = new LinkedHashMap<>();
            body.put("chat_id", chatId.trim());
            body.put("text", text);
            body.put("disable_web_page_preview", true);
            ResponseEntity<String> response = restTemplate.postForEntity(
                    apiBase.trim().replaceAll("/+$", "") + "/bot" + botToken.trim() + "/sendMessage",
                    new HttpEntity<>(body, headers), String.class);
            return response.getStatusCode().is2xxSuccessful();
        } catch (RestClientResponseException rejected) {
            log.warn("Telegram rejected the message: status={}", rejected.getStatusCode().value());
            return false;
        } catch (Exception failed) {
            log.warn("Telegram message could not be sent: {}", failed.getClass().getSimpleName());
            return false;
        }
    }
}
