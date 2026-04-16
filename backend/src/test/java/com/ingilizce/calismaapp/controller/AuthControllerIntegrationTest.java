package com.ingilizce.calismaapp.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ingilizce.calismaapp.repository.EmailVerificationTokenRepository;
import com.ingilizce.calismaapp.repository.PasswordResetTokenRepository;
import com.ingilizce.calismaapp.repository.RefreshTokenSessionRepository;
import com.ingilizce.calismaapp.entity.User;
import com.ingilizce.calismaapp.repository.UserRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.web.servlet.MockMvc;

import java.util.HashMap;
import java.util.Map;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@org.springframework.test.context.TestPropertySource(properties = "GROQ_API_KEY=dummy-key")
public class AuthControllerIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private RefreshTokenSessionRepository refreshTokenSessionRepository;

    @Autowired
    private PasswordResetTokenRepository passwordResetTokenRepository;

    @Autowired
    private EmailVerificationTokenRepository emailVerificationTokenRepository;

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
    private PasswordEncoder passwordEncoder;

    @BeforeEach
    void setUp() {
        refreshTokenSessionRepository.deleteAll();
        passwordResetTokenRepository.deleteAll();
        emailVerificationTokenRepository.deleteAll();
        userRepository.deleteAll();
    }

    @Test
    void register_ShouldCreateUser_WhenPayloadValid() throws Exception {
        Map<String, String> registerRequest = new HashMap<>();
        registerRequest.put("email", "register@test.com");
        registerRequest.put("password", "password123");
        registerRequest.put("displayName", "Register User");

        mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(registerRequest)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.user.email").value("register@test.com"))
                .andExpect(jsonPath("$.accessToken").exists())
                .andExpect(jsonPath("$.refreshToken").exists())
                .andExpect(jsonPath("$.emailVerificationRequired").value(true))
                .andExpect(jsonPath("$.emailVerificationToken").exists());
    }

    @Test
    void register_ShouldReturnBadRequest_WhenEmailMissing() throws Exception {
        Map<String, String> registerRequest = new HashMap<>();
        registerRequest.put("password", "password123");

        mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(registerRequest)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("Email and password required"));
    }

    @Test
    void register_ShouldReturnBadRequest_WhenEmailAlreadyExists() throws Exception {
        userRepository.save(new User("dup@test.com", passwordEncoder.encode("password123"), "Dup User"));

        Map<String, String> registerRequest = new HashMap<>();
        registerRequest.put("email", "dup@test.com");
        registerRequest.put("password", "newpass");

        mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(registerRequest)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("Registration failed"));
    }

    @Test
    void login_ShouldReturnUser_WhenCredentialsAreCorrect() throws Exception {
        User user = new User("login@test.com", passwordEncoder.encode("password123"));
        userRepository.save(user);

        Map<String, String> loginRequest = new HashMap<>();
        loginRequest.put("email", "login@test.com");
        loginRequest.put("password", "password123");

        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(loginRequest)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.email").value("login@test.com"))
                .andExpect(jsonPath("$.accessToken").exists())
                .andExpect(jsonPath("$.refreshToken").exists());
    }

    @Test
    void login_ShouldReturnUnauthorized_WhenPasswordWrong() throws Exception {
        userRepository.save(new User("login@test.com", passwordEncoder.encode("password123")));

        Map<String, String> loginRequest = new HashMap<>();
        loginRequest.put("email", "login@test.com");
        loginRequest.put("password", "wrong-password");

        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(loginRequest)))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.success").value(false));
    }

    @Test
    void login_ShouldAcceptEmailOrTagField() throws Exception {
        userRepository.save(new User("logintag@test.com", passwordEncoder.encode("password123")));

        Map<String, String> loginRequest = new HashMap<>();
        loginRequest.put("emailOrTag", "logintag@test.com");
        loginRequest.put("password", "password123");

        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(loginRequest)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.email").value("logintag@test.com"));
    }

    @Test
    void refresh_ShouldRotateToken_WhenRefreshTokenValid() throws Exception {
        User user = new User("refresh@test.com", passwordEncoder.encode("password123"));
        userRepository.save(user);

        Map<String, String> loginRequest = new HashMap<>();
        loginRequest.put("email", "refresh@test.com");
        loginRequest.put("password", "password123");

        String refreshToken = objectMapper.readTree(
                mockMvc.perform(post("/api/auth/login")
                                .contentType(MediaType.APPLICATION_JSON)
                                .content(objectMapper.writeValueAsString(loginRequest)))
                        .andExpect(status().isOk())
                        .andReturn()
                        .getResponse()
                        .getContentAsString())
                .get("refreshToken")
                .asText();

        mockMvc.perform(post("/api/auth/refresh")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of("refreshToken", refreshToken))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.accessToken").exists())
                .andExpect(jsonPath("$.refreshToken").exists())
                .andExpect(jsonPath("$.userId").isNumber())
                .andExpect(jsonPath("$.role").value("USER"));
    }

    @Test
    void googleLogin_ShouldCreateUser_WhenNotExists() throws Exception {
        Map<String, String> googleRequest = new HashMap<>();
        googleRequest.put("email", "google-new@test.com");
        googleRequest.put("displayName", "Google User");
        googleRequest.put("googleId", "gid-123");

        mockMvc.perform(post("/api/auth/google-login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(googleRequest)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.email").value("google-new@test.com"))
                .andExpect(jsonPath("$.accessToken").exists())
                .andExpect(jsonPath("$.refreshToken").exists())
                .andExpect(jsonPath("$.emailVerified").value(true));
    }

    @Test
    void googleLogin_ShouldUpdateDisplayName_WhenUserExistsWithDefaultName() throws Exception {
        User existing = new User("google-existing@test.com", passwordEncoder.encode("x"));
        existing.setDisplayName("User");
        userRepository.save(existing);

        Map<String, String> googleRequest = new HashMap<>();
        googleRequest.put("email", "google-existing@test.com");
        googleRequest.put("displayName", "Updated Google Name");
        googleRequest.put("googleId", "gid-456");

        mockMvc.perform(post("/api/auth/google-login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(googleRequest)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.displayName").value("Updated Google Name"));
    }

    @Test
    void googleLogin_ShouldReturnBadRequest_WhenEmailMissing() throws Exception {
        Map<String, String> googleRequest = new HashMap<>();
        googleRequest.put("displayName", "No Email");

        mockMvc.perform(post("/api/auth/google-login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(googleRequest)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("Email is required"));
    }

    @Test
    void passwordResetRequestAndConfirm_ShouldResetPassword() throws Exception {
        userRepository.save(new User("pwreset@test.com", passwordEncoder.encode("old-password"), "Reset User"));

        Map<String, String> requestPayload = new HashMap<>();
        requestPayload.put("email", "pwreset@test.com");

        String resetToken = objectMapper.readTree(
                mockMvc.perform(post("/api/auth/password-reset/request")
                                .contentType(MediaType.APPLICATION_JSON)
                                .content(objectMapper.writeValueAsString(requestPayload)))
                        .andExpect(status().isOk())
                        .andExpect(jsonPath("$.success").value(true))
                        .andExpect(jsonPath("$.passwordResetToken").exists())
                        .andReturn()
                        .getResponse()
                        .getContentAsString())
                .get("passwordResetToken")
                .asText();

        Map<String, String> confirmPayload = new HashMap<>();
        confirmPayload.put("token", resetToken);
        confirmPayload.put("newPassword", "new-password-123");

        mockMvc.perform(post("/api/auth/password-reset/confirm")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(confirmPayload)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true));

        Map<String, String> loginPayload = new HashMap<>();
        loginPayload.put("email", "pwreset@test.com");
        loginPayload.put("password", "new-password-123");

        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(loginPayload)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true));
    }

    @Test
    void emailVerificationConfirm_ShouldVerifyEmail() throws Exception {
        userRepository.save(new User("verify@test.com", passwordEncoder.encode("password123"), "Verify User"));

        Map<String, String> requestPayload = new HashMap<>();
        requestPayload.put("email", "verify@test.com");

        String verifyToken = objectMapper.readTree(
                mockMvc.perform(post("/api/auth/email-verification/request")
                                .contentType(MediaType.APPLICATION_JSON)
                                .content(objectMapper.writeValueAsString(requestPayload)))
                        .andExpect(status().isOk())
                        .andExpect(jsonPath("$.success").value(true))
                        .andExpect(jsonPath("$.emailVerificationToken").exists())
                        .andReturn()
                        .getResponse()
                        .getContentAsString())
                .get("emailVerificationToken")
                .asText();

        mockMvc.perform(post("/api/auth/email-verification/confirm")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of("token", verifyToken))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.emailVerified").value(true));
    }
}
