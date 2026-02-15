package com.ingilizce.calismaapp.security;

import com.ingilizce.calismaapp.entity.User;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jws;
import io.jsonwebtoken.JwtException;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.Date;

@Service
public class JwtTokenService {

    public record AccessTokenClaims(Long userId, String role, String sessionId, Instant expiresAt) {
    }

    public record IssuedAccessToken(String token, Instant expiresAt, long expiresInSeconds) {
    }

    private static final Logger log = LoggerFactory.getLogger(JwtTokenService.class);
    private static final String CLAIM_ROLE = "role";
    private static final String CLAIM_SESSION_ID = "sid";

    private final JwtProperties properties;
    private SecretKey secretKey;

    public JwtTokenService(JwtProperties properties) {
        this.properties = properties;
    }

    @PostConstruct
    void init() {
        if (properties.getSecret() == null || properties.getSecret().isBlank()) {
            throw new IllegalStateException("JWT secret is not configured. Set APP_SECURITY_JWT_SECRET (or app.security.jwt.secret).");
        }
        byte[] raw = properties.getSecret().getBytes(StandardCharsets.UTF_8);
        if (raw.length < 32) {
            raw = sha256(raw);
            log.warn("JWT secret is shorter than 32 bytes. Deriving a stronger key via SHA-256.");
        }
        this.secretKey = Keys.hmacShaKeyFor(raw);
    }

    public IssuedAccessToken issueAccessToken(User user, String sessionId, Instant now) {
        Instant issuedAt = now != null ? now : Instant.now();
        Instant expiresAt = issuedAt.plusSeconds(Math.max(60L, properties.getAccessTokenTtlSeconds()));

        String token = Jwts.builder()
                .issuer(properties.getIssuer())
                .subject(String.valueOf(user.getId()))
                .claim(CLAIM_ROLE, user.getRole().name())
                .claim(CLAIM_SESSION_ID, sessionId)
                .issuedAt(Date.from(issuedAt))
                .expiration(Date.from(expiresAt))
                .signWith(secretKey)
                .compact();

        return new IssuedAccessToken(token, expiresAt, expiresAt.getEpochSecond() - issuedAt.getEpochSecond());
    }

    public AccessTokenClaims parseAccessToken(String token) {
        if (token == null || token.isBlank()) {
            return null;
        }
        try {
            Jws<Claims> parsed = Jwts.parser()
                    .verifyWith(secretKey)
                    .clockSkewSeconds(Math.max(0L, properties.getAllowedClockSkewSeconds()))
                    .build()
                    .parseSignedClaims(token);

            Claims claims = parsed.getPayload();
            Long userId = Long.parseLong(claims.getSubject());
            String role = claims.get(CLAIM_ROLE, String.class);
            String sessionId = claims.get(CLAIM_SESSION_ID, String.class);
            Instant expiresAt = claims.getExpiration().toInstant();
            return new AccessTokenClaims(userId, role, sessionId, expiresAt);
        } catch (JwtException | IllegalArgumentException ex) {
            return null;
        }
    }

    private byte[] sha256(byte[] value) {
        try {
            return MessageDigest.getInstance("SHA-256").digest(value);
        } catch (Exception ex) {
            throw new IllegalStateException("Unable to initialize JWT key", ex);
        }
    }
}
