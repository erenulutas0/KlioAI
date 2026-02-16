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
}

