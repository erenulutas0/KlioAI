package com.ingilizce.calismaapp.controller;

import com.ingilizce.calismaapp.entity.User;
import com.ingilizce.calismaapp.repository.UserRepository;
import com.ingilizce.calismaapp.security.ClientIpResolver;
import com.ingilizce.calismaapp.service.GrammarCheckService;
import com.ingilizce.calismaapp.service.AiRateLimitService;
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
 * Uses JLanguageTool for English grammar validation
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

            return ResponseEntity.ok(results);

        } catch (Exception e) {
            return ResponseEntity.internalServerError().body(Map.of());
        }
    }

    private ResponseEntity<Map<String, Object>> enforceAiAccess(HttpServletRequest request, String scope) {
        Long userId = currentUserContext.getCurrentUserId().orElse(null);

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

        return ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS)
                .header("Retry-After", String.valueOf(decision.retryAfterSeconds()))
                .body(Map.of(
                        "error", "AI request quota exceeded. Please retry later.",
                        "success", false,
                        "retryAfterSeconds", decision.retryAfterSeconds(),
                        "reason", decision.reason()));
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
        status.put("service", "JLanguageTool");
        status.put("language", "en-US");
        status.put("version", "6.4");
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
}
