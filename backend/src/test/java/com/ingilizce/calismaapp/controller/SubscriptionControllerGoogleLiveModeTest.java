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
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.argThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest(properties = {
        "app.subscription.mock-verification-enabled=false",
        "app.security.jwt.enforce-auth=true"
})
@AutoConfigureMockMvc
@ActiveProfiles("test")
@DisplayName("Subscription Controller Google Live Mode Tests")
class SubscriptionControllerGoogleLiveModeTest {

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
    private SubscriptionPlan annualPlan;

    @BeforeEach
    void setUp() {
        testUser = new User("test@example.com", "password");
        testUser.setId(1L);

        premiumPlan = new SubscriptionPlan("PREMIUM", new BigDecimal("5.00"), 30);
        premiumPlan.setId(10L);
        annualPlan = new SubscriptionPlan("PRO_ANNUAL", new BigDecimal("999.99"), 365);
        annualPlan.setId(11L);
    }

    @Test
    void verifyGooglePurchase_ShouldUseRealVerificationPath_WhenMockDisabled() throws Exception {
        Mockito.when(userRepository.findById(1L)).thenReturn(Optional.of(testUser));

        GooglePlaySubscriptionVerificationService.VerificationResult verification = new GooglePlaySubscriptionVerificationService.VerificationResult(
                "com.example.app",
                "token-123",
                "SUBSCRIPTION_STATE_ACTIVE",
                "GPA.1234-5678-9012-34567",
                Instant.now().plusSeconds(3600),
                List.of("premium_monthly"));

        Mockito.when(googlePlaySubscriptionVerificationService.verifySubscription("token-123", "com.example.app"))
                .thenReturn(verification);
        Mockito.when(googlePlaySubscriptionVerificationService.resolvePlanName(eq(verification), eq("premium_monthly")))
                .thenReturn("PREMIUM");
        Mockito.when(planRepository.findByName("PREMIUM")).thenReturn(Optional.of(premiumPlan));
        Mockito.when(transactionRepository.findByTransactionIdWithUserAndPlan("google:token-123"))
                .thenReturn(Optional.empty());

        Map<String, String> request = Map.of(
                "purchaseToken", "token-123",
                "packageName", "com.example.app",
                "productId", "premium_monthly");

        mockMvc.perform(post("/api/subscription/verify/google")
                        .header("X-User-Id", "1")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message").value("Google IAP verified"))
                .andExpect(jsonPath("$.planName").value("PREMIUM"));
    }

    @Test
    void verifyGooglePurchase_ShouldGrantOneYearForAnnualPlan_WhenTestExpiryIsShort() throws Exception {
        Mockito.when(userRepository.findById(1L)).thenReturn(Optional.of(testUser));

        GooglePlaySubscriptionVerificationService.VerificationResult verification = new GooglePlaySubscriptionVerificationService.VerificationResult(
                "com.example.app",
                "token-annual",
                "SUBSCRIPTION_STATE_ACTIVE",
                "GPA.annual",
                Instant.now().plusSeconds(300),
                List.of("pro_annual_subscription"));

        Mockito.when(googlePlaySubscriptionVerificationService.verifySubscription("token-annual", "com.example.app"))
                .thenReturn(verification);
        Mockito.when(googlePlaySubscriptionVerificationService.resolvePlanName(eq(verification), eq("pro_annual_subscription")))
                .thenReturn("PRO_ANNUAL");
        Mockito.when(planRepository.findByName("PRO_ANNUAL")).thenReturn(Optional.of(annualPlan));
        Mockito.when(transactionRepository.findByTransactionIdWithUserAndPlan("google:token-annual"))
                .thenReturn(Optional.empty());

        Map<String, String> request = Map.of(
                "purchaseToken", "token-annual",
                "packageName", "com.example.app",
                "productId", "pro_annual_subscription");

        mockMvc.perform(post("/api/subscription/verify/google")
                        .header("X-User-Id", "1")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.planName").value("PRO_ANNUAL"));

        Mockito.verify(userRepository).save(argThat(user ->
                user.getSubscriptionEndDate() != null
                        && user.getSubscriptionEndDate().isAfter(LocalDateTime.now().plusDays(360))));
    }

    @Test
    void verifyGooglePurchase_ShouldNotStackDuration_WhenReVerifiedWithoutUsableExpiry() throws Exception {
        // Grace-period edge: verification succeeds but the reported expiry is in
        // the past. The user already has 40 days of active entitlement. The old
        // logic did currentEnd + 30d on EVERY such verify (repeated restore taps
        // = unbounded free extension); the fix keeps the later of currentEnd and
        // now + planDuration, so the end date must stay ~40 days, never ~70.
        testUser.setSubscriptionEndDate(LocalDateTime.now().plusDays(40));
        Mockito.when(userRepository.findById(1L)).thenReturn(Optional.of(testUser));

        GooglePlaySubscriptionVerificationService.VerificationResult verification = new GooglePlaySubscriptionVerificationService.VerificationResult(
                "com.example.app",
                "token-grace",
                "SUBSCRIPTION_STATE_IN_GRACE_PERIOD",
                "GPA.grace",
                Instant.now().minusSeconds(3600),
                List.of("premium_monthly"));

        Mockito.when(googlePlaySubscriptionVerificationService.verifySubscription("token-grace", "com.example.app"))
                .thenReturn(verification);
        Mockito.when(googlePlaySubscriptionVerificationService.resolvePlanName(eq(verification), eq("premium_monthly")))
                .thenReturn("PREMIUM");
        Mockito.when(planRepository.findByName("PREMIUM")).thenReturn(Optional.of(premiumPlan));
        Mockito.when(transactionRepository.findByTransactionIdWithUserAndPlan("google:token-grace"))
                .thenReturn(Optional.empty());

        Map<String, String> request = Map.of(
                "purchaseToken", "token-grace",
                "packageName", "com.example.app",
                "productId", "premium_monthly");

        mockMvc.perform(post("/api/subscription/verify/google")
                        .header("X-User-Id", "1")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isOk());

        Mockito.verify(userRepository).save(argThat(user ->
                user.getSubscriptionEndDate() != null
                        && user.getSubscriptionEndDate().isAfter(LocalDateTime.now().plusDays(39))
                        && user.getSubscriptionEndDate().isBefore(LocalDateTime.now().plusDays(41))));
    }

    @Test
    void verifyGooglePurchase_ShouldReturnBadRequest_WhenPlanMappingMissing() throws Exception {
        Mockito.when(userRepository.findById(1L)).thenReturn(Optional.of(testUser));

        GooglePlaySubscriptionVerificationService.VerificationResult verification = new GooglePlaySubscriptionVerificationService.VerificationResult(
                "com.example.app",
                "token-456",
                "SUBSCRIPTION_STATE_ACTIVE",
                null,
                Instant.now().plusSeconds(3600),
                List.of("unknown_product"));

        Mockito.when(googlePlaySubscriptionVerificationService.verifySubscription("token-456", "com.example.app"))
                .thenReturn(verification);
        Mockito.when(googlePlaySubscriptionVerificationService.resolvePlanName(eq(verification), eq("unknown_product")))
                .thenReturn(null);

        Map<String, String> request = Map.of(
                "purchaseToken", "token-456",
                "packageName", "com.example.app",
                "productId", "unknown_product");

        mockMvc.perform(post("/api/subscription/verify/google")
                        .header("X-User-Id", "1")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("Unable to map Google product/base plan to internal subscription plan"));
    }

    @Test
    void verifyGooglePurchase_ShouldReturnServiceUnavailable_WhenProviderUnavailable() throws Exception {
        Mockito.when(userRepository.findById(1L)).thenReturn(Optional.of(testUser));
        Mockito.when(googlePlaySubscriptionVerificationService.verifySubscription("token-789", "com.example.app"))
                .thenThrow(new GooglePlaySubscriptionVerificationService.GooglePlayVerificationException(
                        GooglePlaySubscriptionVerificationService.GooglePlayVerificationException.Code.PROVIDER_UNAVAILABLE,
                        "Google Play verification unavailable"));

        Map<String, String> request = Map.of(
                "purchaseToken", "token-789",
                "packageName", "com.example.app",
                "productId", "premium_monthly");

        mockMvc.perform(post("/api/subscription/verify/google")
                        .header("X-User-Id", "1")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isServiceUnavailable())
                .andExpect(jsonPath("$.code").value("PROVIDER_UNAVAILABLE"));
    }
}

