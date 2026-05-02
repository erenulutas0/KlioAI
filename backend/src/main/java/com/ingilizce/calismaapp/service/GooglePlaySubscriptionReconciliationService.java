package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.config.GooglePlaySubscriptionProperties;
import com.ingilizce.calismaapp.config.GooglePlaySubscriptionReconciliationProperties;
import com.ingilizce.calismaapp.entity.PaymentTransaction;
import com.ingilizce.calismaapp.entity.SubscriptionPlan;
import com.ingilizce.calismaapp.entity.User;
import com.ingilizce.calismaapp.repository.PaymentTransactionRepository;
import com.ingilizce.calismaapp.repository.SubscriptionPlanRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.domain.PageRequest;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.Locale;
import java.util.Optional;
import java.util.Set;

@Service
public class GooglePlaySubscriptionReconciliationService {
    private static final Logger log = LoggerFactory.getLogger(GooglePlaySubscriptionReconciliationService.class);
    private static final String GOOGLE_PROVIDER = "GOOGLE_IAP";
    private static final String GOOGLE_TX_PREFIX = "google:";

    private static final Set<String> CANCELED_STATES = Set.of(
            "SUBSCRIPTION_STATE_CANCELED",
            "SUBSCRIPTION_STATE_CANCELLED");
    private static final Set<String> REVOKED_STATES = Set.of("SUBSCRIPTION_STATE_REVOKED");
    private static final Set<String> EXPIRED_STATES = Set.of("SUBSCRIPTION_STATE_EXPIRED");

    private final GooglePlaySubscriptionProperties googleProperties;
    private final GooglePlaySubscriptionReconciliationProperties reconciliationProperties;
    private final GooglePlaySubscriptionVerificationService verificationService;
    private final PaymentTransactionRepository transactionRepository;
    private final SubscriptionPlanRepository planRepository;
    private final Clock clock;

    @Autowired
    public GooglePlaySubscriptionReconciliationService(
            GooglePlaySubscriptionProperties googleProperties,
            GooglePlaySubscriptionReconciliationProperties reconciliationProperties,
            GooglePlaySubscriptionVerificationService verificationService,
            PaymentTransactionRepository transactionRepository,
            SubscriptionPlanRepository planRepository) {
        this(
                googleProperties,
                reconciliationProperties,
                verificationService,
                transactionRepository,
                planRepository,
                Clock.systemUTC());
    }

    GooglePlaySubscriptionReconciliationService(
            GooglePlaySubscriptionProperties googleProperties,
            GooglePlaySubscriptionReconciliationProperties reconciliationProperties,
            GooglePlaySubscriptionVerificationService verificationService,
            PaymentTransactionRepository transactionRepository,
            SubscriptionPlanRepository planRepository,
            Clock clock) {
        this.googleProperties = googleProperties;
        this.reconciliationProperties = reconciliationProperties;
        this.verificationService = verificationService;
        this.transactionRepository = transactionRepository;
        this.planRepository = planRepository;
        this.clock = clock;
    }

    @Scheduled(cron = "${app.subscription.google-play.reconciliation.cron:0 */30 * * * *}", zone = "UTC")
    public void reconcileScheduled() {
        if (!reconciliationProperties.isEnabled()) {
            return;
        }
        try {
            reconcileNow();
        } catch (Exception ex) {
            log.error("Google Play reconciliation run failed", ex);
        }
    }

