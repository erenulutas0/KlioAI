package com.ingilizce.calismaapp.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
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
import org.springframework.http.converter.json.MappingJackson2HttpMessageConverter;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.time.Instant;
import java.time.LocalDateTime;
import java.util.Map;
import java.util.Optional;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
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
    private com.ingilizce.calismaapp.service.LanguageProfileService languageProfileService;
    private final ObjectMapper objectMapper = new ObjectMapper()
            .registerModule(new JavaTimeModule());

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
        languageProfileService = mock(com.ingilizce.calismaapp.service.LanguageProfileService.class);
        authSecurityProperties.setExposeDebugTokens(true);
        when(authRateLimitService.checkRegister(anyString())).thenReturn(RateLimitDecision.allowed());
        when(authRateLimitService.checkLogin(anyString(), anyString())).thenReturn(RateLimitDecision.allowed());
        when(authRateLimitService.checkPasswordResetRequest(anyString())).thenReturn(RateLimitDecision.allowed());
        when(authRateLimitService.checkGuestCreation(anyString(), anyString()))
                .thenReturn(RateLimitDecision.allowed());
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
                trialAbuseProtectionService,
                languageProfileService);
        mockMvc = MockMvcBuilders.standaloneSetup(controller)
                .setMessageConverters(new MappingJackson2HttpMessageConverter(objectMapper))
                .build();
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
    void login_ShouldNormalizeEmailWithCapitalI_OnTurkishLocaleJvm() throws Exception {
        java.util.Locale original = java.util.Locale.getDefault();
        try {
            java.util.Locale.setDefault(new java.util.Locale("tr", "TR"));
            when(userRepository.findByEmail("mike@test.com")).thenReturn(Optional.empty());

            mockMvc.perform(post("/api/auth/login")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(Map.of(
                                    "email", "MIKE@test.com",
                                    "password", "pass123"))))
                    .andExpect(status().isUnauthorized());

            verify(userRepository).findByEmail("mike@test.com");
        } finally {
            java.util.Locale.setDefault(original);
        }
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
    void googleLogin_ShouldCreateFreeAccountWithoutTrial_WhenSharedIpTrialLimitIsReached() throws Exception {
        when(userRepository.findByEmail("google-new@test.com")).thenReturn(Optional.empty());
        when(clientIpResolver.resolve(any())).thenReturn("203.0.113.10");
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

        verify(trialAbuseProtectionService).evaluate(eq("device-77"), eq("203.0.113.10"));
        verify(userRepository).save(argThat(user ->
                "google-new@test.com".equals(user.getEmail()) && !user.isTrialEligible()));
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

    // ---------------------------------------------------------------------------------
    // Guest accounts (V032): the app has to work before anybody has signed in, and signing
    // in later must cost the learner nothing they have already done.
    // ---------------------------------------------------------------------------------

    @Test
    void guest_ShouldCreateAnAccountNobodyHasSignedInTo() throws Exception {
        when(userRepository.save(any(User.class))).thenAnswer(invocation -> {
            User u = invocation.getArgument(0);
            u.setId(501L);
            return u;
        });

        mockMvc.perform(post("/api/auth/guest")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of(
                                "deviceId", "device-501",
                                "displayName", "Eren",
                                "locale", "tr"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.guest").value(true))
                .andExpect(jsonPath("$.userId").value(501))
                .andExpect(jsonPath("$.displayName").value("Eren"))
                .andExpect(jsonPath("$.accessToken").exists())
                .andExpect(jsonPath("$.refreshToken").exists())
                // Nothing to verify: there is no mailbox behind a guest address.
                .andExpect(jsonPath("$.emailVerificationRequired").value(false));

        verify(userRepository).save(argThat(user ->
                user.isGuest()
                        && user.getEmail().startsWith("guest-")
                        && user.getEmail().endsWith("@guest.klioai.app")));
        verify(languageProfileService).ensureDefaultProfile(501L);
    }

    @Test
    void guest_ShouldNotSpendTheTrialTheRealAccountWillNeed() throws Exception {
        when(userRepository.save(any(User.class))).thenAnswer(invocation -> {
            User u = invocation.getArgument(0);
            u.setId(502L);
            return u;
        });

        mockMvc.perform(post("/api/auth/guest")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of("deviceId", "device-502"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.trialEligible").value(false));

        // The device counter must not even be consulted, let alone spent: it is what decides
        // the trial for the account this person actually creates later.
        verify(trialAbuseProtectionService, never()).evaluate(anyString(), anyString());
        verify(trialAbuseProtectionService, never()).recordTrialGrant(anyString(), anyString());
    }

    @Test
    void guest_ShouldBeRefusedWhenTooManyHaveBeenOpenedFromHere() throws Exception {
        // The registration limiter counts failures, and asking for a guest account never
        // fails: without a limiter that counts the accounts themselves, a script gets a user
        // row and a fresh daily AI quota on every request.
        when(authRateLimitService.checkGuestCreation(anyString(), anyString()))
                .thenReturn(RateLimitDecision.blocked(900));

        mockMvc.perform(post("/api/auth/guest")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{}"))
                .andExpect(status().isTooManyRequests());

        verify(userRepository, never()).save(any(User.class));
    }

    @Test
    void guest_ShouldWorkWithNoBodyAtAll() throws Exception {
        when(userRepository.save(any(User.class))).thenAnswer(invocation -> {
            User u = invocation.getArgument(0);
            u.setId(503L);
            return u;
        });

        mockMvc.perform(post("/api/auth/guest").contentType(MediaType.APPLICATION_JSON))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.guest").value(true))
                .andExpect(jsonPath("$.displayName").value("Guest"));
    }

    @Test
    void guest_ShouldReturnTooManyRequests_WhenRateLimited() throws Exception {
        when(authRateLimitService.checkRegister(anyString())).thenReturn(RateLimitDecision.blocked(120));

        mockMvc.perform(post("/api/auth/guest")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{}"))
                .andExpect(status().isTooManyRequests())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.retryAfterSeconds").value(120));

        verify(userRepository, never()).save(any(User.class));
    }

    @Test
    void googleLogin_ShouldConvertTheGuestInPlace_KeepingItsId() throws Exception {
        User guest = new User("guest-abc@guest.klioai.app", "hash", "Guest");
        guest.setId(700L);
        guest.setGuest(true);
        guest.setTrialEligible(false);
        when(currentUserContext.getCurrentUserId()).thenReturn(Optional.of(700L));
        when(userRepository.findById(700L)).thenReturn(Optional.of(guest));
        when(userRepository.findByEmail("real@gmail.com")).thenReturn(Optional.empty());
        when(userRepository.save(any(User.class))).thenAnswer(invocation -> invocation.getArgument(0));

        mockMvc.perform(post("/api/auth/google-login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of(
                                "email", "real@gmail.com",
                                "displayName", "Real Name",
                                "googleId", "gid-700",
                                "deviceId", "device-700"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.converted").value(true))
                // No row was created, so this is not a new account -- but it is the signup.
                .andExpect(jsonPath("$.newAccount").value(false))
                .andExpect(jsonPath("$.userId").value(700))
                .andExpect(jsonPath("$.email").value("real@gmail.com"))
                .andExpect(jsonPath("$.displayName").value("Real Name"))
                .andExpect(jsonPath("$.emailVerified").value(true))
                // The trial the guest was refused is granted to the account it became.
                .andExpect(jsonPath("$.trialEligible").value(true));

        verify(userRepository).save(argThat(user ->
                user.getId().equals(700L) && !user.isGuest() && "real@gmail.com".equals(user.getEmail())));
        verify(trialAbuseProtectionService).recordTrialGrant("device-700", "127.0.0.1");
    }

    @Test
    void googleLogin_ShouldLeaveTheGuestAlone_WhenTheEmailAlreadyHasAnAccount() throws Exception {
        User guest = new User("guest-abc@guest.klioai.app", "hash", "Guest");
        guest.setId(700L);
        guest.setGuest(true);
        User existing = new User("real@gmail.com", "hash", "Real Name");
        existing.setId(800L);
        existing.setEmailVerifiedAt(LocalDateTime.now());
        when(currentUserContext.getCurrentUserId()).thenReturn(Optional.of(700L));
        when(userRepository.findById(700L)).thenReturn(Optional.of(guest));
        when(userRepository.findByEmail("real@gmail.com")).thenReturn(Optional.of(existing));

        mockMvc.perform(post("/api/auth/google-login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of(
                                "email", "real@gmail.com",
                                "displayName", "Real Name",
                                "googleId", "gid-800"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.converted").value(false))
                .andExpect(jsonPath("$.userId").value(800));

        // The guest row is untouched here -- neither converted nor deleted. The nightly
        // cleanup collects it once the retention window passes.
        org.junit.jupiter.api.Assertions.assertTrue(guest.isGuest());
        verify(userRepository, never()).save(argThat(user -> Long.valueOf(700L).equals(user.getId())));
    }

    @Test
    void googleLogin_ShouldCreateANewAccount_WhenThePrincipalIsAlreadyARealOne() throws Exception {
        User realPrincipal = new User("someone@gmail.com", "hash", "Someone");
        realPrincipal.setId(900L);
        when(currentUserContext.getCurrentUserId()).thenReturn(Optional.of(900L));
        when(userRepository.findById(900L)).thenReturn(Optional.of(realPrincipal));
        when(userRepository.findByEmail("other@gmail.com")).thenReturn(Optional.empty());
        when(userRepository.save(any(User.class))).thenAnswer(invocation -> {
            User u = invocation.getArgument(0);
            u.setId(901L);
            return u;
        });

        mockMvc.perform(post("/api/auth/google-login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of(
                                "email", "other@gmail.com",
                                "displayName", "Other"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.converted").value(false))
                .andExpect(jsonPath("$.newAccount").value(true))
                .andExpect(jsonPath("$.userId").value(901));
    }
}
