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
import java.util.List;
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

    // Hard backstop against a runaway loop, far above any realistic subscriber
    // count for now (50 pages x default 200 = 10k users per run).
    private static final int MAX_PAGES_PER_RUN = 50;

    @Transactional
    public void reconcileNow() {
        if (!reconciliationProperties.isEnabled()) {
            return;
        }
        if (!googleProperties.isEnabled()) {
            return;
        }

        // Page through EVERY user's latest Google transaction. A single fixed
        // page ordered by id DESC silently skipped everyone beyond the newest
        // maxUsersPerRun rows - those users' renewals never extended and their
        // refunds never revoked once the subscriber count passed the cap.
        int pageSize = Math.max(1, reconciliationProperties.getMaxUsersPerRun());
        Instant now = clock.instant();
        int checkedCount = 0;
        int successCount = 0;
        int failCount = 0;

        for (int page = 0; page < MAX_PAGES_PER_RUN; page++) {
            var candidates = transactionRepository.findLatestByProviderPerUser(
                    GOOGLE_PROVIDER,
                    PageRequest.of(page, pageSize));
            if (candidates.isEmpty()) {
                break;
            }

            for (PaymentTransaction tx : candidates) {
                checkedCount++;
                if (reconcileTransaction(tx, now)) {
                    successCount++;
                } else {
                    failCount++;
                }
            }

            if (candidates.size() < pageSize) {
                break;
            }
            if (page == MAX_PAGES_PER_RUN - 1) {
                log.warn("Google reconciliation hit MAX_PAGES_PER_RUN={} (pageSize={}); "
                                + "remaining users NOT reconciled this run - raise the cap or page size.",
                        MAX_PAGES_PER_RUN, pageSize);
            }
        }

        if (checkedCount == 0) {
            return;
        }

        log.info("Google reconciliation finished: checked={}, success={}, failed={}",
                checkedCount,
                successCount,
                failCount);
    }

    @Transactional
    public boolean reconcilePurchaseToken(String purchaseToken) {
        if (!googleProperties.isEnabled()) {
            return false;
        }

        String normalizedToken = normalizePurchaseToken(purchaseToken);
        if (normalizedToken.isBlank()) {
            return false;
        }

        List<PaymentTransaction> transactions =
                transactionRepository.findLatestByProviderAndTransactionIdsWithUserAndPlan(
                        GOOGLE_PROVIDER,
                        List.of(GOOGLE_TX_PREFIX + normalizedToken, normalizedToken),
                        PageRequest.of(0, 1));

        if (transactions.isEmpty()) {
            log.warn("Google RTDN received unknown purchase token hash={}", Integer.toHexString(normalizedToken.hashCode()));
            return false;
        }

        return reconcileTransaction(transactions.get(0), clock.instant());
    }

    private boolean reconcileTransaction(PaymentTransaction tx, Instant now) {
        String purchaseToken = extractPurchaseToken(tx.getTransactionId());
        if (purchaseToken.isBlank()) {
            log.warn("Skipping Google tx id={} due to missing purchase token format", tx.getId());
            return false;
        }

        try {
            GooglePlaySubscriptionVerificationService.VerificationResult snapshot =
                    verificationService.fetchSubscriptionState(purchaseToken, null);
            applySnapshot(tx, snapshot, now);
            return true;
        } catch (GooglePlaySubscriptionVerificationService.GooglePlayVerificationException ex) {
            if (ex.getCode() == GooglePlaySubscriptionVerificationService.GooglePlayVerificationException.Code.INVALID_PURCHASE) {
                handleInvalidPurchase(tx, now);
                return false;
            }
            log.warn("Google reconcile provider error txId={}, userId={}, code={}, message={}",
                    tx.getId(),
                    tx.getUser() != null ? tx.getUser().getId() : null,
                    ex.getCode(),
                    ex.getMessage());
            return false;
        } catch (Exception ex) {
            log.warn("Google reconcile unexpected error txId={}, userId={}",
                    tx.getId(),
                    tx.getUser() != null ? tx.getUser().getId() : null,
                    ex);
            return false;
        }
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
        LocalDateTime currentEnd = user.getSubscriptionEndDate();
        if (googleProperties.isTrustVerifiedExpiry() && verifiedExpiry != null) {
            // Google is the billing source of truth: the paid-until date is
            // exactly what the user is entitled to. The legacy now+duration
            // floor below pushed EVERY access-eligible subscription (including
            // canceled-but-not-yet-expired ones) to at least 30 days out on
            // every reconcile run, gifting up to a month past the real expiry.
            // Never shrink an end date the user was already shown.
            LocalDateTime verifiedEnd = LocalDateTime.ofInstant(verifiedExpiry, ZoneOffset.UTC);
            return currentEnd != null && currentEnd.isAfter(verifiedEnd) ? currentEnd : verifiedEnd;
        }
        LocalDateTime nowUtc = LocalDateTime.ofInstant(now, ZoneOffset.UTC);
        LocalDateTime resolved = nowUtc.plusDays(resolveEffectiveDurationDays(plan));
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
        AiPlanTier tier = AiPlanTier.fromSubscriptionPlanName(plan.getName());
        if (tier == AiPlanTier.FREE) {
            // Same guard as SubscriptionController.resolveAiPlanCode: the name
            // mapping is substring-based, so a paid plan named without
            // PRO/PREMIUM/PLUS would silently downgrade a paying user to FREE.
            log.warn("AI_PLAN_MAPPING_FALLBACK: subscription plan '{}' resolved to FREE ai tier - "
                    + "check AiPlanTier.fromSubscriptionPlanName mapping", plan.getName());
        }
        return tier.name();
    }

    private String extractPurchaseToken(String transactionId) {
        String value = normalizePurchaseToken(transactionId);
        if (value.regionMatches(true, 0, GOOGLE_TX_PREFIX, 0, GOOGLE_TX_PREFIX.length())) {
            return value.substring(GOOGLE_TX_PREFIX.length()).trim();
        }
        return value;
    }

    private String normalizePurchaseToken(String transactionId) {
        if (transactionId == null || transactionId.isBlank()) {
            return "";
        }
        return transactionId.trim();
    }

    private String normalizeState(String state) {
        if (state == null) {
            return "";
        }
        return state.trim().toUpperCase(Locale.ROOT);
    }
}
