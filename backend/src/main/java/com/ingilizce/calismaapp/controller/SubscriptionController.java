package com.ingilizce.calismaapp.controller;

import com.ingilizce.calismaapp.entity.PaymentTransaction;
import com.ingilizce.calismaapp.entity.SubscriptionPlan;
import com.ingilizce.calismaapp.entity.User;
import com.ingilizce.calismaapp.repository.PaymentTransactionRepository;
import com.ingilizce.calismaapp.repository.SubscriptionPlanRepository;
import com.ingilizce.calismaapp.repository.UserRepository;
import com.ingilizce.calismaapp.service.AiPlanTier;
import com.ingilizce.calismaapp.service.GooglePlaySubscriptionVerificationService;
import com.ingilizce.calismaapp.service.IyzicoService;
import com.ingilizce.calismaapp.security.CurrentUserContext;
// iyzico SDK removed
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

@RestController
@RequestMapping("/api/subscription")
public class SubscriptionController {
    private static final Logger log = LoggerFactory.getLogger(SubscriptionController.class);
    private static final int STANDARD_SUBSCRIPTION_DAYS = 30;

    private final SubscriptionPlanRepository planRepository;
    private final UserRepository userRepository;
    private final PaymentTransactionRepository transactionRepository;
    private final IyzicoService iyzicoService;
    private final GooglePlaySubscriptionVerificationService googlePlaySubscriptionVerificationService;
    private final CurrentUserContext currentUserContext;
    @Value("${app.subscription.mock-verification-enabled:true}")
    private boolean mockVerificationEnabled;

    public SubscriptionController(SubscriptionPlanRepository planRepository,
            UserRepository userRepository,
            PaymentTransactionRepository transactionRepository,
            IyzicoService iyzicoService,
            GooglePlaySubscriptionVerificationService googlePlaySubscriptionVerificationService,
            CurrentUserContext currentUserContext) {
        this.planRepository = planRepository;
        this.userRepository = userRepository;
        this.transactionRepository = transactionRepository;
        this.iyzicoService = iyzicoService;
        this.googlePlaySubscriptionVerificationService = googlePlaySubscriptionVerificationService;
        this.currentUserContext = currentUserContext;
    }

    @GetMapping("/plans")
    public List<SubscriptionPlan> getPlans() {
        return planRepository.findAll();
    }

    @PostMapping("/pay/iyzico")
    public ResponseEntity<Map<String, Object>> initializeIyzico(
            @RequestBody Map<String, Object> request,
            @RequestHeader("X-User-Id") Long userId) {
        if (!mockVerificationEnabled) {
            return ResponseEntity.status(HttpStatus.NOT_IMPLEMENTED)
                    .body(Map.of("error", "Mock payment flow is disabled in this environment."));
        }

        try {
            Long planId = Long.parseLong(request.get("planId").toString());
            String callbackUrl = request.get("callbackUrl").toString();

            Optional<User> userOpt = userRepository.findById(userId);
            if (userOpt.isEmpty()) {
                return ResponseEntity.badRequest()
                        .body(Map.of("error", "Kullanıcı bulunamadı. Lütfen tekrar giriş yapın."));
            }
            User user = userOpt.get();

            Optional<SubscriptionPlan> planOpt = planRepository.findById(planId);
            if (planOpt.isEmpty()) {
                return ResponseEntity.badRequest()
                        .body(Map.of("error", "Seçilen plan bulunamadı."));
            }
            SubscriptionPlan plan = planOpt.get();

            Map<String, Object> response = iyzicoService.initializePayment(user, plan, callbackUrl);

            if ("success".equals(response.get("status"))) {
                // Log the pending transaction
                PaymentTransaction transaction = new PaymentTransaction();
                transaction.setUser(user);
                transaction.setPlan(plan);
                transaction.setAmount(plan.getPrice());
                transaction.setProvider("IYZICO");
                transaction.setTransactionId(response.get("token").toString());
                transactionRepository.save(transaction);

                return ResponseEntity.ok(Map.of(
                        "checkoutFormContent", response.get("checkoutFormContent"),
                        "token", response.get("token"),
                        "paymentPageUrl", response.get("paymentPageUrl")));
            } else {
                return ResponseEntity.badRequest()
                        .body(Map.of("error", response.getOrDefault("errorMessage", "Ödeme başlatılamadı")));
            }
        } catch (Exception e) {
            return ResponseEntity.internalServerError()
                    .body(Map.of("error", "Ödeme hatası: " + e.getMessage()));
        }
    }

