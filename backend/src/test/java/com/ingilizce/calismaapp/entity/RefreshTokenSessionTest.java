package com.ingilizce.calismaapp.entity;

import org.junit.jupiter.api.Test;

import java.time.LocalDateTime;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class RefreshTokenSessionTest {

    @Test
    void gettersAndSetters_ShouldStoreValues() {
        RefreshTokenSession session = new RefreshTokenSession();
        User user = new User("session@test.com", "hash", "Session User");
        user.setId(101L);

        LocalDateTime now = LocalDateTime.now();
        LocalDateTime expires = now.plusDays(7);

        session.setId(1L);
        session.setSessionId("sid-1");
        session.setUser(user);
        session.setTokenHash("token-hash");
        session.setDeviceId("device-1");
        session.setUserAgent("ua");
        session.setCreatedIp("10.0.0.1");
        session.setLastUsedIp("10.0.0.2");
        session.setCreatedAt(now);
        session.setLastUsedAt(now.plusMinutes(5));
        session.setExpiresAt(expires);
        session.setRevokedAt(now.plusHours(1));
        session.setRevokeReason("logout");
        session.setReplacedBySessionId("sid-2");
        session.setParentSessionId("sid-parent");
        session.setRememberMe(true);
        session.setReuseDetectedAt(now.plusHours(2));

        assertEquals(1L, session.getId());
        assertEquals("sid-1", session.getSessionId());
        assertEquals(user, session.getUser());
        assertEquals("token-hash", session.getTokenHash());
        assertEquals("device-1", session.getDeviceId());
        assertEquals("ua", session.getUserAgent());
        assertEquals("10.0.0.1", session.getCreatedIp());
        assertEquals("10.0.0.2", session.getLastUsedIp());
        assertEquals(now, session.getCreatedAt());
        assertEquals(now.plusMinutes(5), session.getLastUsedAt());
        assertEquals(expires, session.getExpiresAt());
        assertEquals(now.plusHours(1), session.getRevokedAt());
        assertEquals("logout", session.getRevokeReason());
        assertEquals("sid-2", session.getReplacedBySessionId());
        assertEquals("sid-parent", session.getParentSessionId());
        assertTrue(session.isRememberMe());
        assertEquals(now.plusHours(2), session.getReuseDetectedAt());
    }
}
