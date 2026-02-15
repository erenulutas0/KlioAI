package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.config.AiRateLimitProperties;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

@Service
public class AiRateLimitService {

    public record Decision(boolean blocked, long retryAfterSeconds, String reason) {
        public static Decision allowed() {
            return new Decision(false, 0, "allowed");
        }

        public static Decision blocked(String reason, long retryAfterSeconds) {
            return new Decision(true, Math.max(1, retryAfterSeconds), reason);
        }
    }

    private static final String USER_PREFIX = "ai:rl:user:";
    private static final String IP_PREFIX = "ai:rl:ip:";
    private static final String DAILY_PREFIX = "ai:quota:day:";
    private static final String DAILY_SCOPE_PREFIX = "ai:quota:day:scope:";

    private static final String METRIC_BLOCK_TOTAL = "ai.rate.limit.block.total";
    private static final String METRIC_REDIS_FAILURE_TOTAL = "ai.rate.limit.redis.failure.total";
    private static final String METRIC_REDIS_FALLBACK_ACTIVE = "ai.rate.limit.redis.fallback.active";
    private static final String METRIC_REDIS_FALLBACK_TRANSITION_TOTAL = "ai.rate.limit.redis.fallback.transition.total";

    private final AiRateLimitProperties properties;
    private final StringRedisTemplate stringRedisTemplate;
    private final MeterRegistry meterRegistry;
    private final AtomicBoolean redisFailureLogged = new AtomicBoolean(false);
    private final AtomicInteger redisFallbackActive = new AtomicInteger(0);

    private final Map<String, WindowCounter> userCounters = new ConcurrentHashMap<>();
    private final Map<String, WindowCounter> ipCounters = new ConcurrentHashMap<>();
    private final Map<String, DailyCounter> dailyCounters = new ConcurrentHashMap<>();

    @Autowired
    public AiRateLimitService(AiRateLimitProperties properties,
                              @Autowired(required = false) StringRedisTemplate stringRedisTemplate,
                              @Autowired(required = false) MeterRegistry meterRegistry) {
        this.properties = properties;
        this.stringRedisTemplate = stringRedisTemplate;
        this.meterRegistry = meterRegistry;
        if (meterRegistry != null) {
            meterRegistry.gauge(METRIC_REDIS_FALLBACK_ACTIVE, redisFallbackActive);
        }
    }

    AiRateLimitService(AiRateLimitProperties properties) {
        this(properties, null, null);
    }

    public Decision checkAndConsume(Long userId, String clientIp, String scope) {
        if (!properties.isEnabled()) {
            return Decision.allowed();
        }

        String normalizedScope = normalize(scope);
        String normalizedIp = normalize(clientIp);
        String normalizedUser = userId == null ? "anonymous" : String.valueOf(userId);

        EffectiveLimits limits = effectiveLimits(normalizedScope);

        if (canUseRedis()) {
            try {
                return checkAndConsumeRedis(normalizedUser, normalizedIp, normalizedScope, limits);
            } catch (Exception ex) {
                onRedisFailure("checkAndConsume");
                if (isFailClosedMode()) {
                    return block("redis-fail-closed", properties.getRedisFailureBlockSeconds(), normalizedScope);
                }
            }
        }

        return checkAndConsumeMemory(normalizedUser, normalizedIp, normalizedScope, limits);
    }

    protected long currentTimeMillis() {
        return System.currentTimeMillis();
    }

    private Decision checkAndConsumeRedis(String userId, String clientIp, String scope, EffectiveLimits limits) {
        long windowSeconds = Math.max(1L, limits.windowSeconds);
        String userKey = USER_PREFIX + scope + ":" + userId;
        String ipKey = IP_PREFIX + scope + ":" + clientIp;
        String dayKey = DAILY_PREFIX + LocalDate.now(ZoneOffset.UTC) + ":" + userId;
        String scopeDayKey = DAILY_SCOPE_PREFIX + LocalDate.now(ZoneOffset.UTC) + ":" + scope + ":" + userId;

        Decision userDecision = incrementAndCheckRedisWindow(userKey, windowSeconds, limits.userWindowMaxRequests,
                "user-burst", scope);
        if (userDecision.blocked()) {
            return userDecision;
        }

        Decision ipDecision = incrementAndCheckRedisWindow(ipKey, windowSeconds, limits.ipWindowMaxRequests,
                "ip-burst", scope);
        if (ipDecision.blocked()) {
            return ipDecision;
        }

        Decision dailyDecision = incrementAndCheckRedisDailyQuota(dayKey, properties.getDailyQuotaPerUser(), scope);
        if (dailyDecision.blocked()) {
            return dailyDecision;
        }

        if (limits.scopeDailyQuotaPerUser != null && limits.scopeDailyQuotaPerUser > 0) {
            Decision scopeDaily = incrementAndCheckRedisDailyQuota(scopeDayKey, limits.scopeDailyQuotaPerUser, scope);
            if (scopeDaily.blocked()) {
                return scopeDaily;
            }
        }

        onRedisSuccess();
        return Decision.allowed();
    }