    @Transactional
    public void reconcileNow() {
        if (!reconciliationProperties.isEnabled()) {
            return;
        }
        if (!googleProperties.isEnabled()) {
            return;
        }

        int maxUsers = Math.max(1, reconciliationProperties.getMaxUsersPerRun());
        var candidates = transactionRepository.findLatestByProviderPerUser(
                GOOGLE_PROVIDER,
                PageRequest.of(0, maxUsers));

        if (candidates.isEmpty()) {
            return;
        }

        Instant now = clock.instant();
        int successCount = 0;
        int failCount = 0;

        for (PaymentTransaction tx : candidates) {
            String purchaseToken = extractPurchaseToken(tx.getTransactionId());
            if (purchaseToken.isBlank()) {
                log.warn("Skipping Google tx id={} due to missing purchase token format", tx.getId());
                failCount++;
                continue;
            }

            try {
                GooglePlaySubscriptionVerificationService.VerificationResult snapshot =
                        verificationService.fetchSubscriptionState(purchaseToken, null);
                applySnapshot(tx, snapshot, now);
                successCount++;
            } catch (GooglePlaySubscriptionVerificationService.GooglePlayVerificationException ex) {
                if (ex.getCode() == GooglePlaySubscriptionVerificationService.GooglePlayVerificationException.Code.INVALID_PURCHASE) {
                    handleInvalidPurchase(tx, now);
                    failCount++;
                    continue;
                }
                log.warn("Google reconcile provider error txId={}, userId={}, code={}, message={}",
                        tx.getId(),
                        tx.getUser() != null ? tx.getUser().getId() : null,
                        ex.getCode(),
                        ex.getMessage());
                failCount++;
            } catch (Exception ex) {
                log.warn("Google reconcile unexpected error txId={}, userId={}",
                        tx.getId(),
                        tx.getUser() != null ? tx.getUser().getId() : null,
                        ex);
                failCount++;
            }
        }

        log.info("Google reconciliation finished: checked={}, success={}, failed={}",
                candidates.size(),
                successCount,
                failCount);
    }

    private void applySnapshot(PaymentTransaction tx,
                               GooglePlaySubscriptionVerificationService.VerificationResult snapshot,
                               Instant now) {
        User user = tx.getUser();
        if (user == null) {
            return;
        }

        SubscriptionPlan effectivePlan = resolveEffectivePlan(tx, snapshot);
        String state = normalizeState(snapshot.subscriptionState());
        Instant expiry = snapshot.expiryTime();
        boolean hasFutureExpiry = expiry != null && expiry.isAfter(now);
        boolean forceRevoke = REVOKED_STATES.contains(state);
        boolean expiredState = EXPIRED_STATES.contains(state);
        boolean canceledWithFutureExpiry = CANCELED_STATES.contains(state) && hasFutureExpiry;
        boolean stateAllowsAccess =
                verificationService.isStateEligibleForAccess(state) || canceledWithFutureExpiry;
        boolean accessEnabled = !forceRevoke && !expiredState && hasFutureExpiry && stateAllowsAccess;

        if (forceRevoke) {
            tx.setStatus(PaymentTransaction.Status.REFUNDED);
            downgradeUserNow(user, now);
            log.info("Google reconcile revoked access userId={}, txId={}", user.getId(), tx.getId());
            return;
        }

        if (accessEnabled) {
            tx.setStatus(PaymentTransaction.Status.SUCCESS);
            user.setAiPlanCode(resolveAiPlanCode(effectivePlan));
            user.setSubscriptionEndDate(resolveReconciledSubscriptionEnd(user, effectivePlan, expiry, now));
            return;
        }

        LocalDateTime currentEnd = user.getSubscriptionEndDate();
        LocalDateTime nowUtc = LocalDateTime.ofInstant(now, ZoneOffset.UTC);
        if (currentEnd != null && currentEnd.isAfter(nowUtc)) {
            tx.setStatus(PaymentTransaction.Status.SUCCESS);
            log.info("Google reconcile preserved active local entitlement userId={}, txId={}, state={}, expiry={}, end={}",
                    user.getId(), tx.getId(), state, expiry, currentEnd);
            return;
        }

        boolean blockedByState = hasFutureExpiry && !stateAllowsAccess;
        if (blockedByState) {
            tx.setStatus(PaymentTransaction.Status.PENDING);
            downgradeUserNow(user, now);
            log.info("Google reconcile blocked by state userId={}, txId={}, state={}", user.getId(), tx.getId(), state);
            return;
        }

        tx.setStatus(PaymentTransaction.Status.FAILED);
        downgradeUserNow(user, now);
        log.info("Google reconcile marked inactive userId={}, txId={}, state={}, expiry={}",
                user.getId(), tx.getId(), state, expiry);
    }

