package com.ingilizce.calismaapp.controller;

import com.ingilizce.calismaapp.entity.User;
import com.ingilizce.calismaapp.repository.UserRepository;
import com.ingilizce.calismaapp.security.ClientIpResolver;
import com.ingilizce.calismaapp.service.GrammarCheckService;
import com.ingilizce.calismaapp.service.AiRateLimitService;
import com.ingilizce.calismaapp.service.AiTokenQuotaService;
import com.ingilizce.calismaapp.service.ProgressService;
import com.ingilizce.calismaapp.security.CurrentUserContext;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * REST Controller for grammar checking functionality
 * Uses the configured AI provider for English grammar validation.
 */
@RestController
@RequestMapping("/api/grammar")
public class GrammarController {

    @Autowired
    private GrammarCheckService grammarCheckService;

    @Autowired
    private CurrentUserContext currentUserContext;

    @Autowired
    private UserRepository userRepository;

    @Autowired(required = false)
    private AiRateLimitService aiRateLimitService;

    @Autowired
    private ClientIpResolver clientIpResolver;

    @Autowired(required = false)
    private ProgressService progressService;

    @Autowired(required = false)
    private AiTokenQuotaService aiTokenQuotaService;

    // GrammarCheckService calls the discard-usage AiCompletionProvider.chatCompletion()
    // overload (no real token count available), so quota consumption uses a fixed
    // conservative estimate per call - a fair-use throttle, not a billing meter,
    // consistent with how speech tokens are estimated from audio duration elsewhere.
    private static final long ESTIMATED_TOKENS_PER_GRAMMAR_CHECK = 400;

    /**
     * Check grammar for a single sentence
     * 
     * @param request Map containing "sentence" key
     * @return Grammar check results with errors and suggestions
     * 
     *         Example request:
     *         {
     *         "sentence": "I goes to school"
     *         }
     * 
     *         Example response:
     *         {
     *         "hasErrors": true,
     *         "errorCount": 1,
     *         "errors": [
     *         {
     *         "message": "The verb 'goes' does not agree with the subject 'I'",
     *         "shortMessage": "Wrong verb form",
     *         "fromPos": 2,
     *         "toPos": 6,
     *         "suggestions": ["go"]
     *         }
     *         ]
     *         }
     */
    @PostMapping("/check")
    public ResponseEntity<Map<String, Object>> checkGrammar(@RequestBody Map<String, String> request,
                                                            HttpServletRequest httpRequest) {
        try {
            ResponseEntity<Map<String, Object>> aiAccessResult = enforceAiAccess(httpRequest, "grammar-check");
            if (aiAccessResult != null) {
                return aiAccessResult;
            }

            String sentence = request.get("sentence");

            if (sentence == null || sentence.trim().isEmpty()) {
                Map<String, Object> errorResponse = new HashMap<>();
                errorResponse.put("hasErrors", false);
                errorResponse.put("errorCount", 0);
                errorResponse.put("errors", List.of());
                errorResponse.put("message", "Empty sentence provided");
                return ResponseEntity.badRequest().body(errorResponse);
            }

            Map<String, Object> result = grammarCheckService.checkGrammar(sentence);
            Long userId = currentUserContext.getCurrentUserId().orElse(null);
            consumeAiTokens(userId, httpRequest, "grammar-check", ESTIMATED_TOKENS_PER_GRAMMAR_CHECK);
            creditDailyStreak(userId);
            return ResponseEntity.ok(result);

        } catch (Exception e) {
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("hasErrors", false);
            errorResponse.put("errorCount", 0);
            errorResponse.put("errors", List.of());
            errorResponse.put("message", "Grammar check failed: " + e.getMessage());
            return ResponseEntity.internalServerError().body(errorResponse);
        }
    }