    private Decision incrementAndCheckRedisWindow(String key, long windowSeconds, int maxRequests, String reason, String scope) {
        Long count = stringRedisTemplate.opsForValue().increment(key);
        if (count == null) {
            return Decision.allowed();
        }
        if (count == 1L) {
            stringRedisTemplate.expire(key, Duration.ofSeconds(windowSeconds));
        }
        if (count > Math.max(1, maxRequests)) {
            Long ttl = stringRedisTemplate.getExpire(key, TimeUnit.SECONDS);
            long retryAfter = (ttl == null || ttl < 1) ? 1 : ttl;
            onRedisSuccess();
            return block(reason, retryAfter, scope);
        }
        return Decision.allowed();
    }

    private Decision incrementAndCheckRedisDailyQuota(String dayKey, int dailyQuota, String scope) {
        Long count = stringRedisTemplate.opsForValue().increment(dayKey);
        if (count == null) {
            return Decision.allowed();
        }
        if (count == 1L) {
            long ttlSeconds = secondsUntilNextUtcDay();
            stringRedisTemplate.expire(dayKey, Duration.ofSeconds(Math.max(1L, ttlSeconds)));
        }
        if (count > Math.max(1, dailyQuota)) {
            Long ttl = stringRedisTemplate.getExpire(dayKey, TimeUnit.SECONDS);
            long retryAfter = (ttl == null || ttl < 1) ? secondsUntilNextUtcDay() : ttl;
            onRedisSuccess();
            return block("daily-quota", retryAfter, scope);
        }
        return Decision.allowed();
    }

    private Decision checkAndConsumeMemory(String userId, String clientIp, String scope, EffectiveLimits limits) {
        long now = currentTimeMillis();
        long windowMs = Math.max(1000L, limits.windowSeconds * 1000L);

        Decision userBurst = checkWindowCounter(userCounters, USER_PREFIX + scope + ":" + userId, now, windowMs,
                Math.max(1, limits.userWindowMaxRequests), "user-burst", scope);
        if (userBurst.blocked()) {
            return userBurst;
        }

        Decision ipBurst = checkWindowCounter(ipCounters, IP_PREFIX + scope + ":" + clientIp, now, windowMs,
                Math.max(1, limits.ipWindowMaxRequests), "ip-burst", scope);
        if (ipBurst.blocked()) {
            return ipBurst;
        }

        DailyCounter dailyCounter = dailyCounters.computeIfAbsent("daily:" + userId, ignored -> new DailyCounter());
        synchronized (dailyCounter) {
            if (dailyCounter.dayStartMs < 0 || now >= dailyCounter.dayEndMs) {
                dailyCounter.dayStartMs = startOfUtcDay(now);
                dailyCounter.dayEndMs = dailyCounter.dayStartMs + TimeUnit.DAYS.toMillis(1);
                dailyCounter.count = 0;
            }
            if (dailyCounter.count >= Math.max(1, properties.getDailyQuotaPerUser())) {
                long retry = Math.max(1L, (dailyCounter.dayEndMs - now + 999L) / 1000L);
                return block("daily-quota", retry, scope);
            }
            dailyCounter.count++;
        }

        if (limits.scopeDailyQuotaPerUser != null && limits.scopeDailyQuotaPerUser > 0) {
            DailyCounter scopeDaily = dailyCounters.computeIfAbsent("daily:" + userId + ":" + scope, ignored -> new DailyCounter());
            synchronized (scopeDaily) {
                if (scopeDaily.dayStartMs < 0 || now >= scopeDaily.dayEndMs) {
                    scopeDaily.dayStartMs = startOfUtcDay(now);
                    scopeDaily.dayEndMs = scopeDaily.dayStartMs + TimeUnit.DAYS.toMillis(1);
                    scopeDaily.count = 0;
                }
                if (scopeDaily.count >= Math.max(1, limits.scopeDailyQuotaPerUser)) {
                    long retry = Math.max(1L, (scopeDaily.dayEndMs - now + 999L) / 1000L);
                    return block("daily-quota", retry, scope);
                }
                scopeDaily.count++;
            }
        }

        return Decision.allowed();
    }