    @PostMapping("/verify/apple")
    public ResponseEntity<Map<String, Object>> verifyApplePurchase(@RequestBody Map<String, String> request,
            @RequestHeader("X-User-Id") Long userId) {
        if (!mockVerificationEnabled) {
            return ResponseEntity.status(HttpStatus.NOT_IMPLEMENTED)
                    .body(Map.of("error", "Mock Apple verification is disabled in this environment."));
        }
        try {
            Optional<User> userOpt = userRepository.findById(userId);
            if (userOpt.isEmpty()) {
                return ResponseEntity.internalServerError().body(Map.of("error", "User not found"));
            }
            User user = userOpt.get();

            String planName = request.get("planName");

            // In a real scenario, we would verify the receipt with Apple's verifyReceipt API.
            // For demonstration, we simulate success.
            Optional<SubscriptionPlan> planOpt = planRepository.findByName(planName);
            if (planOpt.isEmpty()) {
                return ResponseEntity.internalServerError().body(Map.of("error", "Plan not found"));
            }
            SubscriptionPlan plan = planOpt.get();

            if (isSubscriptionCurrentlyActive(user)) {
                Map<String, Object> payload = new HashMap<>();
                payload.put("message", "Apple IAP already active");
                payload.put("subscriptionEndDate", user.getSubscriptionEndDate());
                payload.put("planName", plan.getName());
                payload.put("idempotent", true);
                return ResponseEntity.ok(payload);
            }

            user.setSubscriptionEndDate(resolveNextSubscriptionEnd(user, plan, null));
            user.setAiPlanCode(resolveAiPlanCode(plan));
            userRepository.save(user);

            return ResponseEntity
                    .ok(Map.of("message", "Apple IAP verified", "subscriptionEndDate", user.getSubscriptionEndDate()));
        } catch (Exception e) {
            return ResponseEntity.internalServerError().body(Map.of("error", e.getMessage()));
        }
    }

