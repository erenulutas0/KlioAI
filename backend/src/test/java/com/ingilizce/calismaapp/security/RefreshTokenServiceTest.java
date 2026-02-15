package com.ingilizce.calismaapp.security;

import com.ingilizce.calismaapp.entity.RefreshTokenSession;
import com.ingilizce.calismaapp.entity.User;
import com.ingilizce.calismaapp.repository.RefreshTokenSessionRepository;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.clearInvocations;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoMoreInteractions;
import static org.mockito.Mockito.when;

class RefreshTokenServiceTest {

    private RefreshTokenSessionRepository repository;
    private JwtProperties jwtProperties;
    private RefreshTokenService service;
    private Map<String, RefreshTokenSession> sessions;

    @BeforeEach
    void setUp() {
        repository = mock(RefreshTokenSessionRepository.class);
        jwtProperties = new JwtProperties();
        jwtProperties.setSecret("refresh-token-test-secret-refresh-token-test-secret");
        jwtProperties.setRefreshTokenTtlSeconds(180);
        jwtProperties.setRefreshTokenRememberMeTtlSeconds(3600);
        sessions = new ConcurrentHashMap<>();

        when(repository.save(any(RefreshTokenSession.class))).thenAnswer(invocation -> {
            RefreshTokenSession session = invocation.getArgument(0);
            sessions.put(session.getSessionId(), session);
            return session;
        });
        when(repository.findBySessionId(anyString()))
                .thenAnswer(invocation -> Optional.ofNullable(sessions.get(invocation.getArgument(0))));
        when(repository.revokeActiveSessionsForUser(any(Long.class), any(LocalDateTime.class), anyString(), any(LocalDateTime.class)))
                .thenReturn(1);

        service = new RefreshTokenService(repository, jwtProperties, new SimpleMeterRegistry());
    }

    @Test
    void issue_ShouldPersistSession_AndApplyMinimumTtl() {
        User user = user(7L);
        Instant now = Instant.parse("2026-02-10T10:00:00Z");

        RefreshTokenService.IssuedRefreshToken issued = service.issue(
                user,
                false,
                "  device-A  ",
                " 1.1.1.1 ",
                "agent",
                now);

        assertTrue(issued.tokenValue().startsWith("rt."));
        assertEquals(now.plusSeconds(300), issued.expiresAt());

        RefreshTokenSession saved = sessions.get(issued.sessionId());
        assertNotNull(saved);
        assertEquals("device-A", saved.getDeviceId());
        assertEquals("1.1.1.1", saved.getCreatedIp());
        assertEquals("1.1.1.1", saved.getLastUsedIp());
        assertEquals(LocalDateTime.ofInstant(now, ZoneOffset.UTC), saved.getCreatedAt());
        assertEquals(LocalDateTime.ofInstant(now.plusSeconds(300), ZoneOffset.UTC), saved.getExpiresAt());
    }

    @Test
    void rotate_ShouldRevokePrevious_AndIssueNewToken() {
        User user = user(8L);
        Instant issuedAt = Instant.parse("2026-02-10T10:00:00Z");
        RefreshTokenService.IssuedRefreshToken first = service.issue(user, true, "device-A", "1.1.1.1", "ua-1", issuedAt);

        RefreshTokenService.RotationResult rotation = service.rotate(
                first.tokenValue(),
                8L,
                "device-A",
                "2.2.2.2",
                "ua-2",
                issuedAt.plusSeconds(30));

        assertEquals("rotated", rotation.previousSession().getRevokeReason());
        assertNotNull(rotation.previousSession().getRevokedAt());
        assertEquals(rotation.nextToken().sessionId(), rotation.previousSession().getReplacedBySessionId());
        assertNotEquals(first.sessionId(), rotation.nextToken().sessionId());
        assertNotEquals(first.tokenValue(), rotation.nextToken().tokenValue());
        assertNotNull(sessions.get(rotation.nextToken().sessionId()));
    }

    @Test
    void rotate_ShouldThrowExpired_WhenSessionExpired() {
        User user = user(9L);
        Instant now = Instant.parse("2026-02-10T10:00:00Z");
        RefreshTokenService.IssuedRefreshToken issued = service.issue(user, false, "device-A", "1.1.1.1", "ua", now);
        RefreshTokenSession session = sessions.get(issued.sessionId());
        session.setExpiresAt(LocalDateTime.ofInstant(now.minusSeconds(1), ZoneOffset.UTC));

        RefreshTokenService.RefreshTokenException ex = assertThrows(
                RefreshTokenService.RefreshTokenException.class,
                () -> service.rotate(issued.tokenValue(), 9L, "device-A", "1.1.1.1", "ua", now));

        assertEquals(RefreshTokenService.RefreshTokenException.Code.EXPIRED, ex.getCode());
        assertEquals("expired", session.getRevokeReason());
        assertNotNull(session.getRevokedAt());
    }

