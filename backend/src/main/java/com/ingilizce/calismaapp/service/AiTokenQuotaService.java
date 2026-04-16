package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.config.AiTokenQuotaProperties;
import io.micrometer.core.instrument.MeterRegistry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
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
import java.util.concurrent.atomic.AtomicLong;

@Service
public class AiTokenQuotaService {
    private static final Logger log = LoggerFactory.getLogger(AiTokenQuotaService.class);

    public record Decision(boolean blocked,
                           long retryAfterSeconds,
                           String reason,
                           long tokensUsed,
                           long tokenLimit,
                           long tokensRemaining) {
        public static Decision allowed() {
            return new Decision(false, 0, "allowed", 0, 0, 0);
        }

        public static Decision blocked(String reason, long retryAfterSeconds,
                                       long used, long limit) {
            long remaining = Math.max(0L, limit - used);
            return new Decision(true, Math.max(1L, retryAfterSeconds), reason, used, limit, remaining);
        }
    }

    public record Usage(long tokensUsed, long tokensRemaining, long tokenLimit) {
    }

    public record Entitlement(String planCode,
                              boolean aiAccessEnabled,
                              long dailyTokenLimit,
                              boolean trialActive,
                              int trialDaysRemaining) {
    }

    private static final String DAILY_TOKEN_PREFIX = "ai:tokens:day:";
    private static final String DAILY_SCOPE_TOKEN_PREFIX = "ai:tokens:day:scope:";

    private static final String METRIC_BLOCK_TOTAL = "ai.token.quota.block.total";
    private static final String METRIC_REDIS_FAILURE_TOTAL = "ai.token.quota.redis.failure.total";
    private static final String METRIC_REDIS_FALLBACK_ACTIVE = "ai.token.quota.redis.fallback.active";
    private static final String METRIC_REDIS_FALLBACK_TRANSITION_TOTAL = "ai.token.quota.redis.fallback.transition.total";
    private static final String METRIC_MEMORY_SUBJECTS = "ai.token.quota.memory.subjects";
    private static final String METRIC_MEMORY_TRIM_TOTAL = "ai.token.quota.memory.trim.total";

    private final AiTokenQuotaProperties properties;
    private final StringRedisTemplate stringRedisTemplate;
    private final MeterRegistry meterRegistry;
    private final AiEntitlementService aiEntitlementService;

    private final AtomicBoolean redisFailureLogged = new AtomicBoolean(false);
    private final AtomicInteger redisFallbackActive = new AtomicInteger(0);
    private final AtomicLong lastMemoryCleanupEpochMs = new AtomicLong(0L);

    private final Map<String, DailyTokenCounter> dailyCounters = new ConcurrentHashMap<>();

    @Autowired
    public AiTokenQuotaService(AiTokenQuotaProperties properties,
                               @Qualifier("securityStringRedisTemplate")
                               @Autowired(required = false) StringRedisTemplate stringRedisTemplate,
                               @Autowired(required = false) MeterRegistry meterRegistry,
                               @Autowired(required = false) AiEntitlementService aiEntitlementService) {
        this.properties = properties;
        this.stringRedisTemplate = stringRedisTemplate;
        this.meterRegistry = meterRegistry;
        this.aiEntitlementService = aiEntitlementService;
        if (meterRegistry != null) {
            meterRegistry.gauge(METRIC_REDIS_FALLBACK_ACTIVE, redisFallbackActive);
            meterRegistry.gauge(METRIC_MEMORY_SUBJECTS, dailyCounters, map -> map.size());
        }
    }

    AiTokenQuotaService(AiTokenQuotaProperties properties,
                        StringRedisTemplate stringRedisTemplate,
                        MeterRegistry meterRegistry) {
        this(properties, stringRedisTemplate, meterRegistry, null);
    }

    AiTokenQuotaService(AiTokenQuotaProperties properties) {
        this(properties, null, null, null);
    }

    public Decision check(Long userId, String scope) {
        if (!properties.isEnabled()) {
            return Decision.allowed();
        }

        Entitlement entitlement = resolveEntitlement(userId);
        if (!entitlement.aiAccessEnabled()) {
            return Decision.blocked("ai-access-disabled", secondsUntilNextUtcDay(), 0L, entitlement.dailyTokenLimit());
        }

        String normalizedScope = normalize(scope);
        String normalizedUser = userId == null ? "anonymous" : String.valueOf(userId);

        long globalLimit = Math.max(0L, entitlement.dailyTokenLimit());
        Long scopeLimit = resolveScopeLimit(normalizedScope);

        if (canUseRedis()) {
            try {
                return checkRedis(normalizedUser, normalizedScope, globalLimit, scopeLimit);
            } catch (Exception ex) {
                onRedisFailure("check");
                if (isFailClosedMode()) {
                    return Decision.blocked("redis-fail-closed", properties.getRedisFailureBlockSeconds(), 0, 0);
                }
            }
        }

        return checkMemory(normalizedUser, normalizedScope, globalLimit, scopeLimit);
    }