    @PostMapping("/verify/google")
    public ResponseEntity<Map<String, Object>> verifyGooglePurchase(@RequestBody Map<String, String> request,
            @RequestHeader("X-User-Id") Long userId) {
        try {
            Optional<User> userOpt = userRepository.findById(userId);
            if (userOpt.isEmpty()) {
                return ResponseEntity.internalServerError().body(Map.of("error", "User not found"));
            }
            User user = userOpt.get();

            if (mockVerificationEnabled) {
                String planName = request.get("planName");
                Optional<SubscriptionPlan> planOpt = planRepository.findByName(planName);
                if (planOpt.isEmpty()) {
                    return ResponseEntity.internalServerError().body(Map.of("error", "Plan not found"));
                }
                SubscriptionPlan plan = planOpt.get();

                if (isSubscriptionCurrentlyActive(user)) {
                    Map<String, Object> payload = new HashMap<>();
                    payload.put("message", "Google IAP already active");
                    payload.put("subscriptionEndDate", user.getSubscriptionEndDate());
                    payload.put("planName", plan.getName());
                    payload.put("idempotent", true);
                    return ResponseEntity.ok(payload);
                }

                user.setSubscriptionEndDate(resolveNextSubscriptionEnd(user, plan, null));
                user.setAiPlanCode(resolveAiPlanCode(plan));
                userRepository.save(user);

                return ResponseEntity.ok(
                        Map.of("message", "Google IAP verified", "subscriptionEndDate", user.getSubscriptionEndDate()));
            }

            String purchaseToken = request.get("purchaseToken");
            String packageName = request.get("packageName");
            String requestedProductId = request.get("productId");
            int purchaseTokenLen = purchaseToken == null ? 0 : purchaseToken.trim().length();
            log.info("Google verify request userId={}, productId={}, packageOverride={}, tokenLen={}",
                    userId,
                    requestedProductId,
                    packageName != null && !packageName.isBlank(),
                    purchaseTokenLen);
            if (purchaseToken == null || purchaseToken.isBlank()) {
                return ResponseEntity.badRequest().body(Map.of("error", "purchaseToken is required"));
            }

            GooglePlaySubscriptionVerificationService.VerificationResult verification = googlePlaySubscriptionVerificationService
                    .verifySubscription(purchaseToken, packageName);

            String resolvedPlanName = googlePlaySubscriptionVerificationService.resolvePlanName(
                    verification,
                    requestedProductId);
            if (resolvedPlanName == null || resolvedPlanName.isBlank()) {
                return ResponseEntity.badRequest().body(
                        Map.of("error", "Unable to map Google product/base plan to internal subscription plan"));
            }

            Optional<SubscriptionPlan> planOpt = planRepository.findByName(resolvedPlanName);
            if (planOpt.isEmpty()) {
                return ResponseEntity.badRequest().body(Map.of("error", "Mapped plan not found: " + resolvedPlanName));
            }
            SubscriptionPlan plan = planOpt.get();

            LocalDateTime verifiedExpiry = verification.expiryTime() != null
                    ? LocalDateTime.ofInstant(verification.expiryTime(), ZoneOffset.UTC)
                    : null;
            user.setSubscriptionEndDate(resolveNextSubscriptionEnd(user, plan, verifiedExpiry));
            user.setAiPlanCode(resolveAiPlanCode(plan));
            userRepository.save(user);

            String transactionId = "google:" + purchaseToken;
            Optional<PaymentTransaction> existingTx = transactionRepository.findByTransactionIdWithUserAndPlan(transactionId);
            if (existingTx.isPresent() && existingTx.get().getStatus() == PaymentTransaction.Status.SUCCESS) {
                PaymentTransaction tx = existingTx.get();
                if (tx.getUser() == null || !userId.equals(tx.getUser().getId())) {
                    tx.setUser(user);
                    tx.setPlan(plan);
                    tx.setAmount(plan.getPrice());
                    tx.setProvider("GOOGLE_IAP");
                    transactionRepository.save(tx);
                }
                Map<String, Object> payload = new HashMap<>();
                payload.put("message", "Google IAP already verified");
                payload.put("subscriptionEndDate", user.getSubscriptionEndDate());
                payload.put("planName", plan.getName());
                payload.put("idempotent", true);
                return ResponseEntity.ok(payload);
            }

            PaymentTransaction tx = existingTx.orElseGet(PaymentTransaction::new);
            tx.setTransactionId(transactionId);
            tx.setUser(user);
            tx.setPlan(plan);
            tx.setAmount(plan.getPrice());
            tx.setProvider("GOOGLE_IAP");
            tx.setStatus(PaymentTransaction.Status.SUCCESS);
            transactionRepository.save(tx);

            Map<String, Object> payload = new HashMap<>();
            payload.put("message", "Google IAP verified");
            payload.put("planName", plan.getName());
            payload.put("subscriptionEndDate", user.getSubscriptionEndDate());
            payload.put("subscriptionState", verification.subscriptionState());
            payload.put("productKeys", verification.productKeys());
            payload.put("latestOrderId", verification.latestOrderId());
            log.info("Google verify success userId={}, productId={}, planName={}, state={}",
                    userId,
                    requestedProductId,
                    plan.getName(),
                    verification.subscriptionState());
            return ResponseEntity.ok(payload);
        } catch (GooglePlaySubscriptionVerificationService.GooglePlayVerificationException e) {
            HttpStatus status = switch (e.getCode()) {
                case INVALID_PURCHASE -> HttpStatus.BAD_REQUEST;
                case MISCONFIGURED -> HttpStatus.INTERNAL_SERVER_ERROR;
                case PROVIDER_UNAVAILABLE -> HttpStatus.SERVICE_UNAVAILABLE;
            };
            log.warn("Google verify failed userId={}, code={}, message={}",
                    userId, e.getCode(), e.getMessage());
            return ResponseEntity.status(status).body(Map.of(
                    "error", e.getMessage(),
                    "code", e.getCode().name()));
        } catch (Exception e) {
            log.error("Google verify unexpected failure userId={}", userId, e);
            return ResponseEntity.internalServerError().body(Map.of("error", e.getMessage()));
        }
    }

    private LocalDateTime resolveNextSubscriptionEnd(User user, SubscriptionPlan plan, LocalDateTime verifiedExpiryUtc) {
        LocalDateTime now = LocalDateTime.now();
        LocalDateTime currentEnd = user.getSubscriptionEndDate();
        int durationDays = resolveEffectiveDurationDays(plan);
        if (verifiedExpiryUtc != null && verifiedExpiryUtc.isAfter(now)) {
            if (currentEnd == null || currentEnd.isBefore(now)) {
                return verifiedExpiryUtc;
            }
            return verifiedExpiryUtc.isAfter(currentEnd) ? verifiedExpiryUtc : currentEnd;
        }
        if (currentEnd == null || currentEnd.isBefore(now)) {
            return now.plusDays(durationDays);
        }
        return currentEnd.plusDays(durationDays);
    }

    private int resolveEffectiveDurationDays(SubscriptionPlan plan) {
        if (plan == null) {
            return STANDARD_SUBSCRIPTION_DAYS;
        }
        AiPlanTier tier = AiPlanTier.fromSubscriptionPlanName(plan.getName());
        if (tier == AiPlanTier.PREMIUM || tier == AiPlanTier.PREMIUM_PLUS) {
            return STANDARD_SUBSCRIPTION_DAYS;
        }
        Integer configuredDuration = plan.getDurationDays();
        if (configuredDuration == null || configuredDuration < 1) {
            return STANDARD_SUBSCRIPTION_DAYS;
        }
        return configuredDuration;
    }

