package com.ingilizce.calismaapp.security;

import jakarta.annotation.PostConstruct;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;
import org.springframework.stereotype.Component;

@Component
public class SecurityStartupGuard {

    private final Environment environment;
    private final JwtProperties jwtProperties;

    public SecurityStartupGuard(Environment environment, JwtProperties jwtProperties) {
        this.environment = environment;
        this.jwtProperties = jwtProperties;
    }

    @PostConstruct
    void validate() {
        if (environment.acceptsProfiles(Profiles.of("prod")) && !jwtProperties.isEnforceAuth()) {
            throw new IllegalStateException(
                    "Invalid production security config: app.security.jwt.enforce-auth must be true in prod profile.");
        }
    }
}
