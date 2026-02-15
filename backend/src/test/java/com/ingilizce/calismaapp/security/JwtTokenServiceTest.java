package com.ingilizce.calismaapp.security;

import com.ingilizce.calismaapp.entity.User;
import org.junit.jupiter.api.Test;

import java.time.Instant;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;

class JwtTokenServiceTest {

    @Test
    void issueAndParse_ShouldRoundTripClaims() {
        JwtProperties properties = new JwtProperties();
        properties.setSecret("jwt-token-service-test-secret-jwt-token-service-test");
        properties.setIssuer("test-issuer");
        properties.setAccessTokenTtlSeconds(900);
        properties.setAllowedClockSkewSeconds(30);

        JwtTokenService service = new JwtTokenService(properties);
        service.init();

        User user = new User("jwt@test.com", "hash", "Jwt User");
        user.setId(42L);
        user.setRole(User.Role.ADMIN);
        Instant now = Instant.parse("2099-02-10T10:00:00Z");

        JwtTokenService.IssuedAccessToken issued = service.issueAccessToken(user, "session-1", now);
        JwtTokenService.AccessTokenClaims claims = service.parseAccessToken(issued.token());

        assertNotNull(claims);
        assertEquals(42L, claims.userId());
        assertEquals("ADMIN", claims.role());
        assertEquals("session-1", claims.sessionId());
        assertEquals(now.plusSeconds(900), claims.expiresAt());
        assertEquals(900L, issued.expiresInSeconds());
    }

    @Test
    void issueAccessToken_ShouldApplyMinimumTtlOf60Seconds() {
        JwtProperties properties = new JwtProperties();
        properties.setSecret("jwt-token-service-test-secret-jwt-token-service-test");
        properties.setAccessTokenTtlSeconds(1);

        JwtTokenService service = new JwtTokenService(properties);
        service.init();

        User user = new User("ttl@test.com", "hash", "Ttl User");
        user.setId(7L);

        JwtTokenService.IssuedAccessToken issued = service.issueAccessToken(
                user,
                "session-ttl",
                Instant.parse("2026-02-10T10:00:00Z"));

        assertEquals(60L, issued.expiresInSeconds());
    }

    @Test
    void parseAccessToken_ShouldReturnNull_ForInvalidToken() {
        JwtProperties properties = new JwtProperties();
        properties.setSecret("jwt-token-service-test-secret-jwt-token-service-test");

        JwtTokenService service = new JwtTokenService(properties);
        service.init();

        assertNull(service.parseAccessToken(null));
        assertNull(service.parseAccessToken(""));
        assertNull(service.parseAccessToken("not-a-jwt"));
    }

    @Test
    void init_ShouldSupportShortSecret_ByDerivingSha256Key() {
        JwtProperties properties = new JwtProperties();
        properties.setSecret("short-secret");

        JwtTokenService service = new JwtTokenService(properties);
        service.init();

        User user = new User("short@test.com", "hash", "Short Secret User");
        user.setId(55L);
        JwtTokenService.IssuedAccessToken issued = service.issueAccessToken(user, "sid-short", Instant.now());

        assertNotNull(issued.token());
        assertNotNull(service.parseAccessToken(issued.token()));
    }
}
