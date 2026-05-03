package com.ingilizce.calismaapp.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

import java.util.HashMap;
import java.util.Map;

@Component
@ConfigurationProperties(prefix = "app.security.ai-token-quota")
public class AiTokenQuotaProperties {

    private boolean enabled = false;
    private boolean redisEnabled = true;
    private String redisFallbackMode = "memory";
    private long redisFailureBlockSeconds = 60;
    private int memoryMaxEntries = 100_000;
    private long memoryCleanupIntervalSeconds = 30;
    private int trialDurationDays = 7;
    private long trialDailyTokenQuotaPerUser = 5_000;
    private long freeDailyTokenQuotaPerUser = 1_500;
    private long premiumDailyTokenQuotaPerUser = 30_000;
    private long premiumPlusDailyTokenQuotaPerUser = 60_000;
    private double estimatedCostUsdPerMillionTokens = 0.10;

    /**
     * Global daily token budget per user (prompt + completion tokens).
     * Set <= 0 to disable global budget.
     */
    private long dailyTokenQuotaPerUser = 0;

    /**
     * Optional per-scope budgets keyed by normalized scope.
     * Example:
     * app.security.ai-token-quota.scopes.chat.daily-token-quota-per-user=50000
     */
    private Map<String, ScopeLimits> scopes = new HashMap<>();

    public static class ScopeLimits {
        private Long dailyTokenQuotaPerUser;

        public Long getDailyTokenQuotaPerUser() {
            return dailyTokenQuotaPerUser;
        }

        public void setDailyTokenQuotaPerUser(Long dailyTokenQuotaPerUser) {
            this.dailyTokenQuotaPerUser = dailyTokenQuotaPerUser;
        }
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

    public int getMemoryMaxEntries() {
        return memoryMaxEntries;
    }

    public void setMemoryMaxEntries(int memoryMaxEntries) {
        this.memoryMaxEntries = Math.max(1_000, memoryMaxEntries);
    }

    public long getMemoryCleanupIntervalSeconds() {
        return memoryCleanupIntervalSeconds;
    }

    public void setMemoryCleanupIntervalSeconds(long memoryCleanupIntervalSeconds) {
        this.memoryCleanupIntervalSeconds = Math.max(5L, memoryCleanupIntervalSeconds);
    }

    public long getDailyTokenQuotaPerUser() {
        return dailyTokenQuotaPerUser;
    }

    public void setDailyTokenQuotaPerUser(long dailyTokenQuotaPerUser) {
        this.dailyTokenQuotaPerUser = dailyTokenQuotaPerUser;
    }

    public Map<String, ScopeLimits> getScopes() {
        return scopes;
    }

    public void setScopes(Map<String, ScopeLimits> scopes) {
        this.scopes = scopes != null ? scopes : new HashMap<>();
    }

    public int getTrialDurationDays() {
        return trialDurationDays;
    }

    public void setTrialDurationDays(int trialDurationDays) {
        this.trialDurationDays = Math.max(0, trialDurationDays);
    }

    public long getTrialDailyTokenQuotaPerUser() {
        return trialDailyTokenQuotaPerUser;
    }

    public void setTrialDailyTokenQuotaPerUser(long trialDailyTokenQuotaPerUser) {
        this.trialDailyTokenQuotaPerUser = Math.max(0L, trialDailyTokenQuotaPerUser);
    }

    public long getFreeDailyTokenQuotaPerUser() {
        return freeDailyTokenQuotaPerUser;
    }

    public void setFreeDailyTokenQuotaPerUser(long freeDailyTokenQuotaPerUser) {
        this.freeDailyTokenQuotaPerUser = Math.max(0L, freeDailyTokenQuotaPerUser);
    }

    public long getPremiumDailyTokenQuotaPerUser() {
        return premiumDailyTokenQuotaPerUser;
    }

    public void setPremiumDailyTokenQuotaPerUser(long premiumDailyTokenQuotaPerUser) {
        this.premiumDailyTokenQuotaPerUser = Math.max(0L, premiumDailyTokenQuotaPerUser);
    }

    public long getPremiumPlusDailyTokenQuotaPerUser() {
        return premiumPlusDailyTokenQuotaPerUser;
    }

    public void setPremiumPlusDailyTokenQuotaPerUser(long premiumPlusDailyTokenQuotaPerUser) {
        this.premiumPlusDailyTokenQuotaPerUser = Math.max(0L, premiumPlusDailyTokenQuotaPerUser);
    }

    public double getEstimatedCostUsdPerMillionTokens() {
        return estimatedCostUsdPerMillionTokens;
    }

    public void setEstimatedCostUsdPerMillionTokens(double estimatedCostUsdPerMillionTokens) {
        this.estimatedCostUsdPerMillionTokens = Math.max(0.0, estimatedCostUsdPerMillionTokens);
    }
}
