package com.ingilizce.calismaapp.controller;

import com.ingilizce.calismaapp.entity.PaymentTransaction;
import com.ingilizce.calismaapp.entity.SubscriptionPlan;
import com.ingilizce.calismaapp.entity.User;
import com.ingilizce.calismaapp.repository.PaymentTransactionRepository;
import com.ingilizce.calismaapp.repository.SubscriptionPlanRepository;
import com.ingilizce.calismaapp.repository.UserRepository;
import com.ingilizce.calismaapp.service.IyzicoService;
import com.ingilizce.calismaapp.security.CurrentUserContext;
// iyzico SDK removed
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;

@RestController
@RequestMapping("/api/subscription")
public class SubscriptionController {

    private final SubscriptionPlanRepository planRepository;
    private final UserRepository userRepository;
    private final PaymentTransactionRepository transactionRepository;
    private final IyzicoService iyzicoService;
    private final CurrentUserContext currentUserContext;
    @Value("${app.subscription.mock-verification-enabled:true}")
    private boolean mockVerificationEnabled;

    public SubscriptionController(SubscriptionPlanRepository planRepository,
            UserRepository userRepository,
            PaymentTransactionRepository transactionRepository,
            IyzicoService iyzicoService,
            CurrentUserContext currentUserContext) {
        this.planRepository = planRepository;
        this.userRepository = userRepository;
        this.transactionRepository = transactionRepository;
        this.iyzicoService = iyzicoService;
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

            user.setSubscriptionEndDate(LocalDateTime.now().plusDays(plan.getDurationDays()));
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
        if (!mockVerificationEnabled) {
            return ResponseEntity.status(HttpStatus.NOT_IMPLEMENTED)
                    .body(Map.of("error", "Mock Google verification is disabled in this environment."));
        }
        try {
            Optional<User> userOpt = userRepository.findById(userId);
            if (userOpt.isEmpty()) {
                return ResponseEntity.internalServerError().body(Map.of("error", "User not found"));
            }
            User user = userOpt.get();

            String planName = request.get("planName");

            // In a real scenario, we would use Google Play Developer API to verify.
            Optional<SubscriptionPlan> planOpt = planRepository.findByName(planName);
            if (planOpt.isEmpty()) {
                return ResponseEntity.internalServerError().body(Map.of("error", "Plan not found"));
            }
            SubscriptionPlan plan = planOpt.get();

            user.setSubscriptionEndDate(LocalDateTime.now().plusDays(plan.getDurationDays()));
            userRepository.save(user);

            return ResponseEntity
                    .ok(Map.of("message", "Google IAP verified", "subscriptionEndDate", user.getSubscriptionEndDate()));
        } catch (Exception e) {
            return ResponseEntity.internalServerError().body(Map.of("error", e.getMessage()));
        }
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
        int days = transaction.getPlan().getDurationDays();
        LocalDateTime currentEnd = user.getSubscriptionEndDate();
        if (currentEnd == null || currentEnd.isBefore(LocalDateTime.now())) {
            user.setSubscriptionEndDate(LocalDateTime.now().plusDays(days));
        } else {
            user.setSubscriptionEndDate(currentEnd.plusDays(days));
        }
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

            // Activate subscription directly
            int days = plan.getDurationDays();
            LocalDateTime currentEnd = user.getSubscriptionEndDate();
            if (currentEnd == null || currentEnd.isBefore(LocalDateTime.now())) {
                user.setSubscriptionEndDate(LocalDateTime.now().plusDays(days));
            } else {
                user.setSubscriptionEndDate(currentEnd.plusDays(days));
            }
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
}
