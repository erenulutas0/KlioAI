package com.ingilizce.calismaapp.controller;

import com.ingilizce.calismaapp.service.AiRateLimitService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;
import com.ingilizce.calismaapp.repository.WordRepository;
import com.ingilizce.calismaapp.repository.WordReviewRepository;
import com.ingilizce.calismaapp.repository.SentenceRepository;
import com.ingilizce.calismaapp.repository.SentencePracticeRepository;
import com.ingilizce.calismaapp.security.CurrentUserContext;

import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/api/admin")
public class AdminController {

    @Autowired
    private WordReviewRepository wordReviewRepository;

    @Autowired
    private SentencePracticeRepository sentencePracticeRepository;

    @Autowired
    private SentenceRepository sentenceRepository;

    @Autowired
    private WordRepository wordRepository;

    @Autowired
    private CurrentUserContext currentUserContext;

    @Autowired(required = false)
    private AiRateLimitService aiRateLimitService;

    @PostMapping("/reset-data")
    public String resetData() {
        if (currentUserContext.shouldEnforceAuthz() && !currentUserContext.hasRole("ADMIN")) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Admin role required");
        }
        try {
            wordReviewRepository.deleteAll();
            sentencePracticeRepository.deleteAll();
            sentenceRepository.deleteAll();
            wordRepository.deleteAll();
            return "Mock data (Words, Sentences, Reviews) reset successful.";
        } catch (Exception e) {
            return "Error resetting data: " + e.getMessage();
        }
    }

    @PostMapping("/ai-abuse/unban")
    public ResponseEntity<Map<String, Object>> clearAiAbusePenalty(@RequestBody Map<String, Object> payload) {
        ResponseEntity<Map<String, Object>> preflight = requireAdminRateLimitService();
        if (preflight != null) return preflight;

        Long userId = toNullableLong(payload.get("userId"));
        String clientIp = payload.get("clientIp") == null ? null : payload.get("clientIp").toString().trim();
        if (clientIp != null && clientIp.isBlank()) {
            clientIp = null;
        }

        if (userId == null && clientIp == null) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                    .body(Map.of("success", false, "error", "userId or clientIp is required"));
        }

        AiRateLimitService.UnbanResult result = aiRateLimitService.clearAbusePenalty(userId, clientIp);

        Map<String, Object> body = new HashMap<>();
        body.put("success", true);
        body.put("userId", userId);
        body.put("clientIp", clientIp);
        body.put("userSubject", result.userSubject());
        body.put("ipSubject", result.ipSubject());
        body.put("userPenaltyCleared", result.userPenaltyCleared());
        body.put("ipPenaltyCleared", result.ipPenaltyCleared());
        body.put("message", "AI abuse penalty cleanup executed.");

        return ResponseEntity.ok(body);
    }

    @PostMapping("/ai-abuse/status")
    public ResponseEntity<Map<String, Object>> aiAbuseStatus(@RequestBody Map<String, Object> payload) {
        ResponseEntity<Map<String, Object>> preflight = requireAdminRateLimitService();
        if (preflight != null) return preflight;

        Long userId = toNullableLong(payload.get("userId"));
        String clientIp = payload.get("clientIp") == null ? null : payload.get("clientIp").toString().trim();
        if (clientIp != null && clientIp.isBlank()) {
            clientIp = null;
        }

        if (userId == null && clientIp == null) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                    .body(Map.of("success", false, "error", "userId or clientIp is required"));
        }

        AiRateLimitService.AbusePenaltyStatus status = aiRateLimitService.getAbusePenaltyStatus(userId, clientIp);

        Map<String, Object> body = new HashMap<>();
        body.put("success", true);
        body.put("userId", userId);
        body.put("clientIp", clientIp);
        body.put("userSubject", status.userSubject());
        body.put("ipSubject", status.ipSubject());
        body.put("userPenaltyActive", status.userPenaltyActive());
        body.put("ipPenaltyActive", status.ipPenaltyActive());
        body.put("userRetryAfterSeconds", status.userRetryAfterSeconds());
        body.put("ipRetryAfterSeconds", status.ipRetryAfterSeconds());
        body.put("anyPenaltyActive", status.userPenaltyActive() || status.ipPenaltyActive());

        return ResponseEntity.ok(body);
    }

    @GetMapping("/ai-abuse/stats")
    public ResponseEntity<Map<String, Object>> aiAbuseStats() {
        ResponseEntity<Map<String, Object>> preflight = requireAdminRateLimitService();
        if (preflight != null) return preflight;

        AiRateLimitService.AbuseStats stats = aiRateLimitService.getAbuseStats();

        Map<String, Object> body = new HashMap<>();
        body.put("success", true);
        body.put("enabled", stats.enabled());
        body.put("redisEnabled", stats.redisEnabled());
        body.put("redisFallbackMode", stats.redisFallbackMode());
        body.put("redisFallbackActive", stats.redisFallbackActive());
        body.put("abusePenaltyEnabled", stats.abusePenaltyEnabled());
        body.put("abusePenaltySeconds", stats.abusePenaltySeconds());
        body.put("abuseStrikeResetSeconds", stats.abuseStrikeResetSeconds());
        body.put("configuredScopeCount", stats.configuredScopeCount());
        body.put("memoryPenaltySubjects", stats.memoryPenaltySubjects());
        body.put("memoryActivePenaltySubjects", stats.memoryActivePenaltySubjects());
        body.put("memoryUserWindowSubjects", stats.memoryUserWindowSubjects());
        body.put("memoryIpWindowSubjects", stats.memoryIpWindowSubjects());

        return ResponseEntity.ok(body);
    }

    private ResponseEntity<Map<String, Object>> requireAdminRateLimitService() {
        if (currentUserContext.shouldEnforceAuthz() && !currentUserContext.hasRole("ADMIN")) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN)
                    .body(Map.of("success", false, "error", "Admin role required"));
        }
        if (aiRateLimitService == null) {
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                    .body(Map.of("success", false, "error", "AI rate limit service unavailable"));
        }
        return null;
    }

    private Long toNullableLong(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Number number) {
            return number.longValue();
        }
        try {
            return Long.parseLong(value.toString().trim());
        } catch (NumberFormatException ignored) {
            return null;
        }
    }
}
