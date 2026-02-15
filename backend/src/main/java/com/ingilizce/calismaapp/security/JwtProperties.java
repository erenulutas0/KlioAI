package com.ingilizce.calismaapp.security;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "app.security.jwt")
public class JwtProperties {

    private boolean enforceAuth = false;
    private String issuer = "calismaapp";
    private String secret = "";
    private long accessTokenTtlSeconds = 900;
    private long refreshTokenTtlSeconds = 604800;
    private long refreshTokenRememberMeTtlSeconds = 2592000;
    private long allowedClockSkewSeconds = 30;

    public boolean isEnforceAuth() {
        return enforceAuth;
    }

    public void setEnforceAuth(boolean enforceAuth) {
        this.enforceAuth = enforceAuth;
    }

    public String getIssuer() {
        return issuer;
    }

    public void setIssuer(String issuer) {
        this.issuer = issuer;
    }

    public String getSecret() {
        return secret;
    }

    public void setSecret(String secret) {
        this.secret = secret;
    }

    public long getAccessTokenTtlSeconds() {
        return accessTokenTtlSeconds;
    }

    public void setAccessTokenTtlSeconds(long accessTokenTtlSeconds) {
        this.accessTokenTtlSeconds = accessTokenTtlSeconds;
    }

    public long getRefreshTokenTtlSeconds() {
        return refreshTokenTtlSeconds;
    }

    public void setRefreshTokenTtlSeconds(long refreshTokenTtlSeconds) {
        this.refreshTokenTtlSeconds = refreshTokenTtlSeconds;
    }

    public long getRefreshTokenRememberMeTtlSeconds() {
        return refreshTokenRememberMeTtlSeconds;
    }

    public void setRefreshTokenRememberMeTtlSeconds(long refreshTokenRememberMeTtlSeconds) {
        this.refreshTokenRememberMeTtlSeconds = refreshTokenRememberMeTtlSeconds;
    }

    public long getAllowedClockSkewSeconds() {
        return allowedClockSkewSeconds;
    }

    public void setAllowedClockSkewSeconds(long allowedClockSkewSeconds) {
        this.allowedClockSkewSeconds = allowedClockSkewSeconds;
    }
}
