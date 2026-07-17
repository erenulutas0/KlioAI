package com.ingilizce.calismaapp.config;

import org.junit.jupiter.api.Test;

import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertTrue;

class AiRateLimitPropertiesTest {

    @Test
    void settersShouldNormalizeUnsafeValues() {
        AiRateLimitProperties properties = new AiRateLimitProperties();

        properties.setEnabled(false);
        properties.setRedisEnabled(false);
        properties.setRedisFallbackMode("block");
        properties.setRedisFailureBlockSeconds(12);
        properties.setUserWindowMaxRequests(5);
        properties.setIpWindowMaxRequests(6);
        properties.setWindowSeconds(7);
        properties.setDailyQuotaPerUser(8);
        properties.setAbusePenaltyEnabled(false);
        properties.setAbusePenaltySeconds(Arrays.asList(null, -3L, 20L));
        properties.setAbuseStrikeResetSeconds(0);
        properties.setMemoryMaxEntriesPerMap(10);
        properties.setMemoryCleanupIntervalSeconds(1);

        assertFalse(properties.isEnabled());
        assertFalse(properties.isRedisEnabled());
        assertEquals("block", properties.getRedisFallbackMode());
        assertEquals(12, properties.getRedisFailureBlockSeconds());
        assertEquals(5, properties.getUserWindowMaxRequests());
        assertEquals(6, properties.getIpWindowMaxRequests());
        assertEquals(7, properties.getWindowSeconds());
        assertEquals(8, properties.getDailyQuotaPerUser());
        assertFalse(properties.isAbusePenaltyEnabled());
        assertEquals(List.of(1L, 1L, 20L), properties.getAbusePenaltySeconds());
        assertEquals(1, properties.getAbuseStrikeResetSeconds());
        assertEquals(1000, properties.getMemoryMaxEntriesPerMap());
        assertEquals(5, properties.getMemoryCleanupIntervalSeconds());
    }

    @Test
    void abusePenaltySecondsShouldFallbackWhenNullOrEmpty() {
        AiRateLimitProperties properties = new AiRateLimitProperties();

        properties.setAbusePenaltySeconds(null);
        assertEquals(List.of(30L, 60L, 150L), properties.getAbusePenaltySeconds());

        properties.setAbusePenaltySeconds(List.of());
        assertEquals(List.of(30L, 60L, 150L), properties.getAbusePenaltySeconds());
    }

    @Test
    void scopesShouldFallbackToEmptyMapWhenNullAndPreserveProvidedMap() {
        AiRateLimitProperties properties = new AiRateLimitProperties();

        properties.setScopes(null);
        assertTrue(properties.getScopes().isEmpty());

        AiRateLimitProperties.ScopeLimits limits = new AiRateLimitProperties.ScopeLimits();
        limits.setUserWindowMaxRequests(10);
        limits.setIpWindowMaxRequests(20);
        limits.setWindowSeconds(30L);
        limits.setDailyQuotaPerUser(40);
        Map<String, AiRateLimitProperties.ScopeLimits> scopes = new HashMap<>();
        scopes.put("speaking", limits);

        properties.setScopes(scopes);

        assertSame(scopes, properties.getScopes());
        assertEquals(10, properties.getScopes().get("speaking").getUserWindowMaxRequests());
        assertEquals(20, properties.getScopes().get("speaking").getIpWindowMaxRequests());
        assertEquals(30L, properties.getScopes().get("speaking").getWindowSeconds());
        assertEquals(40, properties.getScopes().get("speaking").getDailyQuotaPerUser());
    }
}
