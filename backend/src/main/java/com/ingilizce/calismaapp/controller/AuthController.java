package com.ingilizce.calismaapp.controller;

import com.ingilizce.calismaapp.entity.User;
import com.ingilizce.calismaapp.repository.UserRepository;
import com.ingilizce.calismaapp.security.AuthSecurityProperties;
import com.ingilizce.calismaapp.security.ClientIpResolver;
import com.ingilizce.calismaapp.security.CurrentUserContext;
import com.ingilizce.calismaapp.security.EmailVerificationService;
import com.ingilizce.calismaapp.security.GoogleIdentityService;
import com.ingilizce.calismaapp.security.JwtTokenService;
import com.ingilizce.calismaapp.security.PasswordResetService;
import com.ingilizce.calismaapp.security.RefreshTokenService;
import com.ingilizce.calismaapp.service.AuthRateLimitService;
import com.ingilizce.calismaapp.service.AuthRateLimitService.RateLimitDecision;
import com.ingilizce.calismaapp.service.TrialAbuseProtectionService;
import jakarta.servlet.http.HttpServletRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.bind.annotation.*;

import java.time.Instant;
import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

@RestController
@RequestMapping("/api/auth")
public class AuthController {
    private static final Logger log = LoggerFactory.getLogger(AuthController.class);

    private final UserRepository userRepository;
    private final AuthRateLimitService authRateLimitService;
    private final PasswordEncoder passwordEncoder;
    private final JwtTokenService jwtTokenService;
    private final RefreshTokenService refreshTokenService;
    private final CurrentUserContext currentUserContext;
    private final PasswordResetService passwordResetService;
    private final EmailVerificationService emailVerificationService;
    private final GoogleIdentityService googleIdentityService;
    private final AuthSecurityProperties authSecurityProperties;
    private final ClientIpResolver clientIpResolver;
    private final TrialAbuseProtectionService trialAbuseProtectionService;

    public AuthController(UserRepository userRepository,
                          AuthRateLimitService authRateLimitService,
                          PasswordEncoder passwordEncoder,
                          JwtTokenService jwtTokenService,
                          RefreshTokenService refreshTokenService,
                          CurrentUserContext currentUserContext,
                           PasswordResetService passwordResetService,
                           EmailVerificationService emailVerificationService,
                           GoogleIdentityService googleIdentityService,
                           AuthSecurityProperties authSecurityProperties,
                           ClientIpResolver clientIpResolver,
                           TrialAbuseProtectionService trialAbuseProtectionService) {
        this.userRepository = userRepository;
        this.authRateLimitService = authRateLimitService;
        this.passwordEncoder = passwordEncoder;
        this.jwtTokenService = jwtTokenService;
        this.refreshTokenService = refreshTokenService;
        this.currentUserContext = currentUserContext;
        this.passwordResetService = passwordResetService;
        this.emailVerificationService = emailVerificationService;
        this.googleIdentityService = googleIdentityService;
        this.authSecurityProperties = authSecurityProperties;
        this.clientIpResolver = clientIpResolver;
        this.trialAbuseProtectionService = trialAbuseProtectionService;
    }

