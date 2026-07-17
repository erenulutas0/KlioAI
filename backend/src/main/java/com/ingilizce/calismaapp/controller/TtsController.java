package com.ingilizce.calismaapp.controller;

import com.ingilizce.calismaapp.security.ClientIpResolver;
import com.ingilizce.calismaapp.service.AiRateLimitService;
import com.ingilizce.calismaapp.service.PiperTtsService;
import jakarta.servlet.http.HttpServletRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/api/tts")
public class TtsController {
    private static final Logger log = LoggerFactory.getLogger(TtsController.class);
    private static final String RATE_LIMIT_SCOPE = "tts-synthesize";

    private final PiperTtsService piperTtsService;
    private final AiRateLimitService aiRateLimitService;
    private final ClientIpResolver clientIpResolver;

    // Each synthesize call forks a native Piper process; without a text-length
    // cap and a per-subject rate limit this endpoint is a CPU-exhaustion vector
    // on the shared VPS.
    @Value("${app.tts.max-text-length:400}")
    private int maxTextLength;

    public TtsController(PiperTtsService piperTtsService,
            @Autowired(required = false) AiRateLimitService aiRateLimitService,
            @Autowired(required = false) ClientIpResolver clientIpResolver) {
        this.piperTtsService = piperTtsService;
        this.aiRateLimitService = aiRateLimitService;
        this.clientIpResolver = clientIpResolver;
    }

    @PostMapping("/synthesize")
    public ResponseEntity<?> synthesize(@RequestBody Map<String, String> request,
            @RequestHeader(value = "X-User-Id", required = false) Long userId,
            HttpServletRequest httpRequest) {
        String text = request.get("text");
        String voice = request.get("voice");

        if (text == null || text.trim().isEmpty()) {
            Map<String, Object> error = new HashMap<>();
            error.put("error", "Text is required");
            return ResponseEntity.badRequest().body(error);
        }

        String trimmedText = text.trim();
        if (trimmedText.length() > maxTextLength) {
            Map<String, Object> error = new HashMap<>();
            error.put("error", "Text is too long for speech synthesis");
            error.put("maxTextLength", maxTextLength);
            error.put("success", false);
            return ResponseEntity.badRequest().body(error);
        }

        if (aiRateLimitService != null) {
            String clientIp = clientIpResolver != null
                    ? clientIpResolver.resolve(httpRequest)
                    : (httpRequest != null ? httpRequest.getRemoteAddr() : "unknown");
            AiRateLimitService.Decision decision =
                    aiRateLimitService.checkAndConsume(userId, clientIp, RATE_LIMIT_SCOPE);
            if (decision.blocked()) {
                Map<String, Object> error = new HashMap<>();
                error.put("error", "TTS request limit reached. Please try again later.");
                error.put("reason", decision.reason());
                error.put("retryAfterSeconds", decision.retryAfterSeconds());
                error.put("success", false);
                return ResponseEntity.status(429).body(error);
            }
        }

        try {
            if (!piperTtsService.isAvailable()) {
                Map<String, Object> error = new HashMap<>();
                error.put("error", "Piper TTS is not available.");
                error.put("available", false);
                return ResponseEntity.status(503).body(error);
            }

            // Service bize zaten Base64 string veriyor, onu hiç bozmadan JSON'a koyuyoruz.
            // (Eskiden decode edip byte[] yapıyorduk, artık gerek yok)
            String audioBase64 = piperTtsService.synthesizeSpeech(trimmedText, voice);

            Map<String, String> response = new HashMap<>();
            response.put("audio", audioBase64); // "audio" anahtarı ile gönderiyoruz

            return ResponseEntity.ok(response);

        } catch (Exception e) {
            Map<String, Object> error = new HashMap<>();
            error.put("error", "Failed to synthesize: " + e.getMessage());
            log.error("Failed to synthesize speech via Piper TTS", e);
            return ResponseEntity.internalServerError().body(error);
        }
    }

    @GetMapping("/status")
    public ResponseEntity<Map<String, Object>> getStatus() {
        Map<String, Object> status = new HashMap<>();
        boolean available = piperTtsService.isAvailable();
        status.put("available", available);
        status.put("voices", piperTtsService.getSupportedVoices());
        return ResponseEntity.ok(status);
    }
}
