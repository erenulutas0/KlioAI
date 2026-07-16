package com.ingilizce.calismaapp.controller;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.ingilizce.calismaapp.entity.User;
import com.ingilizce.calismaapp.repository.UserRepository;
import com.ingilizce.calismaapp.security.ClientIpResolver;
import com.ingilizce.calismaapp.security.CurrentUserContext;
import com.ingilizce.calismaapp.service.AiRateLimitService;
import com.ingilizce.calismaapp.service.GrammarCheckService;
import jakarta.servlet.http.HttpServletRequest;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.test.util.ReflectionTestUtils;

class GrammarControllerUnitTest {

    private GrammarCheckService grammarCheckService;
    private CurrentUserContext currentUserContext;
    private UserRepository userRepository;
    private AiRateLimitService aiRateLimitService;
    private ClientIpResolver clientIpResolver;
    private HttpServletRequest request;
    private GrammarController controller;

    @BeforeEach
    void setUp() {
        grammarCheckService = mock(GrammarCheckService.class);
        currentUserContext = mock(CurrentUserContext.class);
        userRepository = mock(UserRepository.class);
        aiRateLimitService = mock(AiRateLimitService.class);
        clientIpResolver = mock(ClientIpResolver.class);
        request = mock(HttpServletRequest.class);

        controller = new GrammarController();
        ReflectionTestUtils.setField(controller, "grammarCheckService", grammarCheckService);
        ReflectionTestUtils.setField(controller, "currentUserContext", currentUserContext);
        ReflectionTestUtils.setField(controller, "userRepository", userRepository);
        ReflectionTestUtils.setField(controller, "aiRateLimitService", aiRateLimitService);
        ReflectionTestUtils.setField(controller, "clientIpResolver", clientIpResolver);
    }

    @Test
    void checkGrammarShouldReturnUnauthorizedWhenAuthzIsEnforcedWithoutUser() {
        when(currentUserContext.shouldEnforceAuthz()).thenReturn(true);
        when(currentUserContext.getCurrentUserId()).thenReturn(Optional.empty());

        ResponseEntity<Map<String, Object>> response = controller.checkGrammar(Map.of("sentence", "I go home"), request);

        assertEquals(HttpStatus.UNAUTHORIZED, response.getStatusCode());
        assertEquals("Unauthorized", response.getBody().get("error"));
        assertEquals(false, response.getBody().get("success"));
    }

    @Test
    void checkGrammarShouldReturnForbiddenWhenSubscriptionIsInactive() {
        when(currentUserContext.shouldEnforceAuthz()).thenReturn(true);
        when(currentUserContext.getCurrentUserId()).thenReturn(Optional.of(7L));
        User user = new User("user@example.com", "hash");
        user.setId(7L);
        when(userRepository.findById(7L)).thenReturn(Optional.of(user));

        ResponseEntity<Map<String, Object>> response = controller.checkGrammar(Map.of("sentence", "I go home"), request);

        assertEquals(HttpStatus.FORBIDDEN, response.getStatusCode());
        assertEquals("Subscription expired or not active.", response.getBody().get("error"));
    }

    @Test
    void checkGrammarShouldReturnTooManyRequestsWhenAiRateLimitBlocks() {
        when(currentUserContext.shouldEnforceAuthz()).thenReturn(true);
        when(currentUserContext.getCurrentUserId()).thenReturn(Optional.of(7L));
        User user = new User("user@example.com", "hash");
        user.setId(7L);
        user.setSubscriptionEndDate(LocalDateTime.now().plusDays(1));
        when(userRepository.findById(7L)).thenReturn(Optional.of(user));
        when(clientIpResolver.resolve(request)).thenReturn("203.0.113.10");
        when(aiRateLimitService.checkAndConsume(7L, "203.0.113.10", "grammar-check"))
                .thenReturn(AiRateLimitService.Decision.blocked("scope-limit", 30));

        ResponseEntity<Map<String, Object>> response = controller.checkGrammar(Map.of("sentence", "I go home"), request);

        assertEquals(HttpStatus.TOO_MANY_REQUESTS, response.getStatusCode());
        assertEquals("30", response.getHeaders().getFirst("Retry-After"));
        assertEquals("scope-limit", response.getBody().get("reason"));
        assertEquals(30L, response.getBody().get("retryAfterSeconds"));
    }

    @Test
    void checkMultipleShouldReturnAbuseBanPayloadWhenPenaltyBlocks() {
        when(currentUserContext.shouldEnforceAuthz()).thenReturn(false);
        when(currentUserContext.getCurrentUserId()).thenReturn(Optional.of(7L));
        when(clientIpResolver.resolve(request)).thenReturn("203.0.113.10");
        when(aiRateLimitService.checkAndConsume(7L, "203.0.113.10", "grammar-check-multiple"))
                .thenReturn(AiRateLimitService.Decision.blockedWithPenalty("abuse-ban", 120, 2, 300));

        ResponseEntity<Object> response = controller.checkMultipleSentences(Map.of("sentences", List.of("One")), request);

        assertEquals(HttpStatus.TOO_MANY_REQUESTS, response.getStatusCode());
        @SuppressWarnings("unchecked")
        Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertEquals("abuse-ban", body.get("reason"));
        assertEquals(2, body.get("banLevel"));
        assertEquals(300L, body.get("nextBanSeconds"));
        assertTrue(body.get("error").toString().contains("Temporary ban"));
    }

    @Test
    void toggleShouldRejectNonAdminWhenAuthzIsEnforced() {
        when(currentUserContext.shouldEnforceAuthz()).thenReturn(true);
        when(currentUserContext.hasRole("ADMIN")).thenReturn(false);
        when(grammarCheckService.isEnabled()).thenReturn(true);

        ResponseEntity<Map<String, Object>> response = controller.toggleGrammarCheck(Map.of("enabled", false));

        assertEquals(HttpStatus.FORBIDDEN, response.getStatusCode());
        assertEquals("Admin role required", response.getBody().get("message"));
        assertEquals(true, response.getBody().get("enabled"));
    }

    @Test
    void toggleShouldUpdateWhenAdminOrAuthzDisabled() {
        when(currentUserContext.shouldEnforceAuthz()).thenReturn(true);
        when(currentUserContext.hasRole("ADMIN")).thenReturn(true);
        when(grammarCheckService.isEnabled()).thenReturn(false);

        ResponseEntity<Map<String, Object>> response = controller.toggleGrammarCheck(Map.of("enabled", false));

        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertFalse((Boolean) response.getBody().get("enabled"));
        verify(grammarCheckService).setEnabled(eq(false));
    }
}