    @PostMapping("/register")
    public ResponseEntity<Map<String, Object>> register(@RequestBody Map<String, String> request,
                                                        HttpServletRequest httpRequest) {
        String email = normalizeEmail(request.get("email"));
        log.info("Processing registration request for email={}", email);
        try {
            String clientIp = resolveClientIp(httpRequest);
            RateLimitDecision rateLimitDecision = authRateLimitService.checkRegister(clientIp);
            if (rateLimitDecision.blocked()) {
                return tooManyRequests("Too many registration attempts. Please try again later.", rateLimitDecision);
            }

            String password = request.get("password");
            String displayName = request.get("displayName");
            boolean rememberMe = Boolean.parseBoolean(request.getOrDefault("rememberMe", "false"));
            String deviceId = resolveDeviceId(request, httpRequest);

            if (email == null || password == null) {
                authRateLimitService.recordRegisterFailure(clientIp);
                return ResponseEntity.badRequest().body(Map.of("error", "Email and password required"));
            }

            if (userRepository.existsByEmail(email)) {
                authRateLimitService.recordRegisterFailure(clientIp);
                log.warn("Registration rejected for email={}", email);
                return ResponseEntity.badRequest().body(Map.of("error", "Registration failed"));
            }

            TrialAbuseProtectionService.TrialDecision trialDecision =
                    trialAbuseProtectionService.evaluate(deviceId, clientIp);
            User user = new User(email, passwordEncoder.encode(password), displayName);
            if (!trialDecision.trialEligible()) {
                user.setTrialEligible(false);
            }
            User savedUser = userRepository.save(user);
            if (savedUser.isTrialEligible()) {
                trialAbuseProtectionService.recordTrialGrant(deviceId, clientIp);
            }
            TokenBundle tokens = issueTokens(savedUser, rememberMe, deviceId, httpRequest);
            EmailVerificationService.IssuedVerificationToken verificationToken = emailVerificationService.issue(
                    savedUser,
                    clientIp,
                    resolveUserAgent(httpRequest),
                    Instant.now());
            authRateLimitService.resetRegister(clientIp);
            log.info("User registered successfully, userId={}", savedUser.getId());

            Map<String, Object> response = buildAuthSuccessResponse(savedUser, tokens);
            response.put("emailVerificationRequired", true);
            if (!savedUser.isTrialEligible()) {
                response.put("trialBlockedReason", trialDecision.reason());
            }
            maybeAttachDebugToken(response, "emailVerificationToken", verificationToken.tokenValue(), verificationToken.expiresAt());
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            log.error("Error during registration for email={}", email, e);
            return ResponseEntity.internalServerError()
                    .body(Map.of("error", "Internal server error", "success", false));
        }
    }

    @PostMapping("/login")
    public ResponseEntity<Map<String, Object>> login(@RequestBody Map<String, String> request,
                                                     HttpServletRequest httpRequest) {
        String email = normalizeEmail(request.get("emailOrTag"));
        if (email == null) {
            email = normalizeEmail(request.get("email"));
        }
        log.info("Processing login request for email={}", email);

        try {
            String clientIp = resolveClientIp(httpRequest);
            RateLimitDecision rateLimitDecision = authRateLimitService.checkLogin(email, clientIp);
            if (rateLimitDecision.blocked()) {
                return tooManyRequests("Too many login attempts. Please try again later.", rateLimitDecision);
            }

            String password = request.get("password");
            boolean rememberMe = Boolean.parseBoolean(request.getOrDefault("rememberMe", "false"));
            String deviceId = resolveDeviceId(request, httpRequest);
            if (email == null || password == null) {
                authRateLimitService.recordLoginFailure(email, clientIp);
                return ResponseEntity.badRequest().body(Map.of("error", "Email and password required", "success", false));
            }

            Optional<User> userOpt = userRepository.findByEmail(email);

            if (userOpt.isPresent()) {
                User user = userOpt.get();
                if (passwordEncoder.matches(password, user.getPasswordHash())) {
                    TokenBundle tokens = issueTokens(user, rememberMe, deviceId, httpRequest);
                    authRateLimitService.resetLogin(email, clientIp);
                    log.info("Login successful, userId={}", user.getId());
                    return ResponseEntity.ok(buildAuthSuccessResponse(user, tokens));
                } else {
                    authRateLimitService.recordLoginFailure(email, clientIp);
                    log.warn("Login rejected due to invalid password, email={}", email);
                }
            } else {
                authRateLimitService.recordLoginFailure(email, clientIp);
                log.info("Login rejected: user not found, email={}", email);
            }

            return ResponseEntity.status(401).body(Map.of("error", "Invalid credentials", "success", false));
        } catch (Exception e) {
            log.error("Internal login error for email={}", email, e);
            return ResponseEntity.internalServerError().body(Map.of("error", "Internal login error", "success", false));
        }
    }

