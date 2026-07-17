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
import static org.junit.jupiter.api.Assertions.assertTrue;
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

    @Test
    void reconcileNow_shouldPageThroughAllUsers_NotJustTheFirstPage() {
        // Regression: a single PageRequest.of(0, maxUsersPerRun) silently skipped
        // every user beyond the newest N rows - their renewals never extended and
        // their refunds never revoked once subscriber count passed the cap.
        GooglePlaySubscriptionProperties googleProps = new GooglePlaySubscriptionProperties();
        googleProps.setEnabled(true);
        GooglePlaySubscriptionReconciliationProperties smallPageProps =
                new GooglePlaySubscriptionReconciliationProperties();
        smallPageProps.setEnabled(true);
        smallPageProps.setMaxUsersPerRun(1);
        GooglePlaySubscriptionReconciliationService pagingService =
                new GooglePlaySubscriptionReconciliationService(
                        googleProps,
                        smallPageProps,
                        verificationService,
                        transactionRepository,
                        planRepository,
                        Clock.fixed(now, ZoneOffset.UTC));

        PaymentTransaction tx1 = buildGoogleTx("google:token-page-1", "PREMIUM");
        PaymentTransaction tx2 = buildGoogleTx("google:token-page-2", "PREMIUM");
        tx2.getUser().setId(43L);
        when(transactionRepository.findLatestByProviderPerUser(eq("GOOGLE_IAP"), any(Pageable.class)))
                .thenReturn(List.of(tx1))
                .thenReturn(List.of(tx2))
                .thenReturn(List.of());

        for (String token : List.of("token-page-1", "token-page-2")) {
            GooglePlaySubscriptionVerificationService.VerificationResult snapshot =
                    new GooglePlaySubscriptionVerificationService.VerificationResult(
                            "com.VocabMaster",
                            token,
                            "SUBSCRIPTION_STATE_ACTIVE",
                            "order-" + token,
                            now.plusSeconds(3600),
                            List.of("pro_monthly_subscription"));
            when(verificationService.fetchSubscriptionState(token, null)).thenReturn(snapshot);
            when(verificationService.resolvePlanName(snapshot, null)).thenReturn("PREMIUM");
        }
        when(verificationService.isStateEligibleForAccess("SUBSCRIPTION_STATE_ACTIVE")).thenReturn(true);
        when(planRepository.findByName("PREMIUM")).thenReturn(Optional.of(tx1.getPlan()));

        pagingService.reconcileNow();

        assertEquals("PREMIUM", tx1.getUser().getAiPlanCode());
        assertEquals("PREMIUM", tx2.getUser().getAiPlanCode());
        assertEquals(PaymentTransaction.Status.SUCCESS, tx1.getStatus());
        assertEquals(PaymentTransaction.Status.SUCCESS, tx2.getStatus());
    }

    @Test
    void reconcileNow_shouldHonorGoogleExpiryExactly_WhenTrustVerifiedExpiryEnabled() {
        // Production billing-truth mode: a canceled-but-paid-up subscription must
        // end exactly at Google's expiry, not get pushed to now+30d on every run.
        GooglePlaySubscriptionProperties trustProps = new GooglePlaySubscriptionProperties();
        trustProps.setEnabled(true);
        trustProps.setTrustVerifiedExpiry(true);
        GooglePlaySubscriptionReconciliationProperties reconciliationProps =
                new GooglePlaySubscriptionReconciliationProperties();
        reconciliationProps.setEnabled(true);
        reconciliationProps.setMaxUsersPerRun(50);
        GooglePlaySubscriptionReconciliationService trustingService =
                new GooglePlaySubscriptionReconciliationService(
                        trustProps,
                        reconciliationProps,
                        verificationService,
                        transactionRepository,
                        planRepository,
                        Clock.fixed(now, ZoneOffset.UTC));

        PaymentTransaction tx = buildGoogleTx("google:token-trust", "PREMIUM");
        when(transactionRepository.findLatestByProviderPerUser(eq("GOOGLE_IAP"), any(Pageable.class)))
                .thenReturn(List.of(tx));

        Instant expiry = now.plusSeconds(5 * 24 * 3600);
        GooglePlaySubscriptionVerificationService.VerificationResult snapshot =
                new GooglePlaySubscriptionVerificationService.VerificationResult(
                        "com.VocabMaster",
                        "token-trust",
                        "SUBSCRIPTION_STATE_CANCELED",
                        "order-trust",
                        expiry,
                        List.of("pro_monthly_subscription"));
        when(verificationService.fetchSubscriptionState("token-trust", null)).thenReturn(snapshot);
        when(verificationService.resolvePlanName(snapshot, null)).thenReturn("PREMIUM");
        when(verificationService.isStateEligibleForAccess("SUBSCRIPTION_STATE_CANCELED")).thenReturn(false);
        when(planRepository.findByName("PREMIUM")).thenReturn(Optional.of(tx.getPlan()));

        trustingService.reconcileNow();

        assertEquals(PaymentTransaction.Status.SUCCESS, tx.getStatus());
        assertEquals(LocalDateTime.ofInstant(expiry, ZoneOffset.UTC), tx.getUser().getSubscriptionEndDate());
    }

    @Test
    void reconcilePurchaseToken_shouldFetchLatestMatchingGoogleTransaction() {
        PaymentTransaction tx = buildGoogleTx("google:token-rtdn", "PREMIUM");
        when(transactionRepository.findLatestByProviderAndTransactionIdsWithUserAndPlan(
                eq("GOOGLE_IAP"),
                eq(List.of("google:token-rtdn", "token-rtdn")),
                any(Pageable.class)))
                .thenReturn(List.of(tx));

        Instant expiry = now.plusSeconds(3600);
        GooglePlaySubscriptionVerificationService.VerificationResult snapshot =
                new GooglePlaySubscriptionVerificationService.VerificationResult(
                        "com.VocabMaster",
                        "token-rtdn",
                        "SUBSCRIPTION_STATE_ACTIVE",
                        "order-rtdn",
                        expiry,
                        List.of("pro_monthly_subscription"));
        when(verificationService.fetchSubscriptionState("token-rtdn", null)).thenReturn(snapshot);
        when(verificationService.resolvePlanName(snapshot, null)).thenReturn("PREMIUM");
        when(verificationService.isStateEligibleForAccess("SUBSCRIPTION_STATE_ACTIVE")).thenReturn(true);
        when(planRepository.findByName("PREMIUM")).thenReturn(Optional.of(tx.getPlan()));

        assertTrue(reconciliationService.reconcilePurchaseToken("token-rtdn"));
        assertEquals(PaymentTransaction.Status.SUCCESS, tx.getStatus());
        assertEquals("PREMIUM", tx.getUser().getAiPlanCode());
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