    public Usage consume(Long userId, String scope, long tokens) {
        if (!properties.isEnabled()) {
            return new Usage(0L, 0L, 0L);
        }

        Entitlement entitlement = resolveEntitlement(userId);
        if (!entitlement.aiAccessEnabled()) {
            return new Usage(0L, 0L, entitlement.dailyTokenLimit());
        }

        long delta = Math.max(0L, tokens);
        if (delta == 0L) {
            Decision check = check(userId, scope);
            return new Usage(check.tokensUsed(), check.tokensRemaining(), check.tokenLimit());
        }

        String normalizedScope = normalize(scope);
        String normalizedUser = userId == null ? "anonymous" : String.valueOf(userId);

        long globalLimit = Math.max(0L, entitlement.dailyTokenLimit());
        Long scopeLimit = resolveScopeLimit(normalizedScope);

        if (canUseRedis()) {
            try {
                Usage usage = consumeRedis(normalizedUser, normalizedScope, delta, globalLimit, scopeLimit);
                onRedisSuccess();
                return usage;
            } catch (Exception ex) {
                onRedisFailure("consume");
                if (isFailClosedMode()) {
                    return new Usage(0L, 0L, 0L);
                }
            }
        }

        return consumeMemory(normalizedUser, normalizedScope, delta, globalLimit, scopeLimit);
    }

    public Usage getGlobalUsage(Long userId) {
        Entitlement entitlement = resolveEntitlement(userId);
        long globalLimit = Math.max(0L, entitlement.dailyTokenLimit());
        if (!properties.isEnabled()) {
            return new Usage(0L, globalLimit > 0 ? globalLimit : 0L, globalLimit);
        }
        if (!entitlement.aiAccessEnabled()) {
            return new Usage(0L, 0L, globalLimit);
        }

        String normalizedUser = userId == null ? "anonymous" : String.valueOf(userId);
        if (canUseRedis()) {
            try {
                Usage usage = getGlobalUsageRedis(normalizedUser, globalLimit);
                onRedisSuccess();
                return usage;
            } catch (Exception ex) {
                onRedisFailure("usage");
            }
        }

        return getGlobalUsageMemory(normalizedUser, globalLimit);
    }

    protected long currentTimeMillis() {
        return System.currentTimeMillis();
    }

    public Entitlement getEntitlement(Long userId) {
        return resolveEntitlement(userId);
    }

    private Decision checkRedis(String userId, String scope, long globalLimit, Long scopeLimit) {
        String day = LocalDate.now(ZoneOffset.UTC).toString();
        String globalKey = DAILY_TOKEN_PREFIX + day + ":" + userId;
        String scopeKey = DAILY_SCOPE_TOKEN_PREFIX + day + ":" + scope + ":" + userId;

        if (globalLimit > 0) {
            long used = parseLongOrZero(stringRedisTemplate.opsForValue().get(globalKey));
            if (used >= globalLimit) {
                long retry = ttlOrDaySeconds(globalKey);
                onBlock("daily-token-quota", scope);
                return Decision.blocked("daily-token-quota", retry, used, globalLimit);
            }
        }

        if (scopeLimit != null && scopeLimit > 0) {
            long used = parseLongOrZero(stringRedisTemplate.opsForValue().get(scopeKey));
            if (used >= scopeLimit) {
                long retry = ttlOrDaySeconds(scopeKey);
                onBlock("daily-token-quota", scope);
                return Decision.blocked("daily-token-quota", retry, used, scopeLimit);
            }
        }

        onRedisSuccess();
        return Decision.allowed();
    }

    private Usage consumeRedis(String userId, String scope, long tokens, long globalLimit, Long scopeLimit) {
        String day = LocalDate.now(ZoneOffset.UTC).toString();
        long ttlSeconds = Math.max(1L, secondsUntilNextUtcDay());

        String globalKey = DAILY_TOKEN_PREFIX + day + ":" + userId;
        Long globalUsed = stringRedisTemplate.opsForValue().increment(globalKey, tokens);
        if (globalUsed != null && globalUsed == tokens) {
            stringRedisTemplate.expire(globalKey, Duration.ofSeconds(ttlSeconds));
        }

        Long scopeUsed = null;
        if (scopeLimit != null && scopeLimit > 0) {
            String scopeKey = DAILY_SCOPE_TOKEN_PREFIX + day + ":" + scope + ":" + userId;
            scopeUsed = stringRedisTemplate.opsForValue().increment(scopeKey, tokens);
            if (scopeUsed != null && scopeUsed == tokens) {
                stringRedisTemplate.expire(scopeKey, Duration.ofSeconds(ttlSeconds));
            }
        }

        if (scopeLimit != null && scopeLimit > 0) {
            long used = scopeUsed != null ? scopeUsed : 0L;
            long remaining = Math.max(0L, scopeLimit - used);
            return new Usage(used, remaining, scopeLimit);
        }
        if (globalLimit > 0) {
            long used = globalUsed != null ? globalUsed : 0L;
            long remaining = Math.max(0L, globalLimit - used);
            return new Usage(used, remaining, globalLimit);
        }
        long used = globalUsed != null ? globalUsed : 0L;
        return new Usage(used, 0L, 0L);
    }