    @PostMapping("/google-login")
    public ResponseEntity<Map<String, Object>> googleLogin(@RequestBody Map<String, String> request,
                                                           HttpServletRequest httpRequest) {
        String requestedEmail = normalizeEmail(request.get("email"));
        String email = requestedEmail;
        log.info("Processing Google login request for email={}", requestedEmail);
        try {
            String clientIp = resolveClientIp(httpRequest);
            RateLimitDecision rateLimitDecision = authRateLimitService.checkLogin(
                    requestedEmail != null ? requestedEmail : "google-login",
                    clientIp);
            if (rateLimitDecision.blocked()) {
                return tooManyRequests("Too many login attempts. Please try again later.", rateLimitDecision);
            }

            GoogleIdentityService.VerifiedIdentity verifiedIdentity = null;
            if (authSecurityProperties.isGoogleIdTokenRequired()) {
                try {
                    verifiedIdentity = googleIdentityService.verifyIdToken(request.get("idToken"));
                } catch (GoogleIdentityService.GoogleIdentityException ex) {
                    authRateLimitService.recordLoginFailure(requestedEmail, clientIp);
                    if (ex.getCode() == GoogleIdentityService.GoogleIdentityException.Code.PROVIDER_UNAVAILABLE
                            || ex.getCode() == GoogleIdentityService.GoogleIdentityException.Code.MISCONFIGURED) {
                        return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                                .body(Map.of("error", "Google login temporarily unavailable", "success", false));
                    }
                    return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                            .body(Map.of("error", "Google authentication failed", "success", false));
                }
                email = normalizeEmail(verifiedIdentity.email());
                if (requestedEmail != null && !requestedEmail.equals(email)) {
                    authRateLimitService.recordLoginFailure(requestedEmail, clientIp);
                    return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                            .body(Map.of("error", "Google authentication failed", "success", false));
                }
            }

            String displayName = request.get("displayName");
            String photoUrl = request.get("photoUrl");
            String googleId = request.get("googleId");
            String deviceId = resolveDeviceId(request, httpRequest);
            boolean rememberMe = Boolean.parseBoolean(request.getOrDefault("rememberMe", "true"));

            if (email == null) {
                authRateLimitService.recordLoginFailure(requestedEmail, clientIp);
                return ResponseEntity.badRequest().body(Map.of("error", "Email is required"));
            }

            Optional<User> userOpt = userRepository.findByEmail(email);
            User user;
            boolean createdUser = false;
            TrialAbuseProtectionService.TrialDecision trialDecision = TrialAbuseProtectionService.TrialDecision.allowed();

            if (userOpt.isPresent()) {
                user = userOpt.get();
                log.info("Google login user found, userId={}", user.getId());

                // Update displayName if it was null/default before
                boolean updated = false;
                if ((user.getDisplayName() == null || user.getDisplayName().equals("User")) && displayName != null) {
                    user.setDisplayName(displayName);
                    updated = true;
                }
                if (!user.isEmailVerified()) {
                    user.setEmailVerifiedAt(LocalDateTime.now());
                    updated = true;
                }
                if (updated) {
                    userRepository.save(user);
                }
            } else {
                // User doesn't exist, create proper account
                log.info("Google login user not found, creating new account for email={}", email);
                // Use googleId as password seed or random string
                String dummyPassword;
                if (verifiedIdentity != null) {
                    dummyPassword = "google_auth_" + verifiedIdentity.subject();
                } else {
                    dummyPassword = googleId != null ? "google_auth_" + googleId : "google_auth_" + UUID.randomUUID();
                }

                trialDecision = trialAbuseProtectionService.evaluate(deviceId, clientIp);
                user = new User(email, passwordEncoder.encode(dummyPassword), displayName);
                user.setEmailVerifiedAt(LocalDateTime.now());
                if (!trialDecision.trialEligible()) {
                    user.setTrialEligible(false);
                }
                user = userRepository.save(user);
                createdUser = true;
                if (user.isTrialEligible()) {
                    trialAbuseProtectionService.recordTrialGrant(deviceId, clientIp);
                }
                log.info("Google login user created, userId={}", user.getId());
            }

            TokenBundle tokens = issueTokens(user, rememberMe, deviceId, httpRequest);
            authRateLimitService.resetLogin(email, clientIp);
            Map<String, Object> response = buildAuthSuccessResponse(user, tokens);
            if (photoUrl != null && !photoUrl.isBlank()) {
                response.put("photoUrl", photoUrl);
            }
            if (createdUser && !user.isTrialEligible()) {
                response.put("trialBlockedReason", trialDecision.reason());
            }

            return ResponseEntity.ok(response);

        } catch (Exception e) {
            log.error("Google login error for email={}", email, e);
            return ResponseEntity.internalServerError()
                    .body(Map.of("error", "Google login error", "success", false));
        }
    }

