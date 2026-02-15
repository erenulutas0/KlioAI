package com.ingilizce.calismaapp.security;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class JwtPropertiesTest {

    @Test
    void defaultsAndSetters_ShouldBehaveAsExpected() {
        JwtProperties properties = new JwtProperties();

        assertFalse(properties.isEnforceAuth());
        assertEquals("calismaapp", properties.getIssuer());
        assertEquals(900, properties.getAccessTokenTtlSeconds());
        assertEquals(604800, properties.getRefreshTokenTtlSeconds());
        assertEquals(2592000, properties.getRefreshTokenRememberMeTtlSeconds());
        assertEquals(30, properties.getAllowedClockSkewSeconds());

        properties.setEnforceAuth(true);
        properties.setIssuer("custom-issuer");
        properties.setSecret("custom-secret-value");
        properties.setAccessTokenTtlSeconds(1200);
        properties.setRefreshTokenTtlSeconds(5000);
        properties.setRefreshTokenRememberMeTtlSeconds(6000);
        properties.setAllowedClockSkewSeconds(10);

        assertTrue(properties.isEnforceAuth());
        assertEquals("custom-issuer", properties.getIssuer());
        assertEquals("custom-secret-value", properties.getSecret());
        assertEquals(1200, properties.getAccessTokenTtlSeconds());
        assertEquals(5000, properties.getRefreshTokenTtlSeconds());
        assertEquals(6000, properties.getRefreshTokenRememberMeTtlSeconds());
        assertEquals(10, properties.getAllowedClockSkewSeconds());
    }
}
