package com.ingilizce.calismaapp.security;

import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class AuthSecurityPropertiesTest {

    @Test
    void defaultsAndSetters_ShouldBehaveAsExpected() {
        AuthSecurityProperties properties = new AuthSecurityProperties();

        assertEquals(900, properties.getPasswordResetTokenTtlSeconds());
        assertEquals(86400, properties.getEmailVerificationTokenTtlSeconds());
        assertFalse(properties.isExposeDebugTokens());
        assertFalse(properties.isGoogleIdTokenRequired());
        assertTrue(properties.getGoogleClientIds().isEmpty());

        properties.setPasswordResetTokenTtlSeconds(1200);
        properties.setEmailVerificationTokenTtlSeconds(172800);
        properties.setExposeDebugTokens(true);
        properties.setGoogleIdTokenRequired(true);
        properties.setGoogleClientIds(List.of("client-a", "client-b"));

        assertEquals(1200, properties.getPasswordResetTokenTtlSeconds());
        assertEquals(172800, properties.getEmailVerificationTokenTtlSeconds());
        assertTrue(properties.isExposeDebugTokens());
        assertTrue(properties.isGoogleIdTokenRequired());
        assertEquals(List.of("client-a", "client-b"), properties.getGoogleClientIds());
    }
}