    @PostMapping("/refresh")
    public ResponseEntity<Map<String, Object>> refresh(@RequestBody Map<String, String> request,
                                                       HttpServletRequest httpRequest) {
        String rawRefreshToken = request.get("refreshToken");
        if (rawRefreshToken == null || rawRefreshToken.isBlank()) {
            return ResponseEntity.badRequest().body(Map.of("error", "refreshToken is required", "success", false));
        }

        try {
            String deviceId = resolveDeviceId(request, httpRequest);
            String ip = resolveClientIp(httpRequest);
            String userAgent = resolveUserAgent(httpRequest);
            Long expectedUserId = currentUserContext.getCurrentUserId().orElse(null);

            RefreshTokenService.RotationResult rotation = refreshTokenService.rotate(
                    rawRefreshToken,
                    expectedUserId,
                    deviceId,
                    ip,
                    userAgent,
                    Instant.now());

            Long userId = rotation.previousSession().getUser().getId();
            User user = userRepository.findById(userId)
                    .orElseThrow(() -> new IllegalStateException("Refresh token user not found"));
            JwtTokenService.IssuedAccessToken accessToken = jwtTokenService.issueAccessToken(
                    user,
                    rotation.nextToken().sessionId(),
                    Instant.now());

            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("accessToken", accessToken.token());
            response.put("sessionToken", accessToken.token());
            response.put("refreshToken", rotation.nextToken().tokenValue());
            response.put("tokenType", "Bearer");
            response.put("expiresIn", accessToken.expiresInSeconds());
            response.put("refreshTokenExpiresAt", rotation.nextToken().expiresAt().toString());
            response.put("sessionId", rotation.nextToken().sessionId());
            response.put("userId", user.getId());
            response.put("role", user.getRole());
            return ResponseEntity.ok(response);
        } catch (RefreshTokenService.RefreshTokenException ex) {
            log.warn("Refresh failed: code={}, reason={}", ex.getCode(), ex.getMessage());
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                    .body(Map.of("error", "Invalid refresh token", "success", false));
        } catch (Exception ex) {
            log.error("Unexpected refresh error", ex);
            return ResponseEntity.internalServerError()
                    .body(Map.of("error", "Internal refresh error", "success", false));
        }
    }

    @PostMapping("/logout")
    public ResponseEntity<Map<String, Object>> logout(@RequestBody(required = false) Map<String, String> request) {
        Long userId = currentUserContext.getCurrentUserId().orElse(null);
        if (userId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                    .body(Map.of("error", "Unauthorized", "success", false));
        }

        String refreshToken = request != null ? request.get("refreshToken") : null;
        boolean revoked = false;

        if (refreshToken != null && !refreshToken.isBlank()) {
            revoked = refreshTokenService.revoke(refreshToken, userId, "logout", Instant.now());
        } else {
            Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
            if (authentication != null && authentication.getCredentials() instanceof String sid && !sid.isBlank()) {
                refreshTokenService.revokeBySessionId(sid, userId, "logout", Instant.now());
                revoked = true;
            } else {
                refreshTokenService.revokeAllForUser(userId, "logout-all", Instant.now());
                revoked = true;
            }
        }

        return ResponseEntity.ok(Map.of("success", true, "revoked", revoked));
    }

