package com.ingilizce.calismaapp.security;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.web.client.RestTemplateBuilder;
import org.springframework.http.HttpStatusCode;
import org.springframework.stereotype.Service;
import org.springframework.web.client.HttpStatusCodeException;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestTemplate;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

@Service
public class GoogleIdentityService {

    public record VerifiedIdentity(String subject, String email, boolean emailVerified, String audience) {
    }

    public static class GoogleIdentityException extends RuntimeException {
        public enum Code {
            INVALID_TOKEN,
            PROVIDER_UNAVAILABLE,
            MISCONFIGURED
        }

        private final Code code;

        public GoogleIdentityException(Code code, String message) {
            super(message);
            this.code = code;
        }

        public Code getCode() {
            return code;
        }
    }

    private static final Set<String> ALLOWED_ISSUERS = Set.of(
            "https://accounts.google.com",
            "accounts.google.com");

    private static final String TOKEN_INFO_URL = "https://oauth2.googleapis.com/tokeninfo?id_token={idToken}";

    private final AuthSecurityProperties authSecurityProperties;
    private final RestTemplate restTemplate;

    @Autowired
    public GoogleIdentityService(AuthSecurityProperties authSecurityProperties,
                                 RestTemplateBuilder restTemplateBuilder) {
        this(authSecurityProperties, restTemplateBuilder
                .setConnectTimeout(Duration.ofSeconds(3))
                .setReadTimeout(Duration.ofSeconds(5))
                .build());
    }

    GoogleIdentityService(AuthSecurityProperties authSecurityProperties, RestTemplate restTemplate) {
        this.authSecurityProperties = authSecurityProperties;
        this.restTemplate = restTemplate;
    }

    @SuppressWarnings("unchecked")
    public VerifiedIdentity verifyIdToken(String idToken) {
        if (idToken == null || idToken.isBlank()) {
            throw new GoogleIdentityException(GoogleIdentityException.Code.INVALID_TOKEN, "Missing Google idToken");
        }

        Map<String, Object> payload;
        try {
            payload = restTemplate.getForObject(TOKEN_INFO_URL, Map.class, idToken);
        } catch (HttpStatusCodeException ex) {
            HttpStatusCode status = ex.getStatusCode();
            if (status.is4xxClientError()) {
                throw new GoogleIdentityException(GoogleIdentityException.Code.INVALID_TOKEN, "Google token rejected");
            }
            throw new GoogleIdentityException(GoogleIdentityException.Code.PROVIDER_UNAVAILABLE, "Google token verification unavailable");
        } catch (ResourceAccessException ex) {
            throw new GoogleIdentityException(GoogleIdentityException.Code.PROVIDER_UNAVAILABLE, "Google token verification unreachable");
        } catch (RestClientException ex) {
            throw new GoogleIdentityException(GoogleIdentityException.Code.PROVIDER_UNAVAILABLE, "Google token verification failed");
        }

        if (payload == null) {
            throw new GoogleIdentityException(GoogleIdentityException.Code.INVALID_TOKEN, "Empty token payload");
        }

        String issuer = asString(payload.get("iss"));
        if (issuer == null || !ALLOWED_ISSUERS.contains(issuer)) {
            throw new GoogleIdentityException(GoogleIdentityException.Code.INVALID_TOKEN, "Invalid issuer");
        }

        String audience = asString(payload.get("aud"));
        if (audience == null || audience.isBlank()) {
            throw new GoogleIdentityException(GoogleIdentityException.Code.INVALID_TOKEN, "Missing audience");
        }

        List<String> configuredClientIds = authSecurityProperties.getGoogleClientIds() == null
                ? List.of()
                : authSecurityProperties.getGoogleClientIds().stream()
                .map(this::normalize)
                .filter(v -> !v.isEmpty())
                .collect(Collectors.toList());

        if (authSecurityProperties.isGoogleIdTokenRequired() && configuredClientIds.isEmpty()) {
            throw new GoogleIdentityException(GoogleIdentityException.Code.MISCONFIGURED, "Google client IDs are not configured");
        }

        if (!configuredClientIds.isEmpty() && !configuredClientIds.contains(audience)) {
            throw new GoogleIdentityException(GoogleIdentityException.Code.INVALID_TOKEN, "Audience mismatch");
        }

        String subject = asString(payload.get("sub"));
        if (subject == null || subject.isBlank()) {
            throw new GoogleIdentityException(GoogleIdentityException.Code.INVALID_TOKEN, "Missing subject");
        }

        String email = normalize(asString(payload.get("email")));
        if (email.isEmpty()) {
            throw new GoogleIdentityException(GoogleIdentityException.Code.INVALID_TOKEN, "Missing email");
        }

        boolean emailVerified = asBoolean(payload.get("email_verified"));
        if (!emailVerified) {
            throw new GoogleIdentityException(GoogleIdentityException.Code.INVALID_TOKEN, "Email not verified");
        }

        long expEpochSeconds = asLong(payload.get("exp"));
        if (expEpochSeconds <= 0 || Instant.ofEpochSecond(expEpochSeconds).isBefore(Instant.now())) {
            throw new GoogleIdentityException(GoogleIdentityException.Code.INVALID_TOKEN, "Token expired");
        }

        return new VerifiedIdentity(subject, email, true, audience);
    }

    private String asString(Object value) {
        if (value == null) {
            return null;
        }
        return String.valueOf(value).trim();
    }

    private boolean asBoolean(Object value) {
        if (value instanceof Boolean b) {
            return b;
        }
        if (value == null) {
            return false;
        }
        return "true".equalsIgnoreCase(String.valueOf(value).trim());
    }

    private long asLong(Object value) {
        if (value == null) {
            return -1L;
        }
        try {
            return Long.parseLong(String.valueOf(value).trim());
        } catch (NumberFormatException ignored) {
            return -1L;
        }
    }

    private String normalize(String value) {
        if (value == null) {
            return "";
        }
        return value.trim().toLowerCase();
    }
}