    private Decision checkMemory(String userId, String scope, long globalLimit, Long scopeLimit) {
        long now = currentTimeMillis();
        runMemoryCleanupIfNeeded(now);

        if (globalLimit > 0) {
            DailyTokenCounter global = dailyCounters.computeIfAbsent("global:" + userId, ignored -> new DailyTokenCounter());
            synchronized (global) {
                global.rollIfNeeded(now);
                global.lastTouchedMs = now;
                if (global.tokensUsed >= globalLimit) {
                    long retry = global.retryAfterSeconds(now);
                    onBlock("daily-token-quota", scope);
                    return Decision.blocked("daily-token-quota", retry, global.tokensUsed, globalLimit);
                }
            }
        }

        if (scopeLimit != null && scopeLimit > 0) {
            DailyTokenCounter scoped = dailyCounters.computeIfAbsent("scope:" + userId + ":" + scope, ignored -> new DailyTokenCounter());
            synchronized (scoped) {
                scoped.rollIfNeeded(now);
                scoped.lastTouchedMs = now;
                if (scoped.tokensUsed >= scopeLimit) {
                    long retry = scoped.retryAfterSeconds(now);
                    onBlock("daily-token-quota", scope);
                    return Decision.blocked("daily-token-quota", retry, scoped.tokensUsed, scopeLimit);
                }
            }
        }

        return Decision.allowed();
    }

    private Usage consumeMemory(String userId, String scope, long tokens, long globalLimit, Long scopeLimit) {
        long now = currentTimeMillis();
        runMemoryCleanupIfNeeded(now);

        DailyTokenCounter global = dailyCounters.computeIfAbsent("global:" + userId, ignored -> new DailyTokenCounter());
        synchronized (global) {
            global.rollIfNeeded(now);
            global.lastTouchedMs = now;
            global.tokensUsed += tokens;
        }

        if (scopeLimit != null && scopeLimit > 0) {
            DailyTokenCounter scoped = dailyCounters.computeIfAbsent("scope:" + userId + ":" + scope, ignored -> new DailyTokenCounter());
            synchronized (scoped) {
                scoped.rollIfNeeded(now);
                scoped.lastTouchedMs = now;
                scoped.tokensUsed += tokens;
                long remaining = Math.max(0L, scopeLimit - scoped.tokensUsed);
                return new Usage(scoped.tokensUsed, remaining, scopeLimit);
            }
        }

        if (globalLimit > 0) {
            long remaining = Math.max(0L, globalLimit - global.tokensUsed);
            return new Usage(global.tokensUsed, remaining, globalLimit);
        }

        return new Usage(global.tokensUsed, 0L, 0L);
    }

    private Usage getGlobalUsageRedis(String userId, long globalLimit) {
        String day = LocalDate.now(ZoneOffset.UTC).toString();
        String globalKey = DAILY_TOKEN_PREFIX + day + ":" + userId;
        long used = parseLongOrZero(stringRedisTemplate.opsForValue().get(globalKey));
        long remaining = globalLimit > 0 ? Math.max(0L, globalLimit - used) : 0L;
        return new Usage(used, remaining, globalLimit);
    }

    private Usage getGlobalUsageMemory(String userId, long globalLimit) {
        long now = currentTimeMillis();
        runMemoryCleanupIfNeeded(now);

        DailyTokenCounter global = dailyCounters.get("global:" + userId);
        if (global == null) {
            return new Usage(0L, globalLimit > 0 ? globalLimit : 0L, globalLimit);
        }

        synchronized (global) {
            global.rollIfNeeded(now);
            global.lastTouchedMs = now;
            long remaining = globalLimit > 0 ? Math.max(0L, globalLimit - global.tokensUsed) : 0L;
            return new Usage(global.tokensUsed, remaining, globalLimit);
        }
    }

    private Long resolveScopeLimit(String normalizedScope) {
        if (properties.getScopes() == null || normalizedScope == null || normalizedScope.isBlank()) {
            return null;
        }
        AiTokenQuotaProperties.ScopeLimits limits = properties.getScopes().get(normalizedScope);
        if (limits == null) {
            return null;
        }
        return limits.getDailyTokenQuotaPerUser();
    }

