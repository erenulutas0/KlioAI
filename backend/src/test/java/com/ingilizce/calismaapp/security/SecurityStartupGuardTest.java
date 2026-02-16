package com.ingilizce.calismaapp.security;

import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertThrows;

class SecurityStartupGuardTest {

    @Test
    void validate_ShouldThrow_WhenProdProfileAndAuthDisabled() {
        MockEnvironment environment = new MockEnvironment();
        environment.setActiveProfiles("prod");
        JwtProperties jwtProperties = new JwtProperties();
        jwtProperties.setEnforceAuth(false);

        SecurityStartupGuard guard = new SecurityStartupGuard(environment, jwtProperties);

        assertThrows(IllegalStateException.class, guard::validate);
    }

    @Test
    void validate_ShouldPass_WhenProdProfileAndAuthEnabled() {
        MockEnvironment environment = new MockEnvironment();
        environment.setActiveProfiles("prod");
        JwtProperties jwtProperties = new JwtProperties();
        jwtProperties.setEnforceAuth(true);

        SecurityStartupGuard guard = new SecurityStartupGuard(environment, jwtProperties);

        assertDoesNotThrow(guard::validate);
    }

    @Test
    void validate_ShouldPass_WhenNonProdProfileAndAuthDisabled() {
        MockEnvironment environment = new MockEnvironment();
        environment.setActiveProfiles("docker");
        JwtProperties jwtProperties = new JwtProperties();
        jwtProperties.setEnforceAuth(false);

        SecurityStartupGuard guard = new SecurityStartupGuard(environment, jwtProperties);

        assertDoesNotThrow(guard::validate);
    }
}
