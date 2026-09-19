package com.ingilizce.calismaapp.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "app.security.auth-rate-limit")
public class AuthRateLimitProperties {

    private boolean enabled = true;
    private boolean redisEnabled = true;
    /**
     * Redis error policy:
     * - memory: fallback to local in-memory limiter (availability-first)
     * - deny: block auth attempts while Redis path is degraded (enforcement-first)
     */
    private String redisFallbackMode = "memory";
    private long redisFailureBlockSeconds = 60;

    private int loginPrincipalMaxAttempts = 8;
    private long loginPrincipalWindowSeconds = 300;
    private long loginPrincipalBlockSeconds = 900;

    private int loginIpMaxAttempts = 40;
    private long loginIpWindowSeconds = 300;
    private long loginIpBlockSeconds = 900;

    private int registerIpMaxAttempts = 10;
    private long registerIpWindowSeconds = 600;
    private long registerIpBlockSeconds = 1800;

    private int passwordResetIpMaxAttempts = 6;
    private long passwordResetIpWindowSeconds = 600;
    private long passwordResetIpBlockSeconds = 1800;

    // Guest accounts are created without anyone asking for one, and each carries its own
    // daily AI quota, so these count accounts created rather than attempts refused. Twenty
    // an hour from one address is far above a shared network of real installs and far below
    // what a script would want; five a day from one device is more than anyone reinstalls.
    private int guestIpMaxAttempts = 20;
    private long guestIpWindowSeconds = 3600;
    private long guestIpBlockSeconds = 3600;

    private int guestDeviceMaxAttempts = 5;
    private long guestDeviceWindowSeconds = 86400;
    private long guestDeviceBlockSeconds = 86400;

    public int getGuestIpMaxAttempts() {
        return guestIpMaxAttempts;
    }

    public void setGuestIpMaxAttempts(int guestIpMaxAttempts) {
        this.guestIpMaxAttempts = guestIpMaxAttempts;
    }

    public long getGuestIpWindowSeconds() {
        return guestIpWindowSeconds;
    }

    public void setGuestIpWindowSeconds(long guestIpWindowSeconds) {
        this.guestIpWindowSeconds = guestIpWindowSeconds;
    }

    public long getGuestIpBlockSeconds() {
        return guestIpBlockSeconds;
    }

    public void setGuestIpBlockSeconds(long guestIpBlockSeconds) {
        this.guestIpBlockSeconds = guestIpBlockSeconds;
    }

    public int getGuestDeviceMaxAttempts() {
        return guestDeviceMaxAttempts;
    }

    public void setGuestDeviceMaxAttempts(int guestDeviceMaxAttempts) {
        this.guestDeviceMaxAttempts = guestDeviceMaxAttempts;
    }

    public long getGuestDeviceWindowSeconds() {
        return guestDeviceWindowSeconds;
    }

    public void setGuestDeviceWindowSeconds(long guestDeviceWindowSeconds) {
        this.guestDeviceWindowSeconds = guestDeviceWindowSeconds;
    }

    public long getGuestDeviceBlockSeconds() {
        return guestDeviceBlockSeconds;
    }

    public void setGuestDeviceBlockSeconds(long guestDeviceBlockSeconds) {
        this.guestDeviceBlockSeconds = guestDeviceBlockSeconds;
    }

    public boolean isEnabled() {
        return enabled;
    }

    public void setEnabled(boolean enabled) {
        this.enabled = enabled;
    }

    public boolean isRedisEnabled() {
        return redisEnabled;
    }

    public void setRedisEnabled(boolean redisEnabled) {
        this.redisEnabled = redisEnabled;
    }

    public String getRedisFallbackMode() {
        return redisFallbackMode;
    }

    public void setRedisFallbackMode(String redisFallbackMode) {
        this.redisFallbackMode = redisFallbackMode;
    }

    public long getRedisFailureBlockSeconds() {
        return redisFailureBlockSeconds;
    }

    public void setRedisFailureBlockSeconds(long redisFailureBlockSeconds) {
        this.redisFailureBlockSeconds = redisFailureBlockSeconds;
    }

    public int getLoginPrincipalMaxAttempts() {
        return loginPrincipalMaxAttempts;
    }

    public void setLoginPrincipalMaxAttempts(int loginPrincipalMaxAttempts) {
        this.loginPrincipalMaxAttempts = loginPrincipalMaxAttempts;
    }

    public long getLoginPrincipalWindowSeconds() {
        return loginPrincipalWindowSeconds;
    }

    public void setLoginPrincipalWindowSeconds(long loginPrincipalWindowSeconds) {
        this.loginPrincipalWindowSeconds = loginPrincipalWindowSeconds;
    }

    public long getLoginPrincipalBlockSeconds() {
        return loginPrincipalBlockSeconds;
    }

    public void setLoginPrincipalBlockSeconds(long loginPrincipalBlockSeconds) {
        this.loginPrincipalBlockSeconds = loginPrincipalBlockSeconds;
    }

    public int getLoginIpMaxAttempts() {
        return loginIpMaxAttempts;
    }

    public void setLoginIpMaxAttempts(int loginIpMaxAttempts) {
        this.loginIpMaxAttempts = loginIpMaxAttempts;
    }

    public long getLoginIpWindowSeconds() {
        return loginIpWindowSeconds;
    }

    public void setLoginIpWindowSeconds(long loginIpWindowSeconds) {
        this.loginIpWindowSeconds = loginIpWindowSeconds;
    }

    public long getLoginIpBlockSeconds() {
        return loginIpBlockSeconds;
    }

    public void setLoginIpBlockSeconds(long loginIpBlockSeconds) {
        this.loginIpBlockSeconds = loginIpBlockSeconds;
    }

    public int getRegisterIpMaxAttempts() {
        return registerIpMaxAttempts;
    }

    public void setRegisterIpMaxAttempts(int registerIpMaxAttempts) {
        this.registerIpMaxAttempts = registerIpMaxAttempts;
    }

    public long getRegisterIpWindowSeconds() {
        return registerIpWindowSeconds;
    }

    public void setRegisterIpWindowSeconds(long registerIpWindowSeconds) {
        this.registerIpWindowSeconds = registerIpWindowSeconds;
    }

    public long getRegisterIpBlockSeconds() {
        return registerIpBlockSeconds;
    }

    public void setRegisterIpBlockSeconds(long registerIpBlockSeconds) {
        this.registerIpBlockSeconds = registerIpBlockSeconds;
    }

    public int getPasswordResetIpMaxAttempts() {
        return passwordResetIpMaxAttempts;
    }

    public void setPasswordResetIpMaxAttempts(int passwordResetIpMaxAttempts) {
        this.passwordResetIpMaxAttempts = passwordResetIpMaxAttempts;
    }

    public long getPasswordResetIpWindowSeconds() {
        return passwordResetIpWindowSeconds;
    }

    public void setPasswordResetIpWindowSeconds(long passwordResetIpWindowSeconds) {
        this.passwordResetIpWindowSeconds = passwordResetIpWindowSeconds;
    }

    public long getPasswordResetIpBlockSeconds() {
        return passwordResetIpBlockSeconds;
    }

    public void setPasswordResetIpBlockSeconds(long passwordResetIpBlockSeconds) {
        this.passwordResetIpBlockSeconds = passwordResetIpBlockSeconds;
    }
}
