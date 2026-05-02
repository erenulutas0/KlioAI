package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.config.GooglePlaySubscriptionProperties;
import com.ingilizce.calismaapp.config.GooglePlaySubscriptionReconciliationProperties;
import com.ingilizce.calismaapp.entity.PaymentTransaction;
import com.ingilizce.calismaapp.entity.SubscriptionPlan;
import com.ingilizce.calismaapp.entity.User;
import com.ingilizce.calismaapp.repository.PaymentTransactionRepository;
import com.ingilizce.calismaapp.repository.SubscriptionPlanRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.Pageable;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class GooglePlaySubscriptionReconciliationServiceTest {

    @Mock
    private GooglePlaySubscriptionVerificationService verificationService;
    @Mock
    private PaymentTransactionRepository transactionRepository;
    @Mock
    private SubscriptionPlanRepository planRepository;

    private GooglePlaySubscriptionReconciliationService reconciliationService;
    private Instant now;

    @BeforeEach
    void setUp() {
        GooglePlaySubscriptionProperties googleProps = new GooglePlaySubscriptionProperties();
        googleProps.setEnabled(true);
        googleProps.setAcceptGracePeriod(true);
        googleProps.setAcceptOnHold(false);

        GooglePlaySubscriptionReconciliationProperties reconciliationProps =
                new GooglePlaySubscriptionReconciliationProperties();
        reconciliationProps.setEnabled(true);
        reconciliationProps.setMaxUsersPerRun(50);

        now = Instant.parse("2026-02-23T12:00:00Z");
        Clock fixedClock = Clock.fixed(now, ZoneOffset.UTC);

        reconciliationService = new GooglePlaySubscriptionReconciliationService(
                googleProps,
                reconciliationProps,
                verificationService,
                transactionRepository,
                planRepository,
                fixedClock);
    }

    @Test
    void reconcileNow_shouldKeepPremiumWhenCanceledButNotExpired() {
        PaymentTransaction tx = buildGoogleTx("google:token-cancel", "PREMIUM");
        when(transactionRepository.findLatestByProviderPerUser(eq("GOOGLE_IAP"), any(Pageable.class)))
                .thenReturn(List.of(tx));

        Instant expiry = now.plusSeconds(3600);
        GooglePlaySubscriptionVerificationService.VerificationResult snapshot =
                new GooglePlaySubscriptionVerificationService.VerificationResult(
                        "com.VocabMaster",
                        "token-cancel",
                        "SUBSCRIPTION_STATE_CANCELED",
                        "order-1",
                        expiry,
                        List.of("pro_monthly_subscription"));
        when(verificationService.fetchSubscriptionState("token-cancel", null)).thenReturn(snapshot);
        when(verificationService.resolvePlanName(snapshot, null)).thenReturn("PREMIUM");
        when(verificationService.isStateEligibleForAccess("SUBSCRIPTION_STATE_CANCELED")).thenReturn(false);
        when(planRepository.findByName("PREMIUM")).thenReturn(Optional.of(tx.getPlan()));

        reconciliationService.reconcileNow();

        assertEquals(PaymentTransaction.Status.SUCCESS, tx.getStatus());
        assertEquals("PREMIUM", tx.getUser().getAiPlanCode());
        assertEquals(LocalDateTime.ofInstant(now, ZoneOffset.UTC).plusDays(30), tx.getUser().getSubscriptionEndDate());
    }

    @Test
    void reconcileNow_shouldDowngradeWhenRevoked() {
        PaymentTransaction tx = buildGoogleTx("google:token-revoked", "PREMIUM_PLUS");
        tx.getUser().setAiPlanCode("PREMIUM_PLUS");
        tx.getUser().setSubscriptionEndDate(LocalDateTime.now().plusDays(30));
        when(transactionRepository.findLatestByProviderPerUser(eq("GOOGLE_IAP"), any(Pageable.class)))
                .thenReturn(List.of(tx));

        Instant expiry = now.plusSeconds(7200);
        GooglePlaySubscriptionVerificationService.VerificationResult snapshot =
                new GooglePlaySubscriptionVerificationService.VerificationResult(
                        "com.VocabMaster",
                        "token-revoked",
                        "SUBSCRIPTION_STATE_REVOKED",
                        "order-2",
                        expiry,
                        List.of("premium_plus_monthly"));
        when(verificationService.fetchSubscriptionState("token-revoked", null)).thenReturn(snapshot);
        when(verificationService.resolvePlanName(snapshot, null)).thenReturn("PREMIUM_PLUS");
        when(planRepository.findByName("PREMIUM_PLUS")).thenReturn(Optional.of(tx.getPlan()));

        reconciliationService.reconcileNow();

        assertEquals(PaymentTransaction.Status.REFUNDED, tx.getStatus());
        assertEquals("FREE", tx.getUser().getAiPlanCode());
        assertEquals(LocalDateTime.ofInstant(now, ZoneOffset.UTC), tx.getUser().getSubscriptionEndDate());
    }

    @Test
    void reconcileNow_shouldMarkFailedWhenTokenInvalidAndSubscriptionExpiredLocally() {
        PaymentTransaction tx = buildGoogleTx("google:token-invalid", "PREMIUM");
        tx.getUser().setAiPlanCode("PREMIUM");
        tx.getUser().setSubscriptionEndDate(LocalDateTime.ofInstant(now.minusSeconds(10), ZoneOffset.UTC));
        when(transactionRepository.findLatestByProviderPerUser(eq("GOOGLE_IAP"), any(Pageable.class)))
                .thenReturn(List.of(tx));

        when(verificationService.fetchSubscriptionState("token-invalid", null))
                .thenThrow(new GooglePlaySubscriptionVerificationService.GooglePlayVerificationException(
                        GooglePlaySubscriptionVerificationService.GooglePlayVerificationException.Code.INVALID_PURCHASE,
                        "token rejected"));

        reconciliationService.reconcileNow();

        assertEquals(PaymentTransaction.Status.FAILED, tx.getStatus());
        assertEquals("FREE", tx.getUser().getAiPlanCode());
        assertNull(tx.getUser().getSubscriptionEndDate());
    }

    private PaymentTransaction buildGoogleTx(String transactionId, String planName) {
        SubscriptionPlan plan = new SubscriptionPlan();
        plan.setId(10L);
        plan.setName(planName);
        plan.setPrice(BigDecimal.valueOf(20));
        plan.setDurationDays(30);

        User user = new User();
        user.setId(42L);
        user.setAiPlanCode("FREE");
        user.setSubscriptionEndDate(null);

        PaymentTransaction tx = new PaymentTransaction();
        tx.setTransactionId(transactionId);
        tx.setProvider("GOOGLE_IAP");
        tx.setPlan(plan);
        tx.setUser(user);
        tx.setAmount(BigDecimal.valueOf(20));
        tx.setStatus(PaymentTransaction.Status.SUCCESS);
        return tx;
    }
}
