package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.config.AiTokenQuotaProperties;
import com.ingilizce.calismaapp.entity.User;
import com.ingilizce.calismaapp.repository.UserRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.LocalDateTime;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class AiEntitlementServiceTest {

    @Mock
    private UserRepository userRepository;

    private AiEntitlementService aiEntitlementService;

    @BeforeEach
    void setUp() {
        AiTokenQuotaProperties properties = new AiTokenQuotaProperties();
        properties.setTrialDurationDays(7);
        properties.setTrialDailyTokenQuotaPerUser(25_000);
        properties.setFreeDailyTokenQuotaPerUser(0);
        properties.setPremiumDailyTokenQuotaPerUser(50_000);
        properties.setPremiumPlusDailyTokenQuotaPerUser(100_000);
        aiEntitlementService = new AiEntitlementService(userRepository, properties);
    }

    @Test
    void resolve_ShouldReturnTrialPlan_WhenUserIsInsideTrialWindow() {
        User user = new User();
        user.setCreatedAt(LocalDateTime.now().minusDays(2));
        user.setSubscriptionEndDate(LocalDateTime.now().minusDays(1));
        when(userRepository.findById(1L)).thenReturn(Optional.of(user));

        AiEntitlementService.Entitlement entitlement = aiEntitlementService.resolve(1L);

        assertEquals(AiPlanTier.FREE_TRIAL_7D, entitlement.planTier());
        assertTrue(entitlement.aiAccessEnabled());
        assertEquals(25_000, entitlement.dailyTokenLimit());
        assertTrue(entitlement.trialActive());
        assertTrue(entitlement.trialDaysRemaining() > 0);
    }

    @Test
    void resolve_ShouldReturnFree_WhenTrialExpiredAndNoSubscription() {
        User user = new User();
        user.setCreatedAt(LocalDateTime.now().minusDays(20));
        user.setSubscriptionEndDate(LocalDateTime.now().minusDays(1));
        when(userRepository.findById(2L)).thenReturn(Optional.of(user));

        AiEntitlementService.Entitlement entitlement = aiEntitlementService.resolve(2L);

        assertEquals(AiPlanTier.FREE, entitlement.planTier());
        assertFalse(entitlement.aiAccessEnabled());
        assertEquals(0, entitlement.dailyTokenLimit());
        assertFalse(entitlement.trialActive());
        assertEquals(0, entitlement.trialDaysRemaining());
    }

    @Test
    void resolve_ShouldReturnFree_WhenTrialIsMarkedIneligible() {
        User user = new User();
        user.setTrialEligible(false);
        user.setCreatedAt(LocalDateTime.now().minusDays(2));
        user.setSubscriptionEndDate(LocalDateTime.now().minusDays(1));
        when(userRepository.findById(22L)).thenReturn(Optional.of(user));

        AiEntitlementService.Entitlement entitlement = aiEntitlementService.resolve(22L);

        assertEquals(AiPlanTier.FREE, entitlement.planTier());
        assertFalse(entitlement.aiAccessEnabled());
        assertFalse(entitlement.trialActive());
        assertEquals(0, entitlement.trialDaysRemaining());
    }

    @Test
    void resolve_ShouldReturnPremiumPlus_WhenSubscriptionActiveAndPlanPlus() {
        User user = new User();
        user.setAiPlanCode("PREMIUM_PLUS");
        user.setCreatedAt(LocalDateTime.now().minusDays(100));
        user.setSubscriptionEndDate(LocalDateTime.now().plusDays(10));
        when(userRepository.findById(3L)).thenReturn(Optional.of(user));

        AiEntitlementService.Entitlement entitlement = aiEntitlementService.resolve(3L);

        assertEquals(AiPlanTier.PREMIUM_PLUS, entitlement.planTier());
        assertTrue(entitlement.aiAccessEnabled());
        assertEquals(100_000, entitlement.dailyTokenLimit());
    }

    @Test
    void resolve_ShouldFallbackToPremium_WhenSubscriptionActiveButPlanMissing() {
        User user = new User();
        user.setAiPlanCode("FREE");
        user.setCreatedAt(LocalDateTime.now().minusDays(50));
        user.setSubscriptionEndDate(LocalDateTime.now().plusDays(7));
        when(userRepository.findById(4L)).thenReturn(Optional.of(user));

        AiEntitlementService.Entitlement entitlement = aiEntitlementService.resolve(4L);

        assertEquals(AiPlanTier.PREMIUM, entitlement.planTier());
        assertTrue(entitlement.aiAccessEnabled());
        assertEquals(50_000, entitlement.dailyTokenLimit());
    }
}