    private Decision checkWindowCounter(Map<String, WindowCounter> map, String key, long now, long windowMs,
                                        int maxRequests, String reason, String scope) {
        WindowCounter counter = map.computeIfAbsent(key, ignored -> new WindowCounter());
        synchronized (counter) {
            if (counter.windowStartMs == 0 || now - counter.windowStartMs >= windowMs) {
                counter.windowStartMs = now;
                counter.count = 0;
            }
            if (counter.count >= maxRequests) {
                long retry = Math.max(1L, (windowMs - (now - counter.windowStartMs) + 999L) / 1000L);
                return block(reason, retry, scope);
            }
            counter.count++;
            return Decision.allowed();
        }
    }

    private Decision block(String reason, long retryAfterSeconds, String scope) {
        if (meterRegistry != null) {
            meterRegistry.counter(METRIC_BLOCK_TOTAL, "reason", reason, "scope", scope).increment();
        }
        return Decision.blocked(reason, retryAfterSeconds);
    }

    private void onRedisFailure(String operation) {
        if (meterRegistry != null) {
            meterRegistry.counter(METRIC_REDIS_FAILURE_TOTAL, "operation", operation).increment();
        }
        if (redisFailureLogged.compareAndSet(false, true)) {
            redisFallbackActive.set(1);
            if (meterRegistry != null) {
                meterRegistry.counter(METRIC_REDIS_FALLBACK_TRANSITION_TOTAL, "state", "activated").increment();
            }
        }
    }

    private void onRedisSuccess() {
        if (redisFailureLogged.compareAndSet(true, false)) {
            redisFallbackActive.set(0);
            if (meterRegistry != null) {
                meterRegistry.counter(METRIC_REDIS_FALLBACK_TRANSITION_TOTAL, "state", "recovered").increment();
            }
        }
    }

    private boolean canUseRedis() {
        return properties.isRedisEnabled() && stringRedisTemplate != null;
    }

    private boolean isFailClosedMode() {
        String mode = properties.getRedisFallbackMode();
        return mode != null && "deny".equalsIgnoreCase(mode.trim());
    }

    private static final class EffectiveLimits {
        final int userWindowMaxRequests;
        final int ipWindowMaxRequests;
        final long windowSeconds;
        final Integer scopeDailyQuotaPerUser;

        private EffectiveLimits(int userWindowMaxRequests, int ipWindowMaxRequests, long windowSeconds, Integer scopeDailyQuotaPerUser) {
            this.userWindowMaxRequests = userWindowMaxRequests;
            this.ipWindowMaxRequests = ipWindowMaxRequests;
            this.windowSeconds = windowSeconds;
            this.scopeDailyQuotaPerUser = scopeDailyQuotaPerUser;
        }
    }

    private EffectiveLimits effectiveLimits(String normalizedScope) {
        AiRateLimitProperties.ScopeLimits scopeLimits = null;
        if (properties.getScopes() != null && normalizedScope != null && !normalizedScope.isBlank()) {
            scopeLimits = properties.getScopes().get(normalizedScope);
        }

        int userMax = properties.getUserWindowMaxRequests();
        int ipMax = properties.getIpWindowMaxRequests();
        long windowSec = properties.getWindowSeconds();
        Integer scopeDaily = null;

        if (scopeLimits != null) {
            if (scopeLimits.getUserWindowMaxRequests() != null) {
                userMax = scopeLimits.getUserWindowMaxRequests();
            }
            if (scopeLimits.getIpWindowMaxRequests() != null) {
                ipMax = scopeLimits.getIpWindowMaxRequests();
            }
            if (scopeLimits.getWindowSeconds() != null) {
                windowSec = scopeLimits.getWindowSeconds();
            }
            if (scopeLimits.getDailyQuotaPerUser() != null) {
                scopeDaily = scopeLimits.getDailyQuotaPerUser();
            }
        }

        return new EffectiveLimits(userMax, ipMax, windowSec, scopeDaily);
    }

    private String normalize(String value) {
        if (value == null) {
            return "unknown";
        }
        String trimmed = value.trim().toLowerCase();
        return trimmed.isEmpty() ? "unknown" : trimmed;
    }

    private long secondsUntilNextUtcDay() {
        long now = currentTimeMillis();
        long dayStart = startOfUtcDay(now);
        long nextDay = dayStart + TimeUnit.DAYS.toMillis(1);
        return Math.max(1L, (nextDay - now + 999L) / 1000L);
    }

    private long startOfUtcDay(long epochMillis) {
        long dayMillis = TimeUnit.DAYS.toMillis(1);
        long daysSinceEpoch = Math.floorDiv(epochMillis, dayMillis);
        return daysSinceEpoch * dayMillis;
    }

    private static final class WindowCounter {
        private long windowStartMs;
        private int count;
    }

    private static final class DailyCounter {
        private long dayStartMs = -1;
        private long dayEndMs = -1;
        private int count;
    }
}