    @PostMapping("/password-reset/request")
    public ResponseEntity<Map<String, Object>> requestPasswordReset(@RequestBody Map<String, String> request,
                                                                    HttpServletRequest httpRequest) {
        String clientIp = resolveClientIp(httpRequest);
        RateLimitDecision rateLimitDecision = authRateLimitService.checkPasswordResetRequest(clientIp);
        if (rateLimitDecision.blocked()) {
            return tooManyRequests("Too many password reset attempts. Please try again later.", rateLimitDecision);
        }

        authRateLimitService.recordPasswordResetRequest(clientIp);
        String email = normalizeEmail(request.get("email"));
        String debugToken = null;
        Instant debugExpiry = null;

        if (email != null) {
            Optional<User> userOpt = userRepository.findByEmail(email);
            if (userOpt.isPresent()) {
                PasswordResetService.IssuedResetToken issuedResetToken = passwordResetService.issue(
                        userOpt.get(),
                        clientIp,
                        resolveUserAgent(httpRequest),
                        Instant.now());
                debugToken = issuedResetToken.tokenValue();
                debugExpiry = issuedResetToken.expiresAt();
            }
        }

        Map<String, Object> response = new HashMap<>();
        response.put("success", true);
        response.put("message", "If the account exists, password reset instructions have been sent.");
        maybeAttachDebugToken(response, "passwordResetToken", debugToken, debugExpiry);
        return ResponseEntity.ok(response);
    }

    @PostMapping("/password-reset/confirm")
    public ResponseEntity<Map<String, Object>> confirmPasswordReset(@RequestBody Map<String, String> request,
                                                                    HttpServletRequest httpRequest) {
        String rawToken = request.get("token");
        String newPassword = request.get("newPassword");

        if (rawToken == null || rawToken.isBlank() || newPassword == null || newPassword.isBlank()) {
            return ResponseEntity.badRequest()
                    .body(Map.of("success", false, "error", "token and newPassword are required"));
        }
        if (newPassword.length() < 8) {
            return ResponseEntity.badRequest()
                    .body(Map.of("success", false, "error", "Password must be at least 8 characters"));
        }

        try {
            passwordResetService.consume(
                    rawToken,
                    newPassword,
                    resolveClientIp(httpRequest),
                    resolveUserAgent(httpRequest),
                    Instant.now());
            return ResponseEntity.ok(Map.of("success", true, "message", "Password reset completed"));
        } catch (PasswordResetService.PasswordResetException ex) {
            return ResponseEntity.badRequest()
                    .body(Map.of("success", false, "error", "Invalid or expired reset token"));
        }
    }

    @PostMapping("/email-verification/request")
    public ResponseEntity<Map<String, Object>> requestEmailVerification(@RequestBody Map<String, String> request,
                                                                        HttpServletRequest httpRequest) {
        String clientIp = resolveClientIp(httpRequest);
        RateLimitDecision rateLimitDecision = authRateLimitService.checkPasswordResetRequest(clientIp);
        if (rateLimitDecision.blocked()) {
            return tooManyRequests("Too many verification attempts. Please try again later.", rateLimitDecision);
        }

        authRateLimitService.recordPasswordResetRequest(clientIp);
        String email = normalizeEmail(request.get("email"));
        String debugToken = null;
        Instant debugExpiry = null;
        if (email != null) {
            Optional<User> userOpt = userRepository.findByEmail(email);
            if (userOpt.isPresent() && !userOpt.get().isEmailVerified()) {
                EmailVerificationService.IssuedVerificationToken issuedVerificationToken = emailVerificationService.issue(
                        userOpt.get(),
                        clientIp,
                        resolveUserAgent(httpRequest),
                        Instant.now());
                debugToken = issuedVerificationToken.tokenValue();
                debugExpiry = issuedVerificationToken.expiresAt();
            }
        }

        Map<String, Object> response = new HashMap<>();
        response.put("success", true);
        response.put("message", "If the account exists, verification instructions have been sent.");
        maybeAttachDebugToken(response, "emailVerificationToken", debugToken, debugExpiry);
        return ResponseEntity.ok(response);
    }

    @PostMapping("/email-verification/confirm")
    public ResponseEntity<Map<String, Object>> confirmEmailVerification(@RequestBody Map<String, String> request,
                                                                        HttpServletRequest httpRequest) {
        String rawToken = request.get("token");
        if (rawToken == null || rawToken.isBlank()) {
            return ResponseEntity.badRequest()
                    .body(Map.of("success", false, "error", "token is required"));
        }

        try {
            User verifiedUser = emailVerificationService.verify(
                    rawToken,
                    resolveClientIp(httpRequest),
                    resolveUserAgent(httpRequest),
                    Instant.now());
            return ResponseEntity.ok(Map.of(
                    "success", true,
                    "message", "Email verification completed",
                    "userId", verifiedUser.getId(),
                    "emailVerified", verifiedUser.isEmailVerified()));
        } catch (EmailVerificationService.EmailVerificationException ex) {
            return ResponseEntity.badRequest()
                    .body(Map.of("success", false, "error", "Invalid or expired verification token"));
        }
    }

