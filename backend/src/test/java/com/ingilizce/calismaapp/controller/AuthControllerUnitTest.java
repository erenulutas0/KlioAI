package com.ingilizce.calismaapp.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
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
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.time.Instant;
import java.time.LocalDateTime;
import java.util.Map;
import java.util.Optional;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class AuthControllerUnitTest {

    private MockMvc mockMvc;
    private UserRepository userRepository;
    private AuthRateLimitService authRateLimitService;
    private PasswordEncoder passwordEncoder;
    private JwtTokenService jwtTokenService;
    private RefreshTokenService refreshTokenService;
    private CurrentUserContext currentUserContext;
    private PasswordResetService passwordResetService;
    private EmailVerificationService emailVerificationService;
    private GoogleIdentityService googleIdentityService;
    private AuthSecurityProperties authSecurityProperties;
    private ClientIpResolver clientIpResolver;
    private TrialAbuseProtectionService trialAbuseProtectionService;
    private final ObjectMapper objectMapper = new ObjectMapper();

    @BeforeEach
    void setUp() {
        userRepository = mock(UserRepository.class);
        authRateLimitService = mock(AuthRateLimitService.class);
        passwordEncoder = mock(PasswordEncoder.class);
        jwtTokenService = mock(JwtTokenService.class);
        refreshTokenService = mock(RefreshTokenService.class);
        currentUserContext = mock(CurrentUserContext.class);
        passwordResetService = mock(PasswordResetService.class);
        emailVerificationService = mock(EmailVerificationService.class);
        googleIdentityService = mock(GoogleIdentityService.class);
        authSecurityProperties = new AuthSecurityProperties();
        clientIpResolver = mock(ClientIpResolver.class);
        trialAbuseProtectionService = mock(TrialAbuseProtectionService.class);
        authSecurityProperties.setExposeDebugTokens(true);
        when(authRateLimitService.checkRegister(anyString())).thenReturn(RateLimitDecision.allowed());
        when(authRateLimitService.checkLogin(anyString(), anyString())).thenReturn(RateLimitDecision.allowed());
        when(authRateLimitService.checkPasswordResetRequest(anyString())).thenReturn(RateLimitDecision.allowed());
        when(passwordEncoder.encode(anyString())).thenReturn("encoded-password");
        when(passwordEncoder.matches(anyString(), anyString())).thenReturn(true);
        when(currentUserContext.getCurrentUserId()).thenReturn(Optional.empty());
        when(clientIpResolver.resolve(any())).thenReturn("127.0.0.1");
        when(trialAbuseProtectionService.evaluate(anyString(), anyString()))
                .thenReturn(TrialAbuseProtectionService.TrialDecision.allowed());

        when(refreshTokenService.issue(any(User.class), anyBoolean(), anyString(), anyString(), anyString(), any(Instant.class)))
                .thenReturn(new RefreshTokenService.IssuedRefreshToken(
                        "rt.session.secret",
                        "session123",
                        Instant.now().plusSeconds(3600)));
        when(emailVerificationService.issue(any(User.class), anyString(), anyString(), any(Instant.class)))
                .thenReturn(new EmailVerificationService.IssuedVerificationToken(
                        "evt.token.secret",
                        Instant.now().plusSeconds(3600)));
        when(jwtTokenService.issueAccessToken(any(User.class), anyString(), any(Instant.class)))
                .thenReturn(new JwtTokenService.IssuedAccessToken(
                        "access-token",
                        Instant.now().plusSeconds(900),
                        900L));

        AuthController controller = new AuthController(
                userRepository,
                authRateLimitService,
                passwordEncoder,
                jwtTokenService,
                refreshTokenService,
                currentUserContext,
                passwordResetService,
                emailVerificationService,
                googleIdentityService,
                authSecurityProperties,
                clientIpResolver,
                trialAbuseProtectionService);
        mockMvc = MockMvcBuilders.standaloneSetup(controller).build();
    }

    @Test
    void register_ShouldReturnBadRequest_WhenPasswordMissing() throws Exception {
        mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of("email", "a@test.com"))))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("Email and password required"));
    }

    @Test
    void register_ShouldReturnTooManyRequests_WhenRateLimited() throws Exception {
        when(authRateLimitService.checkRegister(anyString())).thenReturn(RateLimitDecision.blocked(120));

        mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of(
                                "email", "a@test.com",
                                "password", "pass123"))))
                .andExpect(status().isTooManyRequests())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.retryAfterSeconds").value(120));

        verify(userRepository, never()).existsByEmail(anyString());
    }

    @Test
    void register_ShouldReturnInternalServerError_WhenRepositorySaveFails() throws Exception {
        when(userRepository.existsByEmail("a@test.com")).thenReturn(false);
        when(userRepository.save(any(User.class))).thenThrow(new RuntimeException("db down"));

        mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of(
                                "email", "a@test.com",
                                "password", "pass123",
                                "displayName", "A User"))))
                .andExpect(status().isInternalServerError())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.error").value("Internal server error"));
    }

    @Test
    void register_ShouldDisableTrial_WhenTrialAbuseProtectionBlocks() throws Exception {
        when(userRepository.existsByEmail("abuse@test.com")).thenReturn(false);
        when(trialAbuseProtectionService.evaluate(anyString(), anyString()))
                .thenReturn(TrialAbuseProtectionService.TrialDecision.blocked("device-limit"));
        when(userRepository.save(any(User.class))).thenAnswer(invocation -> {
            User user = invocation.getArgument(0);
            user.setId(99L);
            return user;
        });

        mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of(
                                "email", "abuse@test.com",
                                "password", "pass123",
                                "displayName", "Abuse User",
                                "deviceId", "device-1"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.trialEligible").value(false))
                .andExpect(jsonPath("$.trialBlockedReason").value("device-limit"));

        verify(trialAbuseProtectionService, never()).recordTrialGrant(anyString(), anyString());
    }

    @Test
    void login_ShouldReturnUnauthorized_WhenUserDoesNotExist() throws Exception {
        when(userRepository.findByEmail("missing@test.com")).thenReturn(Optional.empty());

        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of(
                                "email", "missing@test.com",
                                "password", "pass123"))))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.error").value("Invalid credentials"));
    }

    @Test
    void login_ShouldReturnTooManyRequests_WhenRateLimited() throws Exception {
        when(authRateLimitService.checkLogin(anyString(), anyString())).thenReturn(RateLimitDecision.blocked(60));

        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of(
                                "email", "blocked@test.com",
                                "password", "pass123"))))
                .andExpect(status().isTooManyRequests())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.retryAfterSeconds").value(60));

        verify(userRepository, never()).findByEmail(anyString());
    }

    @Test
    void login_ShouldReturnInternalServerError_WhenRepositoryThrows() throws Exception {
        when(userRepository.findByEmail(anyString())).thenThrow(new RuntimeException("db down"));

        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of(
                                "email", "user@test.com",
                                "password", "pass123"))))
                .andExpect(status().isInternalServerError())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.error").value("Internal login error"));
    }

    @Test
    void emailPasswordEndpoints_ShouldReturnForbidden_WhenDisabled() throws Exception {
        authSecurityProperties.setEmailPasswordEnabled(false);

        mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of(
                                "email", "user@test.com",
                                "password", "pass123"))))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.error").value("Email/password authentication is disabled"));

        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of(
                                "email", "user@test.com",
                                "password", "pass123"))))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.success").value(false));

        mockMvc.perform(post("/api/auth/password-reset/request")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of("email", "user@test.com"))))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.success").value(false));

        mockMvc.perform(post("/api/auth/email-verification/request")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of("email", "user@test.com"))))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.success").value(false));

        verify(authRateLimitService, never()).checkRegister(anyString());
        verify(authRateLimitService, never()).checkLogin(anyString(), anyString());
        verify(authRateLimitService, never()).checkPasswordResetRequest(anyString());
        verify(userRepository, never()).findByEmail(anyString());
    }

    @Test
    void googleLogin_ShouldNotSave_WhenExistingUserHasCustomDisplayName() throws Exception {
        User user = new User("google@test.com", "hash", "Custom Name");
        user.setId(10L);
        user.setEmailVerifiedAt(LocalDateTime.now());
        when(userRepository.findByEmail("google@test.com")).thenReturn(Optional.of(user));

        mockMvc.perform(post("/api/auth/google-login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of(
                                "email", "google@test.com",
                                "displayName", "Incoming Name",
                                "googleId", "gid-1"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.displayName").value("Custom Name"));

        verify(userRepository, never()).save(any(User.class));
    }

    @Test
    void googleLogin_ShouldReturnInternalServerError_WhenRepositoryThrows() throws Exception {
        when(userRepository.findByEmail("google@test.com")).thenThrow(new RuntimeException("db down"));

        mockMvc.perform(post("/api/auth/google-login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of(
                                "email", "google@test.com",
                                "displayName", "Name"))))
                .andExpect(status().isInternalServerError())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.error").value("Google login error"));
    }

    @Test
    void googleLogin_ShouldCreateUser_WhenGoogleIdMissingForNewUser() throws Exception {
        when(userRepository.findByEmail("new@test.com")).thenReturn(Optional.empty());
        when(userRepository.save(any(User.class))).thenAnswer(invocation -> {
            User u = invocation.getArgument(0);
            u.setId(42L);
            return u;
        });

        mockMvc.perform(post("/api/auth/google-login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of(
                                "email", "new@test.com",
                                "displayName", "New User"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.userId").value(42))
                .andExpect(jsonPath("$.email").value("new@test.com"))
                .andExpect(jsonPath("$.emailVerified").value(true));
    }

    @Test
    void googleLogin_ShouldDisableTrial_WhenTrialAbuseProtectionBlocksNewUser() throws Exception {
        when(userRepository.findByEmail("google-new@test.com")).thenReturn(Optional.empty());
        when(trialAbuseProtectionService.evaluate(anyString(), anyString()))
                .thenReturn(TrialAbuseProtectionService.TrialDecision.blocked("ip-limit"));
        when(userRepository.save(any(User.class))).thenAnswer(invocation -> {
            User u = invocation.getArgument(0);
            u.setId(77L);
            return u;
        });

        mockMvc.perform(post("/api/auth/google-login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of(
                                "email", "google-new@test.com",
                                "displayName", "Google User",
                                "googleId", "gid-777",
                                "deviceId", "device-77"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.trialEligible").value(false))
                .andExpect(jsonPath("$.trialBlockedReason").value("ip-limit"));

        verify(trialAbuseProtectionService, never()).recordTrialGrant(anyString(), anyString());
    }

    @Test
    void passwordResetRequest_ShouldReturnGenericSuccess() throws Exception {
        User user = new User("reset@test.com", "hash", "Reset User");
        user.setId(12L);
        when(userRepository.findByEmail("reset@test.com")).thenReturn(Optional.of(user));
        when(passwordResetService.issue(any(User.class), anyString(), anyString(), any(Instant.class)))
                .thenReturn(new PasswordResetService.IssuedResetToken(
                        "prt.token.secret",
                        Instant.now().plusSeconds(600)));

        mockMvc.perform(post("/api/auth/password-reset/request")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of("email", "reset@test.com"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.passwordResetToken").value("prt.token.secret"));
    }

    @Test
    void emailVerificationConfirm_ShouldReturnBadRequest_WhenTokenMissing() throws Exception {
        mockMvc.perform(post("/api/auth/email-verification/confirm")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of())))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.error").value("token is required"));
    }

    @Test
    void googleLogin_ShouldReturnUnauthorized_WhenIdTokenInvalidInStrictMode() throws Exception {
        authSecurityProperties.setGoogleIdTokenRequired(true);
        when(googleIdentityService.verifyIdToken(anyString()))
                .thenThrow(new GoogleIdentityService.GoogleIdentityException(
                        GoogleIdentityService.GoogleIdentityException.Code.INVALID_TOKEN,
                        "invalid"));

        mockMvc.perform(post("/api/auth/google-login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of(
                                "idToken", "bad-token",
                                "email", "google@test.com"))))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.error").value("Google authentication failed"));
    }

    @Test
    void googleLogin_ShouldReturnServiceUnavailable_WhenProviderUnavailableInStrictMode() throws Exception {
        authSecurityProperties.setGoogleIdTokenRequired(true);
        when(googleIdentityService.verifyIdToken(anyString()))
                .thenThrow(new GoogleIdentityService.GoogleIdentityException(
                        GoogleIdentityService.GoogleIdentityException.Code.PROVIDER_UNAVAILABLE,
                        "unavailable"));

        mockMvc.perform(post("/api/auth/google-login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of(
                                "idToken", "token",
                                "email", "google@test.com"))))
                .andExpect(status().isServiceUnavailable())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.error").value("Google login temporarily unavailable"));
    }
}
