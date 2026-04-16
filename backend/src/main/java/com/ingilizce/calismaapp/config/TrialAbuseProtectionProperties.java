package com.ingilizce.calismaapp.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "app.security.trial-abuse")
public class TrialAbuseProtectionProperties {

    private boolean enabled = true;
    private boolean redisEnabled = true;
    private String redisFallbackMode = "memory";
    private long redisFailureBlockSeconds = 60;
    private long windowHours = 24;
    private int maxTrialAccountsPerDevice = 2;
    private int maxTrialAccountsPerIp = 3;

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
        this.redisFailureBlockSeconds = Math.max(1L, redisFailureBlockSeconds);
    }

    public long getWindowHours() {
        return windowHours;
    }

    public void setWindowHours(long windowHours) {
        this.windowHours = Math.max(1L, windowHours);
    }

    public int getMaxTrialAccountsPerDevice() {
        return maxTrialAccountsPerDevice;
    }

    public void setMaxTrialAccountsPerDevice(int maxTrialAccountsPerDevice) {
        this.maxTrialAccountsPerDevice = Math.max(1, maxTrialAccountsPerDevice);
    }

    public int getMaxTrialAccountsPerIp() {
        return maxTrialAccountsPerIp;
    }

    public void setMaxTrialAccountsPerIp(int maxTrialAccountsPerIp) {
        this.maxTrialAccountsPerIp = Math.max(1, maxTrialAccountsPerIp);
    }
}
