package com.ingilizce.calismaapp.security;

import org.springframework.boot.context.properties.ConfigurationProperties;

import java.util.ArrayList;
import java.util.List;

@ConfigurationProperties(prefix = "app.security.auth")
public class AuthSecurityProperties {

    private long passwordResetTokenTtlSeconds = 900;
    private long emailVerificationTokenTtlSeconds = 86400;
    private boolean exposeDebugTokens = false;
    private boolean emailPasswordEnabled = true;
    private boolean googleIdTokenRequired = false;
    private List<String> googleClientIds = new ArrayList<>();

    public long getPasswordResetTokenTtlSeconds() {
        return passwordResetTokenTtlSeconds;
    }

    public void setPasswordResetTokenTtlSeconds(long passwordResetTokenTtlSeconds) {
        this.passwordResetTokenTtlSeconds = passwordResetTokenTtlSeconds;
    }

    public long getEmailVerificationTokenTtlSeconds() {
        return emailVerificationTokenTtlSeconds;
    }

    public void setEmailVerificationTokenTtlSeconds(long emailVerificationTokenTtlSeconds) {
        this.emailVerificationTokenTtlSeconds = emailVerificationTokenTtlSeconds;
    }

    public boolean isExposeDebugTokens() {
        return exposeDebugTokens;
    }

    public void setExposeDebugTokens(boolean exposeDebugTokens) {
        this.exposeDebugTokens = exposeDebugTokens;
    }

    public boolean isEmailPasswordEnabled() {
        return emailPasswordEnabled;
    }

    public void setEmailPasswordEnabled(boolean emailPasswordEnabled) {
        this.emailPasswordEnabled = emailPasswordEnabled;
    }

    public boolean isGoogleIdTokenRequired() {
        return googleIdTokenRequired;
    }

    public void setGoogleIdTokenRequired(boolean googleIdTokenRequired) {
        this.googleIdTokenRequired = googleIdTokenRequired;
    }

    public List<String> getGoogleClientIds() {
        return googleClientIds;
    }

    public void setGoogleClientIds(List<String> googleClientIds) {
        this.googleClientIds = googleClientIds;
    }
}
