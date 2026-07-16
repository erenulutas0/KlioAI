package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.config.AuthRateLimitProperties;
import com.ingilizce.calismaapp.service.AuthRateLimitService.RateLimitDecision;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class AuthRateLimitServiceTest {

    @Test
    void login_ShouldBeBlockedAfterConfiguredFailures_AndRecoverAfterBlockWindow() {
        AuthRateLimitProperties properties = new AuthRateLimitProperties();
        properties.setEnabled(true);
        properties.setLoginPrincipalMaxAttempts(2);
        properties.setLoginPrincipalWindowSeconds(60);
        properties.setLoginPrincipalBlockSeconds(120);
        properties.setLoginIpMaxAttempts(100);

        TestableAuthRateLimitService service = new TestableAuthRateLimitService(properties);

        assertFalse(service.checkLogin("user@test.com", "10.0.0.1").blocked());
        service.recordLoginFailure("user@test.com", "10.0.0.1");
        assertFalse(service.checkLogin("user@test.com", "10.0.0.1").blocked());
        service.recordLoginFailure("user@test.com", "10.0.0.1");

        RateLimitDecision blocked = service.checkLogin("user@test.com", "10.0.0.1");
        assertTrue(blocked.blocked());
        assertTrue(blocked.retryAfterSeconds() >= 1);

        service.advanceSeconds(121);
        assertFalse(service.checkLogin("user@test.com", "10.0.0.1").blocked());
    }

    @Test
    void register_ShouldBeBlockedByIpAfterConfiguredFailures() {
        AuthRateLimitProperties properties = new AuthRateLimitProperties();
        properties.setEnabled(true);
        properties.setRegisterIpMaxAttempts(1);
        properties.setRegisterIpWindowSeconds(600);
        properties.setRegisterIpBlockSeconds(60);

        TestableAuthRateLimitService service = new TestableAuthRateLimitService(properties);

        assertFalse(service.checkRegister("10.0.0.2").blocked());
        service.recordRegisterFailure("10.0.0.2");

        assertTrue(service.checkRegister("10.0.0.2").blocked());
    }

    @Test
    void disabledMode_ShouldAlwaysAllow() {
        AuthRateLimitProperties properties = new AuthRateLimitProperties();
        properties.setEnabled(false);

        TestableAuthRateLimitService service = new TestableAuthRateLimitService(properties);
        service.recordLoginFailure("user@test.com", "10.0.0.3");
        service.recordRegisterFailure("10.0.0.3");

        assertFalse(service.checkLogin("user@test.com", "10.0.0.3").blocked());
        assertFalse(service.checkRegister("10.0.0.3").blocked());
    }

    @Test
    void login_ShouldShareRateLimitBucket_RegardlessOfCapitalIInEmail_OnTurkishLocaleJvm() {
        java.util.Locale original = java.util.Locale.getDefault();
        try {
            java.util.Locale.setDefault(new java.util.Locale("tr", "TR"));

            AuthRateLimitProperties properties = new AuthRateLimitProperties();
            properties.setEnabled(true);
            properties.setLoginPrincipalMaxAttempts(2);
            properties.setLoginPrincipalWindowSeconds(60);
            properties.setLoginPrincipalBlockSeconds(120);
            properties.setLoginIpMaxAttempts(100);

            TestableAuthRateLimitService service = new TestableAuthRateLimitService(properties);

            // Same address, alternating case of 'I' - without Locale.ROOT this would
            // land in two different buckets on a Turkish-locale JVM, letting an
            // attacker dodge the block by flipping the case of one letter.
            service.recordLoginFailure("MIKE@test.com", "10.0.0.5");
            service.recordLoginFailure("mike@test.com", "10.0.0.5");

            assertTrue(service.checkLogin("Mike@test.com", "10.0.0.5").blocked());
        } finally {
            java.util.Locale.setDefault(original);
        }
    }

    @Test
    void passwordReset_ShouldBeBlockedByIpAfterConfiguredFailures() {
        AuthRateLimitProperties properties = new AuthRateLimitProperties();
        properties.setEnabled(true);
        properties.setPasswordResetIpMaxAttempts(1);
        properties.setPasswordResetIpWindowSeconds(600);
        properties.setPasswordResetIpBlockSeconds(60);

        TestableAuthRateLimitService service = new TestableAuthRateLimitService(properties);

        assertFalse(service.checkPasswordResetRequest("10.0.0.4").blocked());
        service.recordPasswordResetRequest("10.0.0.4");

        assertTrue(service.checkPasswordResetRequest("10.0.0.4").blocked());
    }

    private static class TestableAuthRateLimitService extends AuthRateLimitService {
        private long nowMs = 1_000_000L;

        private TestableAuthRateLimitService(AuthRateLimitProperties properties) {
            super(properties);
        }

        @Override
        protected long currentTimeMillis() {
            return nowMs;
        }

        private void advanceSeconds(long seconds) {
            nowMs += seconds * 1000;
        }
    }
}