    /**
     * Check grammar for multiple sentences
     * 
     * @param request Map containing "sentences" array
     * @return Map of sentence to errors
     * 
     *         Example request:
     *         {
     *         "sentences": ["I goes to school", "She play tennis"]
     *         }
     * 
     *         Example response:
     *         {
     *         "I goes to school": [
     *         {
     *         "message": "Wrong verb form",
     *         "suggestions": ["go"]
     *         }
     *         ],
     *         "She play tennis": [
     *         {
     *         "message": "Wrong verb form",
     *         "suggestions": ["plays"]
     *         }
     *         ]
     *         }
     */
    @PostMapping("/check-multiple")
    public ResponseEntity<Object> checkMultipleSentences(
            @RequestBody Map<String, List<String>> request,
            HttpServletRequest httpRequest) {
        try {
            ResponseEntity<Map<String, Object>> aiAccessResult = enforceAiAccess(httpRequest, "grammar-check-multiple");
            if (aiAccessResult != null) {
                return ResponseEntity.status(aiAccessResult.getStatusCode()).body(aiAccessResult.getBody());
            }

            List<String> sentences = request.get("sentences");

            if (sentences == null || sentences.isEmpty()) {
                return ResponseEntity.badRequest().body(Map.of());
            }

            Map<String, List<Map<String, Object>>> results = grammarCheckService.checkMultipleSentences(sentences);

            Long userId = currentUserContext.getCurrentUserId().orElse(null);
            consumeAiTokens(userId, httpRequest, "grammar-check-multiple",
                    (long) sentences.size() * ESTIMATED_TOKENS_PER_GRAMMAR_CHECK);
            creditDailyStreak(userId);
            return ResponseEntity.ok(results);

        } catch (Exception e) {
            return ResponseEntity.internalServerError().body(Map.of());
        }
    }

    private ResponseEntity<Map<String, Object>> enforceAiAccess(HttpServletRequest request, String scope) {
        Long userId = currentUserContext.getCurrentUserId().orElse(null);

        ResponseEntity<Map<String, Object>> quotaLimit = enforceAiTokenQuota(userId, request, scope);
        if (quotaLimit != null) {
            return quotaLimit;
        }

        if (currentUserContext.shouldEnforceAuthz()) {
            if (userId == null) {
                return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                        .body(Map.of("error", "Unauthorized", "success", false));
            }
            if (!hasActiveSubscription(userId)) {
                return ResponseEntity.status(HttpStatus.FORBIDDEN)
                        .body(Map.of("error", "Subscription expired or not active.", "success", false));
            }
        }

        return enforceAiRateLimit(userId, request, scope);
    }

    private boolean hasActiveSubscription(Long userId) {
        if (userId == null) {
            return false;
        }
        return userRepository.findById(userId)
                .map(User::isSubscriptionActive)
                .orElse(false);
    }

