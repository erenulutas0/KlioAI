package com.ingilizce.calismaapp.config;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class AiRateLimitPropertiesTest {

    @Test
    void defaults_ShouldMatchSecureBaseline() {
        AiRateLimitProperties properties = new AiRateLimitProperties();

        assertTrue(properties.isEnabled());
        assertTrue(properties.isRedisEnabled());
        assertEquals("memory", properties.getRedisFallbackMode());
        assertEquals(60, properties.getRedisFailureBlockSeconds());
        assertEquals(30, properties.getUserWindowMaxRequests());
        assertEquals(80, properties.getIpWindowMaxRequests());
        assertEquals(60, properties.getWindowSeconds());
        assertEquals(200, properties.getDailyQuotaPerUser());
    }
}