    private Entitlement resolveEntitlement(Long userId) {
        if (aiEntitlementService == null) {
            long legacyLimit = Math.max(0L, properties.getDailyTokenQuotaPerUser());
            boolean scopeConfigured = properties.getScopes() != null
                    && properties.getScopes().values().stream()
                    .anyMatch(scope -> scope != null && scope.getDailyTokenQuotaPerUser() != null
                            && scope.getDailyTokenQuotaPerUser() > 0);
            boolean accessEnabled = legacyLimit > 0 || scopeConfigured;
            return new Entitlement(
                    accessEnabled ? "LEGACY" : "FREE",
                    accessEnabled,
                    legacyLimit,
                    false,
                    0);
        }

        AiEntitlementService.Entitlement entitlement = aiEntitlementService.resolve(userId);
        return new Entitlement(
                entitlement.planCode(),
                entitlement.aiAccessEnabled(),
                Math.max(0L, entitlement.dailyTokenLimit()),
                entitlement.trialActive(),
                Math.max(0, entitlement.trialDaysRemaining()));
    }

    private boolean canUseRedis() {
        return properties.isRedisEnabled() && stringRedisTemplate != null;
    }

    private boolean isFailClosedMode() {
        String mode = properties.getRedisFallbackMode();
        return mode != null && "deny".equalsIgnoreCase(mode.trim());
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

    private long ttlOrDaySeconds(String key) {
        Long ttl = stringRedisTemplate.getExpire(key, TimeUnit.SECONDS);
        if (ttl == null || ttl < 1) {
            return secondsUntilNextUtcDay();
        }
        return ttl;
    }

    private long parseLongOrZero(String value) {
        if (value == null || value.isBlank()) {
            return 0L;
        }
        try {
            return Long.parseLong(value.trim());
        } catch (NumberFormatException ignored) {
            return 0L;
        }
    }

    private void onBlock(String reason, String scope) {
        if (meterRegistry != null) {
            meterRegistry.counter(METRIC_BLOCK_TOTAL, "reason", reason, "scope", scope).increment();
        }
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

    private void runMemoryCleanupIfNeeded(long nowMs) {
        long intervalMs = TimeUnit.SECONDS.toMillis(Math.max(5L, properties.getMemoryCleanupIntervalSeconds()));
        long previous = lastMemoryCleanupEpochMs.get();
        if (nowMs - previous < intervalMs) {
            return;
        }
        if (!lastMemoryCleanupEpochMs.compareAndSet(previous, nowMs)) {
            return;
        }

        cleanupDailyTokenCounters(nowMs);
        trimDailyCountersToMax();
    }

    private void cleanupDailyTokenCounters(long nowMs) {
        for (String key : dailyCounters.keySet()) {
            DailyTokenCounter counter = dailyCounters.get(key);
            if (counter == null) {
                continue;
            }

            boolean remove;
            synchronized (counter) {
                long grace = TimeUnit.HOURS.toMillis(1);
                remove = (counter.dayEndMs > 0 && nowMs >= (counter.dayEndMs + grace))
                        || (counter.lastTouchedMs > 0 && nowMs - counter.lastTouchedMs > TimeUnit.DAYS.toMillis(2));
            }

            if (remove) {
                dailyCounters.remove(key, counter);
            }
        }
    }

    private void trimDailyCountersToMax() {
        int maxEntries = Math.max(1_000, properties.getMemoryMaxEntries());
        int currentSize = dailyCounters.size();
        if (currentSize <= maxEntries) {
            return;
        }

        int targetRemovals = currentSize - maxEntries;
        int removed = 0;
        for (String key : dailyCounters.keySet()) {
            if (removed >= targetRemovals) {
                break;
            }
            if (dailyCounters.remove(key) != null) {
                removed++;
            }
        }

        if (removed > 0) {
            if (meterRegistry != null) {
                meterRegistry.counter(METRIC_MEMORY_TRIM_TOTAL).increment(removed);
            }
            log.warn("AI token quota memory map trimmed (removed={}, maxEntries={})", removed, maxEntries);
        }
    }

    private static final class DailyTokenCounter {
        private long dayStartMs = -1;
        private long dayEndMs = -1;
        private long tokensUsed = 0L;
        private long lastTouchedMs = 0L;

        void rollIfNeeded(long nowMs) {
            if (dayStartMs < 0 || nowMs >= dayEndMs) {
                long dayMillis = TimeUnit.DAYS.toMillis(1);
                long daysSinceEpoch = Math.floorDiv(nowMs, dayMillis);
                dayStartMs = daysSinceEpoch * dayMillis;
                dayEndMs = dayStartMs + dayMillis;
                tokensUsed = 0L;
            }
        }

        long retryAfterSeconds(long nowMs) {
            return Math.max(1L, (dayEndMs - nowMs + 999L) / 1000L);
        }
    }
}