    private ResponseEntity<Map<String, Object>> enforceAiRateLimit(Long userId,
                                                                    HttpServletRequest request,
                                                                    String scope) {
        if (aiRateLimitService == null) {
            return null;
        }

        AiRateLimitService.Decision decision = aiRateLimitService.checkAndConsume(
                userId,
                clientIpResolver.resolve(request),
                scope);

        if (!decision.blocked()) {
            return null;
        }

        boolean abusePenalty = ABUSE_BAN_REASON.equals(decision.reason()) || decision.penaltyLevel() > 0;
        Map<String, Object> payload = new HashMap<>();
        payload.put("error", abusePenalty
                ? String.format("Abusive AI traffic detected. Temporary ban applied (%d sec).",
                decision.retryAfterSeconds())
                : "AI request quota exceeded. Please retry later.");
        payload.put("success", false);
        payload.put("retryAfterSeconds", decision.retryAfterSeconds());
        payload.put("reason", decision.reason());
        if (abusePenalty) {
            payload.put("abuseWarning", "Repeated abuse attempts will increase temporary ban duration.");
            payload.put("banLevel", decision.penaltyLevel());
            payload.put("nextBanSeconds", decision.nextPenaltySeconds());
        }

        return ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS)
                .header("Retry-After", String.valueOf(decision.retryAfterSeconds()))
                .body(payload);
    }

    /**
     * Get grammar checker status
     * 
     * @return Status information
     */
    @GetMapping("/status")
    public ResponseEntity<Map<String, Object>> getStatus() {
        Map<String, Object> status = new HashMap<>();
        status.put("enabled", grammarCheckService.isEnabled());
        status.put("service", "AI Grammar Checker");
        status.put("language", "English");
        status.put("targetLanguage", "English");
        status.put("strategy", "english-learning-only");
        return ResponseEntity.ok(status);
    }

    /**
     * Enable or disable grammar checking
     * 
     * @param request Map containing "enabled" boolean
     * @return Updated status
     */
    @PostMapping("/toggle")
    public ResponseEntity<Map<String, Object>> toggleGrammarCheck(@RequestBody Map<String, Boolean> request) {
        if (currentUserContext.shouldEnforceAuthz() && !currentUserContext.hasRole("ADMIN")) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN)
                    .body(Map.of("enabled", grammarCheckService.isEnabled(), "message", "Admin role required"));
        }

        Boolean enabled = request.get("enabled");
        if (enabled != null) {
            grammarCheckService.setEnabled(enabled);
        }

        boolean currentEnabled = grammarCheckService.isEnabled();
        Map<String, Object> status = new HashMap<>();
        status.put("enabled", currentEnabled);
        status.put("message", currentEnabled ? "Grammar checking enabled" : "Grammar checking disabled");
        return ResponseEntity.ok(status);
    }

    private void creditDailyStreak(Long userId) {
        if (progressService == null || userId == null) {
            return;
        }
        try {
            progressService.updateStreak(userId);
        } catch (Exception ignored) {
        }
    }

    private ResponseEntity<Map<String, Object>> enforceAiTokenQuota(Long userId,
                                                                     HttpServletRequest request,
                                                                     String scope) {
        if (aiTokenQuotaService == null) {
            return null;
        }

        AiTokenQuotaService.Decision decision = aiTokenQuotaService.check(
                userId,
                scope,
                resolveDeviceId(request),
                clientIpResolver.resolve(request));
        if (!decision.blocked()) {
            return null;
        }

        Map<String, Object> payload = new HashMap<>();
        payload.put("success", false);
        payload.put("reason", decision.reason());
        payload.put("tokenLimit", decision.tokenLimit());
        payload.put("tokensUsed", decision.tokensUsed());
        payload.put("tokensRemaining", decision.tokensRemaining());

        if ("ai-access-disabled".equalsIgnoreCase(decision.reason())) {
            payload.put("error", "AI features are currently disabled. Upgrade to premium to continue.");
            payload.put("upgradeRequired", true);
            return ResponseEntity.status(HttpStatus.FORBIDDEN).body(payload);
        }

        payload.put("error", "Daily AI quota exceeded. Please try again later.");
        payload.put("retryAfterSeconds", decision.retryAfterSeconds());
        return ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS)
                .header("Retry-After", String.valueOf(decision.retryAfterSeconds()))
                .body(payload);
    }

    private void consumeAiTokens(Long userId, HttpServletRequest request, String scope, long tokens) {
        if (aiTokenQuotaService == null) {
            return;
        }
        try {
            aiTokenQuotaService.consume(
                    userId,
                    scope,
                    Math.max(0, tokens),
                    resolveDeviceId(request),
                    clientIpResolver.resolve(request));
        } catch (Exception ignored) {
        }
    }

    private String resolveDeviceId(HttpServletRequest request) {
        if (request == null) {
            return null;
        }
        String deviceId = request.getHeader("X-Device-Id");
        if (deviceId == null || deviceId.isBlank()) {
            return null;
        }
        return deviceId.trim();
    }

    private static final String ABUSE_BAN_REASON = "abuse-ban";
}