    private boolean isSubscriptionCurrentlyActive(User user) {
        if (user == null) {
            return false;
        }
        LocalDateTime end = user.getSubscriptionEndDate();
        return end != null && end.isAfter(LocalDateTime.now());
    }

    @PostMapping("/callback/iyzico")
    @Transactional
    public ResponseEntity<String> handleCallback(@RequestParam String token) {
        if (!mockVerificationEnabled) {
            return ResponseEntity.status(HttpStatus.NOT_IMPLEMENTED).body("Mock iyzico callback is disabled.");
        }
        // In a real scenario, we would verify the payment with iyzico using the token
        // Here we mark it as success for demonstration once iyzico calls back
        Optional<PaymentTransaction> transactionOpt = transactionRepository.findByTransactionIdWithUserAndPlan(token);
        if (transactionOpt.isEmpty()) {
            return ResponseEntity.badRequest().body("Transaction not found");
        }
        PaymentTransaction transaction = transactionOpt.get();

        if (transaction.getStatus() == PaymentTransaction.Status.SUCCESS) {
            return ResponseEntity.ok("Payment already processed.");
        }

        transaction.setStatus(PaymentTransaction.Status.SUCCESS);
        transactionRepository.save(transaction);

        // Update user subscription
        User user = transaction.getUser();
        int days = resolveEffectiveDurationDays(transaction.getPlan());
        LocalDateTime currentEnd = user.getSubscriptionEndDate();
        if (currentEnd == null || currentEnd.isBefore(LocalDateTime.now())) {
            user.setSubscriptionEndDate(LocalDateTime.now().plusDays(days));
        } else {
            user.setSubscriptionEndDate(currentEnd.plusDays(days));
        }
        user.setAiPlanCode(resolveAiPlanCode(transaction.getPlan()));
        userRepository.save(user);

        return ResponseEntity.ok("Payment successful and subscription updated.");
    }

    /**
     * DEMO/TEST ENDPOINT - Activates subscription without payment
     * WARNING: Only for development/testing. Remove in production!
     */
    @PostMapping("/demo/activate")
    public ResponseEntity<Map<String, Object>> activateDemoSubscription(
            @RequestBody Map<String, Object> request,
            @RequestHeader("X-User-Id") Long userId) {
        if (!mockVerificationEnabled) {
            return ResponseEntity.status(HttpStatus.NOT_IMPLEMENTED)
                    .body(Map.of("error", "Demo activation is disabled in this environment."));
        }
        if (currentUserContext.shouldEnforceAuthz() && !currentUserContext.hasRole("ADMIN")) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).body(Map.of("error", "Admin role required"));
        }

        try {
            Long planId = Long.parseLong(request.get("planId").toString());

            Optional<User> userOpt = userRepository.findById(userId);
            if (userOpt.isEmpty()) {
                return ResponseEntity.badRequest()
                        .body(Map.of("error", "Kullanıcı bulunamadı"));
            }
            User user = userOpt.get();

            Optional<SubscriptionPlan> planOpt = planRepository.findById(planId);
            if (planOpt.isEmpty()) {
                return ResponseEntity.badRequest()
                        .body(Map.of("error", "Plan bulunamadı"));
            }
            SubscriptionPlan plan = planOpt.get();

            if (isSubscriptionCurrentlyActive(user)) {
                return ResponseEntity.ok(Map.of(
                        "message", "Demo abonelik zaten aktif, süre uzatılmadı.",
                        "plan", plan.getName(),
                        "subscriptionEndDate", user.getSubscriptionEndDate().toString(),
                        "idempotent", true));
            }

            // Activate subscription directly
            int days = resolveEffectiveDurationDays(plan);
            LocalDateTime currentEnd = user.getSubscriptionEndDate();
            if (currentEnd == null || currentEnd.isBefore(LocalDateTime.now())) {
                user.setSubscriptionEndDate(LocalDateTime.now().plusDays(days));
            } else {
                user.setSubscriptionEndDate(currentEnd.plusDays(days));
            }
            user.setAiPlanCode(resolveAiPlanCode(plan));
            userRepository.save(user);

            return ResponseEntity.ok(Map.of(
                    "message", "Demo abonelik aktifleştirildi!",
                    "plan", plan.getName(),
                    "subscriptionEndDate", user.getSubscriptionEndDate().toString()));
        } catch (Exception e) {
            return ResponseEntity.internalServerError()
                    .body(Map.of("error", "Demo aktivasyon hatası: " + e.getMessage()));
        }
    }

    private String resolveAiPlanCode(SubscriptionPlan plan) {
        if (plan == null) {
            return AiPlanTier.FREE.name();
        }
        return AiPlanTier.fromSubscriptionPlanName(plan.getName()).name();
    }
}