    private TokenBundle issueTokens(User user, boolean rememberMe, String deviceId, HttpServletRequest httpRequest) {
        Instant now = Instant.now();
        RefreshTokenService.IssuedRefreshToken refresh = refreshTokenService.issue(
                user,
                rememberMe,
                deviceId,
                resolveClientIp(httpRequest),
                resolveUserAgent(httpRequest),
                now);
        JwtTokenService.IssuedAccessToken access = jwtTokenService.issueAccessToken(user, refresh.sessionId(), now);
        return new TokenBundle(access, refresh);
    }

    private Map<String, Object> buildAuthSuccessResponse(User user, TokenBundle tokens) {
        Map<String, Object> response = new HashMap<>();
        response.put("success", true);
        response.put("userId", user.getId());
        response.put("email", user.getEmail());
        response.put("role", user.getRole());
        response.put("displayName", user.getDisplayName());
        response.put("userTag", user.getUserTag());
        response.put("subscriptionEndDate", user.getSubscriptionEndDate());
        response.put("isSubscriptionActive", user.isSubscriptionActive());
        response.put("trialEligible", user.isTrialEligible());
        response.put("emailVerified", user.isEmailVerified());
        response.put("emailVerificationRequired", !user.isEmailVerified());
        response.put("user", user);
        response.put("accessToken", tokens.accessToken().token());
        response.put("sessionToken", tokens.accessToken().token());
        response.put("refreshToken", tokens.refreshToken().tokenValue());
        response.put("tokenType", "Bearer");
        response.put("expiresIn", tokens.accessToken().expiresInSeconds());
        response.put("sessionId", tokens.refreshToken().sessionId());
        response.put("refreshTokenExpiresAt", tokens.refreshToken().expiresAt().toString());
        return response;
    }

    private void maybeAttachDebugToken(Map<String, Object> response, String fieldName, String token, Instant expiresAt) {
        if (!authSecurityProperties.isExposeDebugTokens()) {
            return;
        }

        if (token == null || token.isBlank()) {
            response.put(fieldName, "not-issued");
            return;
        }

        response.put(fieldName, token);
        if (expiresAt != null) {
            response.put(fieldName + "ExpiresAt", expiresAt.toString());
        }
    }

    private String normalizeEmail(String email) {
        if (email == null) {
            return null;
        }
        String normalized = email.trim().toLowerCase();
        return normalized.isEmpty() ? null : normalized;
    }

    private String resolveDeviceId(Map<String, String> request, HttpServletRequest httpRequest) {
        String fromBody = request.get("deviceId");
        if (fromBody != null && !fromBody.isBlank()) {
            return fromBody.trim();
        }
        String fromHeader = httpRequest != null ? httpRequest.getHeader("X-Device-Id") : null;
        if (fromHeader != null && !fromHeader.isBlank()) {
            return fromHeader.trim();
        }
        return "unknown-device";
    }

    private String resolveUserAgent(HttpServletRequest request) {
        if (request == null) {
            return "unknown-agent";
        }
        String ua = request.getHeader("User-Agent");
        if (ua == null || ua.isBlank()) {
            return "unknown-agent";
        }
        return ua.length() <= 512 ? ua : ua.substring(0, 512);
    }

    private record TokenBundle(JwtTokenService.IssuedAccessToken accessToken,
                               RefreshTokenService.IssuedRefreshToken refreshToken) {
    }

    private String resolveClientIp(HttpServletRequest request) {
        return clientIpResolver.resolve(request);
    }

    private ResponseEntity<Map<String, Object>> tooManyRequests(String message, RateLimitDecision decision) {
        return ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS)
                .header("Retry-After", String.valueOf(decision.retryAfterSeconds()))
                .body(Map.of(
                        "error", message,
                        "success", false,
                        "retryAfterSeconds", decision.retryAfterSeconds()));
    }
}