    @Test
    void rotate_ShouldThrowDeviceMismatch_AndRevokeAllSessions() {
        User user = user(10L);
        Instant now = Instant.parse("2026-02-10T10:00:00Z");
        RefreshTokenService.IssuedRefreshToken issued = service.issue(user, true, "device-A", "1.1.1.1", "ua", now);

        RefreshTokenService.RefreshTokenException ex = assertThrows(
                RefreshTokenService.RefreshTokenException.class,
                () -> service.rotate(issued.tokenValue(), 10L, "device-B", "1.1.1.1", "ua", now.plusSeconds(5)));

        assertEquals(RefreshTokenService.RefreshTokenException.Code.DEVICE_MISMATCH, ex.getCode());
        verify(repository).revokeActiveSessionsForUser(eq(10L), any(LocalDateTime.class), eq("device-mismatch"), any(LocalDateTime.class));
    }

    @Test
    void rotate_ShouldThrowReuseDetected_WhenRevokedAndReplaced() {
        User user = user(11L);
        Instant now = Instant.parse("2026-02-10T10:00:00Z");
        RefreshTokenService.IssuedRefreshToken issued = service.issue(user, false, "device-A", "1.1.1.1", "ua", now);
        RefreshTokenSession session = sessions.get(issued.sessionId());
        session.setRevokedAt(LocalDateTime.ofInstant(now.plusSeconds(1), ZoneOffset.UTC));
        session.setReplacedBySessionId("next-session");

        RefreshTokenService.RefreshTokenException ex = assertThrows(
                RefreshTokenService.RefreshTokenException.class,
                () -> service.rotate(issued.tokenValue(), 11L, "device-A", "1.1.1.2", "ua", now.plusSeconds(2)));

        assertEquals(RefreshTokenService.RefreshTokenException.Code.REUSE_DETECTED, ex.getCode());
        assertNotNull(session.getReuseDetectedAt());
        verify(repository).revokeActiveSessionsForUser(eq(11L), any(LocalDateTime.class), eq("reuse-detected"), any(LocalDateTime.class));
    }

    @Test
    void revokeAndRevokeBySessionId_ShouldRespectUserBoundaries() {
        User user = user(12L);
        Instant now = Instant.parse("2026-02-10T10:00:00Z");
        RefreshTokenService.IssuedRefreshToken issued = service.issue(user, false, "device-A", "1.1.1.1", "ua", now);

        assertEquals(false, service.revoke(issued.tokenValue(), 99L, "logout", now));
        assertTrue(service.revoke(issued.tokenValue(), 12L, "logout", now));
        assertTrue(service.revoke(issued.tokenValue(), 12L, "logout", now.plusSeconds(5)));

        clearInvocations(repository);
        service.revokeBySessionId("", 12L, "logout", now);
        verifyNoMoreInteractions(repository);

        String sessionId = issued.sessionId();
        sessions.get(sessionId).setRevokedAt(null);
        sessions.get(sessionId).setRevokeReason(null);
        service.revokeBySessionId(sessionId, 100L, "logout", now);
        assertNull(sessions.get(sessionId).getRevokedAt());

        service.revokeBySessionId(sessionId, 12L, "manual", now.plusSeconds(10));
        assertEquals("manual", sessions.get(sessionId).getRevokeReason());
    }

    @Test
    void revokeAllForUser_ShouldIgnoreNullUser() {
        service.revokeAllForUser(null, "logout-all", Instant.now());
        verifyNoMoreInteractions(repository);
    }

    @Test
    void rotate_ShouldThrowInvalid_WhenTokenMalformed() {
        RefreshTokenService.RefreshTokenException ex = assertThrows(
                RefreshTokenService.RefreshTokenException.class,
                () -> service.rotate("invalid-token", 1L, "device", "1.1.1.1", "ua", Instant.now()));

        assertEquals(RefreshTokenService.RefreshTokenException.Code.INVALID, ex.getCode());
    }

    private User user(Long id) {
        User user = new User("user" + id + "@test.com", "hash", "User " + id);
        user.setId(id);
        return user;
    }
}
