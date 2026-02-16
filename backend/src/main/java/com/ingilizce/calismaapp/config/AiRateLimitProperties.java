package com.ingilizce.calismaapp.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@Component
@ConfigurationProperties(prefix = "app.security.ai-rate-limit")
public class AiRateLimitProperties {

    private boolean enabled = true;
    private boolean redisEnabled = true;
    private String redisFallbackMode = "memory";
    private long redisFailureBlockSeconds = 60;

    private int userWindowMaxRequests = 30;
    private int ipWindowMaxRequests = 80;
    private long windowSeconds = 60;
    private int dailyQuotaPerUser = 200;
    private boolean abusePenaltyEnabled = true;
    private List<Long> abusePenaltySeconds = new ArrayList<>(List.of(30L, 60L, 150L));
    private long abuseStrikeResetSeconds = 900;
    private int memoryMaxEntriesPerMap = 100_000;
    private long memoryCleanupIntervalSeconds = 30;

    /**
     * Optional per-scope overrides, keyed by normalized scope (lowercase, trimmed).
     * Example properties:
     * app.security.ai-rate-limit.scopes.chat.daily-quota-per-user=600
     * app.security.ai-rate-limit.scopes.speaking-evaluate.user-window-max-requests=10
     */
    private Map<String, ScopeLimits> scopes = new HashMap<>();

    public static class ScopeLimits {
        private Integer userWindowMaxRequests;
        private Integer ipWindowMaxRequests;
        private Long windowSeconds;
        private Integer dailyQuotaPerUser;

        public Integer getUserWindowMaxRequests() {
            return userWindowMaxRequests;
        }

        public void setUserWindowMaxRequests(Integer userWindowMaxRequests) {
            this.userWindowMaxRequests = userWindowMaxRequests;
        }

        public Integer getIpWindowMaxRequests() {
            return ipWindowMaxRequests;
        }

        public void setIpWindowMaxRequests(Integer ipWindowMaxRequests) {
            this.ipWindowMaxRequests = ipWindowMaxRequests;
        }

        public Long getWindowSeconds() {
            return windowSeconds;
        }

        public void setWindowSeconds(Long windowSeconds) {
            this.windowSeconds = windowSeconds;
        }

        public Integer getDailyQuotaPerUser() {
            return dailyQuotaPerUser;
        }

        public void setDailyQuotaPerUser(Integer dailyQuotaPerUser) {
            this.dailyQuotaPerUser = dailyQuotaPerUser;
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

    public int getUserWindowMaxRequests() {
        return userWindowMaxRequests;
    }

    public void setUserWindowMaxRequests(int userWindowMaxRequests) {
        this.userWindowMaxRequests = userWindowMaxRequests;
    }

    public int getIpWindowMaxRequests() {
        return ipWindowMaxRequests;
    }

    public void setIpWindowMaxRequests(int ipWindowMaxRequests) {
        this.ipWindowMaxRequests = ipWindowMaxRequests;
    }

    public long getWindowSeconds() {
        return windowSeconds;
    }

    public void setWindowSeconds(long windowSeconds) {
        this.windowSeconds = windowSeconds;
    }

    public int getDailyQuotaPerUser() {
        return dailyQuotaPerUser;
    }

    public void setDailyQuotaPerUser(int dailyQuotaPerUser) {
        this.dailyQuotaPerUser = dailyQuotaPerUser;
    }

    public boolean isAbusePenaltyEnabled() {
        return abusePenaltyEnabled;
    }

    public void setAbusePenaltyEnabled(boolean abusePenaltyEnabled) {
        this.abusePenaltyEnabled = abusePenaltyEnabled;
    }

    public List<Long> getAbusePenaltySeconds() {
        return abusePenaltySeconds;
    }

    public void setAbusePenaltySeconds(List<Long> abusePenaltySeconds) {
        if (abusePenaltySeconds == null || abusePenaltySeconds.isEmpty()) {
            this.abusePenaltySeconds = new ArrayList<>(List.of(30L, 60L, 150L));
            return;
        }

        List<Long> normalized = new ArrayList<>();
        for (Long value : abusePenaltySeconds) {
            normalized.add(Math.max(1L, value == null ? 1L : value));
        }
        this.abusePenaltySeconds = normalized;
    }

    public long getAbuseStrikeResetSeconds() {
        return abuseStrikeResetSeconds;
    }

    public void setAbuseStrikeResetSeconds(long abuseStrikeResetSeconds) {
        this.abuseStrikeResetSeconds = Math.max(1L, abuseStrikeResetSeconds);
    }

    public int getMemoryMaxEntriesPerMap() {
        return memoryMaxEntriesPerMap;
    }

    public void setMemoryMaxEntriesPerMap(int memoryMaxEntriesPerMap) {
        this.memoryMaxEntriesPerMap = Math.max(1_000, memoryMaxEntriesPerMap);
    }

    public long getMemoryCleanupIntervalSeconds() {
        return memoryCleanupIntervalSeconds;
    }

    public void setMemoryCleanupIntervalSeconds(long memoryCleanupIntervalSeconds) {
        this.memoryCleanupIntervalSeconds = Math.max(5L, memoryCleanupIntervalSeconds);
    }

    public Map<String, ScopeLimits> getScopes() {
        return scopes;
    }

    public void setScopes(Map<String, ScopeLimits> scopes) {
        this.scopes = scopes != null ? scopes : new HashMap<>();
    }
}
