package com.ingilizce.calismaapp.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ingilizce.calismaapp.entity.SubscriptionPlan;
import com.ingilizce.calismaapp.entity.User;
import com.ingilizce.calismaapp.repository.PaymentTransactionRepository;
import com.ingilizce.calismaapp.repository.SubscriptionPlanRepository;
import com.ingilizce.calismaapp.repository.UserRepository;
import com.ingilizce.calismaapp.service.GooglePlaySubscriptionVerificationService;
import com.ingilizce.calismaapp.service.IyzicoService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.argThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

// Verifies the production billing-truth mode: with trust-verified-expiry=true,
// Google's expiryTime is honored EXACTLY (no minimum-duration floor), while an
// already-promised longer end date is never shrunk.
@SpringBootTest(properties = {
        "app.subscription.mock-verification-enabled=false",
        "app.security.jwt.enforce-auth=true",
        "app.subscription.google-play.trust-verified-expiry=true"
})
@AutoConfigureMockMvc
@ActiveProfiles("test")
@DisplayName("Subscription Controller Trusted Expiry Mode Tests")
class SubscriptionControllerTrustExpiryTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockBean
    private SubscriptionPlanRepository planRepository;

    @MockBean
    private UserRepository userRepository;

    @MockBean
    private PaymentTransactionRepository transactionRepository;

    @MockBean
    private IyzicoService iyzicoService;

    @MockBean
    private GooglePlaySubscriptionVerificationService googlePlaySubscriptionVerificationService;

    private User testUser;
    private SubscriptionPlan premiumPlan;

    @BeforeEach
    void setUp() {
        testUser = new User("trust@example.com", "password");
        testUser.setId(1L);

        premiumPlan = new SubscriptionPlan("PREMIUM", new BigDecimal("5.00"), 30);
        premiumPlan.setId(10L);
    }

    private void stubVerification(String token, Instant expiry) {
        GooglePlaySubscriptionVerificationService.VerificationResult verification =
                new GooglePlaySubscriptionVerificationService.VerificationResult(
                        "com.example.app",
                        token,
                        "SUBSCRIPTION_STATE_ACTIVE",
                        "GPA.trust",
                        expiry,
                        List.of("premium_monthly"));
        Mockito.when(googlePlaySubscriptionVerificationService.verifySubscription(token, "com.example.app"))
                .thenReturn(verification);
        Mockito.when(googlePlaySubscriptionVerificationService.resolvePlanName(eq(verification), eq("premium_monthly")))
                .thenReturn("PREMIUM");
        Mockito.when(planRepository.findByName("PREMIUM")).thenReturn(Optional.of(premiumPlan));
        Mockito.when(transactionRepository.findByTransactionIdWithUserAndPlan("google:" + token))
                .thenReturn(Optional.empty());
    }

    private void postVerify(String token) throws Exception {
        Map<String, String> request = Map.of(
                "purchaseToken", token,
                "packageName", "com.example.app",
                "productId", "premium_monthly");
        mockMvc.perform(post("/api/subscription/verify/google")
                        .header("X-User-Id", "1")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isOk());
    }

    @Test
    void verifyGooglePurchase_ShouldHonorGoogleExpiryExactly_WithoutDurationFloor() throws Exception {
        // A 5-day-out Google expiry must yield a 5-day entitlement, not the
        // 30-day floored one the legacy mode grants.
        Mockito.when(userRepository.findById(1L)).thenReturn(Optional.of(testUser));
        Instant expiry = Instant.now().plus(java.time.Duration.ofDays(5));
        stubVerification("token-exact", expiry);

        postVerify("token-exact");

        LocalDateTime expected = LocalDateTime.ofInstant(expiry, ZoneOffset.UTC);
        Mockito.verify(userRepository).save(argThat(user ->
                user.getSubscriptionEndDate() != null
                        && user.getSubscriptionEndDate().isAfter(expected.minusMinutes(1))
                        && user.getSubscriptionEndDate().isBefore(expected.plusMinutes(1))));
    }

    @Test
    void verifyGooglePurchase_ShouldNeverShrinkAlreadyPromisedEndDate() throws Exception {
        // If a (legacy over-granted) end date is already beyond Google's expiry,
        // re-verifying must not take entitlement away from the user.
        LocalDateTime promised = LocalDateTime.now().plusDays(60);
        testUser.setSubscriptionEndDate(promised);
        Mockito.when(userRepository.findById(1L)).thenReturn(Optional.of(testUser));
        stubVerification("token-keep", Instant.now().plus(java.time.Duration.ofDays(5)));

        postVerify("token-keep");

        Mockito.verify(userRepository).save(argThat(user ->
                promised.equals(user.getSubscriptionEndDate())));
    }
}
