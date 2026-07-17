package com.ingilizce.calismaapp.controller;

import com.ingilizce.calismaapp.config.GooglePlayRtdnProperties;
import com.ingilizce.calismaapp.service.GooglePlayRtdnService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
@RequestMapping("/api/subscription/google-play/rtdn")
public class GooglePlayRtdnController {

    private final GooglePlayRtdnProperties rtdnProperties;
    private final GooglePlayRtdnService rtdnService;

    public GooglePlayRtdnController(
            GooglePlayRtdnProperties rtdnProperties,
            GooglePlayRtdnService rtdnService) {
        this.rtdnProperties = rtdnProperties;
        this.rtdnService = rtdnService;
    }

    @PostMapping
    public ResponseEntity<Void> receive(
            @RequestBody Map<String, Object> envelope,
            @RequestHeader(value = "X-KlioAI-RTDN-Secret", required = false) String headerSecret,
            @RequestParam(value = "secret", required = false) String querySecret) {
        if (!rtdnProperties.isEnabled()) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).build();
        }
        if (!hasValidSecret(headerSecret, querySecret)) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }

        rtdnService.processPubSubPush(envelope);
        return ResponseEntity.noContent().build();
    }

    private boolean hasValidSecret(String headerSecret, String querySecret) {
        if (!rtdnProperties.hasSharedSecret()) {
            return true;
        }
        return matchesSecret(headerSecret) || matchesSecret(querySecret);
    }

    private boolean matchesSecret(String providedSecret) {
        return StringUtils.hasText(providedSecret)
                && rtdnProperties.getSharedSecret().equals(providedSecret.trim());
    }
}