    private void handleInvalidPurchase(PaymentTransaction tx, Instant now) {
        User user = tx.getUser();
        if (user == null) {
            return;
        }
        tx.setStatus(PaymentTransaction.Status.FAILED);

        LocalDateTime nowUtc = LocalDateTime.ofInstant(now, ZoneOffset.UTC);
        LocalDateTime currentEnd = user.getSubscriptionEndDate();
        if (currentEnd == null || !currentEnd.isAfter(nowUtc)) {
            user.setSubscriptionEndDate(null);
            user.setAiPlanCode(AiPlanTier.FREE.name());
        }
    }

    private SubscriptionPlan resolveEffectivePlan(
            PaymentTransaction tx,
            GooglePlaySubscriptionVerificationService.VerificationResult snapshot) {
        String resolvedPlanName = verificationService.resolvePlanName(snapshot, null);
        if (resolvedPlanName == null || resolvedPlanName.isBlank()) {
            return tx.getPlan();
        }
        Optional<SubscriptionPlan> mapped = planRepository.findByName(resolvedPlanName);
        if (mapped.isEmpty()) {
            log.warn("Google reconcile mapped plan not found: {} (txId={})", resolvedPlanName, tx.getId());
            return tx.getPlan();
        }
        SubscriptionPlan mappedPlan = mapped.get();
        if (tx.getPlan() == null || !mappedPlan.getId().equals(tx.getPlan().getId())) {
            tx.setPlan(mappedPlan);
        }
        return mappedPlan;
    }

    private void downgradeUserNow(User user, Instant now) {
        user.setSubscriptionEndDate(LocalDateTime.ofInstant(now, ZoneOffset.UTC));
        user.setAiPlanCode(AiPlanTier.FREE.name());
    }

    private LocalDateTime resolveReconciledSubscriptionEnd(
            User user,
            SubscriptionPlan plan,
            Instant verifiedExpiry,
            Instant now) {
        LocalDateTime nowUtc = LocalDateTime.ofInstant(now, ZoneOffset.UTC);
        LocalDateTime resolved = nowUtc.plusDays(resolveEffectiveDurationDays(plan));
        LocalDateTime currentEnd = user.getSubscriptionEndDate();
        if (currentEnd != null && currentEnd.isAfter(resolved)) {
            resolved = currentEnd;
        }
        if (verifiedExpiry != null) {
            LocalDateTime verifiedEnd = LocalDateTime.ofInstant(verifiedExpiry, ZoneOffset.UTC);
            if (verifiedEnd.isAfter(resolved)) {
                resolved = verifiedEnd;
            }
        }
        return resolved;
    }

    private int resolveEffectiveDurationDays(SubscriptionPlan plan) {
        if (plan == null || plan.getDurationDays() == null || plan.getDurationDays() < 1) {
            return 30;
        }
        return Math.max(30, plan.getDurationDays());
    }

    private String resolveAiPlanCode(SubscriptionPlan plan) {
        if (plan == null) {
            return AiPlanTier.FREE.name();
        }
        return AiPlanTier.fromSubscriptionPlanName(plan.getName()).name();
    }

    private String extractPurchaseToken(String transactionId) {
        if (transactionId == null || transactionId.isBlank()) {
            return "";
        }
        String value = transactionId.trim();
        if (value.regionMatches(true, 0, GOOGLE_TX_PREFIX, 0, GOOGLE_TX_PREFIX.length())) {
            return value.substring(GOOGLE_TX_PREFIX.length()).trim();
        }
        return value;
    }

    private String normalizeState(String state) {
        if (state == null) {
            return "";
        }
        return state.trim().toUpperCase(Locale.ROOT);
    }
}
