package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.config.AiRateLimitProperties;
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
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

@Service
public class AiRateLimitService {
    private static final Logger log = LoggerFactory.getLogger(AiRateLimitService.class);

    public record Decision(boolean blocked,
                           long retryAfterSeconds,
                           String reason,
                           int penaltyLevel,
                           long nextPenaltySeconds) {
        public static Decision allowed() {
            return new Decision(false, 0, "allowed", 0, 0);
        }

        public static Decision blocked(String reason, long retryAfterSeconds) {
            return new Decision(true, Math.max(1, retryAfterSeconds), reason, 0, 0);
        }

        public static Decision blockedWithPenalty(String reason,
                                                  long retryAfterSeconds,
                                                  int penaltyLevel,
                                                  long nextPenaltySeconds) {
            return new Decision(true,
                    Math.max(1, retryAfterSeconds),
                    reason,
                    Math.max(1, penaltyLevel),
                    Math.max(1, nextPenaltySeconds));
        }
    }

    public record UnbanResult(boolean userSubjectRequested,
                              boolean ipSubjectRequested,
                              boolean userPenaltyCleared,
                              boolean ipPenaltyCleared,
                              String userSubject,
                              String ipSubject) {
    }

    public record AbusePenaltyStatus(boolean userSubjectRequested,
                                     boolean ipSubjectRequested,
                                     boolean userPenaltyActive,
                                     boolean ipPenaltyActive,
                                     long userRetryAfterSeconds,
                                     long ipRetryAfterSeconds,
                                     String userSubject,
                                     String ipSubject) {
    }

    public record AbuseStats(boolean enabled,
                             boolean redisEnabled,
                             String redisFallbackMode,
                             boolean redisFallbackActive,
                             boolean abusePenaltyEnabled,
                             long abuseStrikeResetSeconds,
                             List<Long> abusePenaltySeconds,
                             int configuredScopeCount,
                             int memoryPenaltySubjects,
                             int memoryActivePenaltySubjects,
                             int memoryUserWindowSubjects,
                             int memoryIpWindowSubjects) {
    }

    private static final String USER_PREFIX = "ai:rl:user:";
    private static final String IP_PREFIX = "ai:rl:ip:";
    private static final String DAILY_PREFIX = "ai:quota:day:";
    private static final String DAILY_SCOPE_PREFIX = "ai:quota:day:scope:";
    private static final String PENALTY_BAN_PREFIX = "ai:rl:penalty:ban:";
    private static final String PENALTY_STRIKE_PREFIX = "ai:rl:penalty:strike:";
    private static final String ABUSE_BAN_REASON = "abuse-ban";

    private static final String METRIC_BLOCK_TOTAL = "ai.rate.limit.block.total";
    private static final String METRIC_PENALTY_APPLY_TOTAL = "ai.rate.limit.abuse.penalty.apply.total";
    private static final String METRIC_UNBAN_TOTAL = "ai.rate.limit.abuse.unban.total";
    private static final String METRIC_REDIS_FAILURE_TOTAL = "ai.rate.limit.redis.failure.total";
    private static final String METRIC_REDIS_FALLBACK_ACTIVE = "ai.rate.limit.redis.fallback.active";
    private static final String METRIC_REDIS_FALLBACK_TRANSITION_TOTAL = "ai.rate.limit.redis.fallback.transition.total";
    private static final String METRIC_MEMORY_PENALTY_SUBJECTS = "ai.rate.limit.abuse.memory.subjects";
    private static final String METRIC_MEMORY_ACTIVE_PENALTY_SUBJECTS = "ai.rate.limit.abuse.memory.active.subjects";
    private static final String METRIC_MEMORY_TRIM_TOTAL = "ai.rate.limit.memory.trim.total";

    private final AiRateLimitProperties properties;
    private final StringRedisTemplate stringRedisTemplate;
    private final MeterRegistry meterRegistry;
    private final AtomicBoolean redisFailureLogged = new AtomicBoolean(false);
    private final AtomicInteger redisFallbackActive = new AtomicInteger(0);
    private final AtomicLong lastMemoryCleanupEpochMs = new AtomicLong(0L);

    private final Map<String, WindowCounter> userCounters = new ConcurrentHashMap<>();
    private final Map<String, WindowCounter> ipCounters = new ConcurrentHashMap<>();
    private final Map<String, DailyCounter> dailyCounters = new ConcurrentHashMap<>();
    private final Map<String, PenaltyCounter> penaltyCounters = new ConcurrentHashMap<>();

    @Autowired
    public AiRateLimitService(AiRateLimitProperties properties,
                              @Qualifier("securityStringRedisTemplate")
                              @Autowired(required = false) StringRedisTemplate stringRedisTemplate,
                              @Autowired(required = false) MeterRegistry meterRegistry) {
        this.properties = properties;
        this.stringRedisTemplate = stringRedisTemplate;
        this.meterRegistry = meterRegistry;
        if (meterRegistry != null) {
            meterRegistry.gauge(METRIC_REDIS_FALLBACK_ACTIVE, redisFallbackActive);
            meterRegistry.gauge(METRIC_MEMORY_PENALTY_SUBJECTS, penaltyCounters, map -> map.size());
            meterRegistry.gauge(METRIC_MEMORY_ACTIVE_PENALTY_SUBJECTS, penaltyCounters,
                    ignored -> countActivePenaltySubjectsSnapshot());
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

    public UnbanResult clearAbusePenalty(Long userId, String clientIp) {
        String normalizedUser = userId == null ? null : normalize(String.valueOf(userId));
        String normalizedIp = (clientIp == null || clientIp.isBlank()) ? null : normalize(clientIp);

        String userSubject = (normalizedUser == null || normalizedUser.isBlank()) ? null : ("u:" + normalizedUser);
        String ipSubject = (normalizedIp == null || normalizedIp.isBlank()) ? null : penaltySubjectForIp(normalizedIp);

        boolean userCleared = clearPenaltyForSubject(userSubject);
        boolean ipCleared = clearPenaltyForSubject(ipSubject);

        if (userSubject != null) {
            onUnban(userCleared, "user", userSubject);
        }
        if (ipSubject != null) {
            onUnban(ipCleared, "ip", ipSubject);
        }

        return new UnbanResult(
                userSubject != null,
                ipSubject != null,
                userCleared,
                ipCleared,
                userSubject,
                ipSubject);
    }

    public AbusePenaltyStatus getAbusePenaltyStatus(Long userId, String clientIp) {
        String normalizedUser = userId == null ? null : normalize(String.valueOf(userId));
        String normalizedIp = (clientIp == null || clientIp.isBlank()) ? null : normalize(clientIp);

        String userSubject = (normalizedUser == null || normalizedUser.isBlank()) ? null : ("u:" + normalizedUser);
        String ipSubject = (normalizedIp == null || normalizedIp.isBlank()) ? null : penaltySubjectForIp(normalizedIp);

        PenaltyState userPenalty = readPenaltyState(userSubject);
        PenaltyState ipPenalty = readPenaltyState(ipSubject);

        return new AbusePenaltyStatus(
                userSubject != null,
                ipSubject != null,
                userPenalty.active,
                ipPenalty.active,
                userPenalty.retryAfterSeconds,
                ipPenalty.retryAfterSeconds,
                userSubject,
                ipSubject);
    }

    public AbuseStats getAbuseStats() {
        return new AbuseStats(
                properties.isEnabled(),
                canUseRedis(),
                properties.getRedisFallbackMode(),
                redisFallbackActive.get() == 1,
                properties.isAbusePenaltyEnabled(),
                properties.getAbuseStrikeResetSeconds(),
                List.copyOf(properties.getAbusePenaltySeconds()),
                properties.getScopes() != null ? properties.getScopes().size() : 0,
                penaltyCounters.size(),
                countActivePenaltySubjectsSnapshot(),
                userCounters.size(),
                ipCounters.size());
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
        boolean authenticatedUser = isAuthenticatedUserKey(userId);
        String userPenaltySubject = penaltySubjectForUser(userId, clientIp);
        String ipPenaltySubject = authenticatedUser ? null : penaltySubjectForIp(clientIp);

        Decision activeUserPenalty = checkActivePenaltyRedis(userPenaltySubject, scope);
        if (activeUserPenalty.blocked()) {
            return activeUserPenalty;
        }
        if (ipPenaltySubject != null && !userPenaltySubject.equals(ipPenaltySubject)) {
            Decision activeIpPenalty = checkActivePenaltyRedis(ipPenaltySubject, scope);
            if (activeIpPenalty.blocked()) {
                return activeIpPenalty;
            }
        }

        Decision userDecision = incrementAndCheckRedisWindow(
                userKey,
                windowSeconds,
                limits.userWindowMaxRequests,
                "user-burst",
                scope,
                userPenaltySubject);
        if (userDecision.blocked()) {
            return userDecision;
        }

        Decision ipDecision = incrementAndCheckRedisWindow(
                ipKey,
                windowSeconds,
                limits.ipWindowMaxRequests,
                "ip-burst",
                scope,
                ipPenaltySubject);
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

    private Decision incrementAndCheckRedisWindow(String key,
                                                  long windowSeconds,
                                                  int maxRequests,
                                                  String reason,
                                                  String scope,
                                                  String penaltySubject) {
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
            return applyPenaltyRedis(penaltySubject, reason, retryAfter, scope);
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
        runMemoryCleanupIfNeeded(now);
        boolean authenticatedUser = isAuthenticatedUserKey(userId);
        String userPenaltySubject = penaltySubjectForUser(userId, clientIp);
        String ipPenaltySubject = authenticatedUser ? null : penaltySubjectForIp(clientIp);

        Decision activeUserPenalty = checkActivePenaltyMemory(userPenaltySubject, now, scope);
        if (activeUserPenalty.blocked()) {
            return activeUserPenalty;
        }
        if (ipPenaltySubject != null && !userPenaltySubject.equals(ipPenaltySubject)) {
            Decision activeIpPenalty = checkActivePenaltyMemory(ipPenaltySubject, now, scope);
            if (activeIpPenalty.blocked()) {
                return activeIpPenalty;
            }
        }

        Decision userBurst = checkWindowCounter(userCounters, USER_PREFIX + scope + ":" + userId, now, windowMs,
                Math.max(1, limits.userWindowMaxRequests), "user-burst", scope, userPenaltySubject);
        if (userBurst.blocked()) {
            return userBurst;
        }

        Decision ipBurst = checkWindowCounter(ipCounters, IP_PREFIX + scope + ":" + clientIp, now, windowMs,
                Math.max(1, limits.ipWindowMaxRequests), "ip-burst", scope, ipPenaltySubject);
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
            dailyCounter.lastTouchedMs = now;
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
                scopeDaily.lastTouchedMs = now;
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
                                        int maxRequests, String reason, String scope, String penaltySubject) {
        WindowCounter counter = map.computeIfAbsent(key, ignored -> new WindowCounter());
        synchronized (counter) {
            counter.windowMs = windowMs;
            counter.lastTouchedMs = now;
            if (counter.windowStartMs == 0 || now - counter.windowStartMs >= windowMs) {
                counter.windowStartMs = now;
                counter.count = 0;
            }
            if (counter.count >= maxRequests) {
                long retry = Math.max(1L, (windowMs - (now - counter.windowStartMs) + 999L) / 1000L);
                return applyPenaltyMemory(penaltySubject, reason, retry, now, scope);
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

    private Decision blockWithPenalty(String reason,
                                      long retryAfterSeconds,
                                      int penaltyLevel,
                                      long nextPenaltySeconds,
                                      String scope) {
        if (meterRegistry != null) {
            meterRegistry.counter(METRIC_BLOCK_TOTAL, "reason", reason, "scope", scope).increment();
        }
        return Decision.blockedWithPenalty(reason, retryAfterSeconds, penaltyLevel, nextPenaltySeconds);
    }

    private Decision checkActivePenaltyRedis(String penaltySubject, String scope) {
        if (!properties.isAbusePenaltyEnabled() || penaltySubject == null || penaltySubject.isBlank()) {
            return Decision.allowed();
        }

        String banKey = PENALTY_BAN_PREFIX + penaltySubject;
        Long ttl = stringRedisTemplate.getExpire(banKey, TimeUnit.SECONDS);
        if (ttl == null || ttl < 1L) {
            return Decision.allowed();
        }

        long strikes = currentPenaltyStrikeRedis(penaltySubject);
        int level = penaltyLevelForStrike(strikes);
        long nextPenalty = penaltyForStrike(strikes + 1);
        return blockWithPenalty(ABUSE_BAN_REASON, ttl, level, nextPenalty, scope);
    }

    private Decision applyPenaltyRedis(String penaltySubject, String burstReason, long burstRetryAfter, String scope) {
        if (!properties.isAbusePenaltyEnabled() || penaltySubject == null || penaltySubject.isBlank()) {
            return block(burstReason, burstRetryAfter, scope);
        }

        String strikeKey = PENALTY_STRIKE_PREFIX + penaltySubject;
        Long strikes = stringRedisTemplate.opsForValue().increment(strikeKey);
        long normalizedStrikes = strikes == null ? 1L : strikes;
        stringRedisTemplate.expire(
                strikeKey,
                Duration.ofSeconds(Math.max(1L, properties.getAbuseStrikeResetSeconds())));

        long penaltySeconds = penaltyForStrike(normalizedStrikes);
        String banKey = PENALTY_BAN_PREFIX + penaltySubject;
        stringRedisTemplate.opsForValue().set(banKey, "1", Duration.ofSeconds(penaltySeconds));

        int level = penaltyLevelForStrike(normalizedStrikes);
        long nextPenalty = penaltyForStrike(normalizedStrikes + 1);
        onPenaltyApplied("redis", penaltySubject, burstReason, scope, level, penaltySeconds);
        return blockWithPenalty(burstReason, penaltySeconds, level, nextPenalty, scope);
    }

    private long currentPenaltyStrikeRedis(String penaltySubject) {
        String strikeValue = stringRedisTemplate.opsForValue().get(PENALTY_STRIKE_PREFIX + penaltySubject);
        if (strikeValue == null || strikeValue.isBlank()) {
            return 1L;
        }

        try {
            return Math.max(1L, Long.parseLong(strikeValue.trim()));
        } catch (NumberFormatException ignored) {
            return 1L;
        }
    }

    private Decision checkActivePenaltyMemory(String penaltySubject, long now, String scope) {
        if (!properties.isAbusePenaltyEnabled()) {
            return Decision.allowed();
        }

        PenaltyCounter counter = penaltyCounters.get(penaltySubject);
        if (counter == null) {
            return Decision.allowed();
        }

        synchronized (counter) {
            counter.lastTouchedMs = now;
            if (counter.strikeResetAtMs > 0 && now >= counter.strikeResetAtMs) {
                counter.strikes = 0;
                counter.blockedUntilMs = 0;
                counter.strikeResetAtMs = 0;
            }

            if (counter.blockedUntilMs <= now) {
                return Decision.allowed();
            }

            long retry = Math.max(1L, (counter.blockedUntilMs - now + 999L) / 1000L);
            int level = penaltyLevelForStrike(counter.strikes);
            long nextPenalty = penaltyForStrike((long) counter.strikes + 1L);
            return blockWithPenalty(ABUSE_BAN_REASON, retry, level, nextPenalty, scope);
        }
    }

    private Decision applyPenaltyMemory(String penaltySubject,
                                        String burstReason,
                                        long burstRetryAfter,
                                        long now,
                                        String scope) {
        if (!properties.isAbusePenaltyEnabled() || penaltySubject == null || penaltySubject.isBlank()) {
            return block(burstReason, burstRetryAfter, scope);
        }

        PenaltyCounter counter = penaltyCounters.computeIfAbsent(penaltySubject, ignored -> new PenaltyCounter());
        synchronized (counter) {
            counter.lastTouchedMs = now;
            if (counter.strikeResetAtMs > 0 && now >= counter.strikeResetAtMs) {
                counter.strikes = 0;
                counter.blockedUntilMs = 0;
            }

            counter.strikes++;
            long resetMs = TimeUnit.SECONDS.toMillis(Math.max(1L, properties.getAbuseStrikeResetSeconds()));
            counter.strikeResetAtMs = now + resetMs;

            long penaltySeconds = penaltyForStrike(counter.strikes);
            counter.blockedUntilMs = now + TimeUnit.SECONDS.toMillis(penaltySeconds);

            int level = penaltyLevelForStrike(counter.strikes);
            long nextPenalty = penaltyForStrike((long) counter.strikes + 1L);
            onPenaltyApplied("memory", penaltySubject, burstReason, scope, level, penaltySeconds);
            return blockWithPenalty(burstReason, penaltySeconds, level, nextPenalty, scope);
        }
    }

    private String penaltySubjectForUser(String normalizedUser, String normalizedIp) {
        if (normalizedUser != null && !normalizedUser.isBlank() && !"anonymous".equals(normalizedUser)) {
            return "u:" + normalizedUser;
        }
        return penaltySubjectForIp(normalizedIp);
    }

    private boolean isAuthenticatedUserKey(String normalizedUser) {
        return normalizedUser != null && !normalizedUser.isBlank() && !"anonymous".equals(normalizedUser);
    }

    private String penaltySubjectForIp(String normalizedIp) {
        String value = (normalizedIp == null || normalizedIp.isBlank()) ? "unknown" : normalizedIp;
        return "ip:" + value;
    }

    private boolean clearPenaltyForSubject(String subject) {
        if (subject == null || subject.isBlank()) {
            return false;
        }

        boolean memoryCleared = penaltyCounters.remove(subject) != null;
        boolean redisCleared = false;

        if (canUseRedis()) {
            try {
                Boolean banDeleted = stringRedisTemplate.delete(PENALTY_BAN_PREFIX + subject);
                Boolean strikeDeleted = stringRedisTemplate.delete(PENALTY_STRIKE_PREFIX + subject);
                redisCleared = Boolean.TRUE.equals(banDeleted) || Boolean.TRUE.equals(strikeDeleted);
                onRedisSuccess();
            } catch (Exception ex) {
                onRedisFailure("clearAbusePenalty");
            }
        }

        return memoryCleared || redisCleared;
    }

    private int penaltyLevelForStrike(long strikes) {
        int size = Math.max(1, properties.getAbusePenaltySeconds().size());
        return (int) Math.max(1L, Math.min(strikes, (long) size));
    }

    private long penaltyForStrike(long strikes) {
        if (properties.getAbusePenaltySeconds() == null || properties.getAbusePenaltySeconds().isEmpty()) {
            return 30L;
        }

        int idx = (int) Math.max(0L, Math.min(strikes - 1L, properties.getAbusePenaltySeconds().size() - 1L));
        Long configured = properties.getAbusePenaltySeconds().get(idx);
        return Math.max(1L, configured == null ? 1L : configured);
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
            log.warn("Redis AI rate-limit path failed, falling back to local memory (operation={})", operation);
        }
    }

    private void onRedisSuccess() {
        if (redisFailureLogged.compareAndSet(true, false)) {
            redisFallbackActive.set(0);
            if (meterRegistry != null) {
                meterRegistry.counter(METRIC_REDIS_FALLBACK_TRANSITION_TOTAL, "state", "recovered").increment();
            }
            log.info("Redis AI rate-limit path recovered");
        }
    }

    private PenaltyState readPenaltyState(String subject) {
        if (subject == null || subject.isBlank()) {
            return PenaltyState.inactive();
        }

        if (canUseRedis()) {
            try {
                Long ttl = stringRedisTemplate.getExpire(PENALTY_BAN_PREFIX + subject, TimeUnit.SECONDS);
                onRedisSuccess();
                if (ttl != null && ttl > 0) {
                    return PenaltyState.active(ttl);
                }
            } catch (Exception ex) {
                onRedisFailure("getAbusePenaltyStatus");
            }
        }

        return readPenaltyStateFromMemory(subject);
    }

    private PenaltyState readPenaltyStateFromMemory(String subject) {
        PenaltyCounter counter = penaltyCounters.get(subject);
        if (counter == null) {
            return PenaltyState.inactive();
        }

        long now = currentTimeMillis();
        synchronized (counter) {
            if (counter.blockedUntilMs <= now) {
                return PenaltyState.inactive();
            }
            long retry = Math.max(1L, (counter.blockedUntilMs - now + 999L) / 1000L);
            return PenaltyState.active(retry);
        }
    }

    private int countActivePenaltySubjectsSnapshot() {
        long now = currentTimeMillis();
        int active = 0;
        for (PenaltyCounter counter : penaltyCounters.values()) {
            synchronized (counter) {
                if (counter.blockedUntilMs > now) {
                    active++;
                }
            }
        }
        return active;
    }

    private void onPenaltyApplied(String backend,
                                  String penaltySubject,
                                  String reason,
                                  String scope,
                                  int level,
                                  long penaltySeconds) {
        if (meterRegistry != null) {
            meterRegistry.counter(
                    METRIC_PENALTY_APPLY_TOTAL,
                    "backend", normalizeMetricTag(backend),
                    "reason", normalizeMetricTag(reason),
                    "scope", normalizeMetricTag(scope),
                    "level", String.valueOf(Math.max(1, level)))
                    .increment();
        }
        log.warn("AI abuse penalty applied (backend={}, subject={}, reason={}, scope={}, level={}, durationSec={})",
                backend,
                redactPenaltySubject(penaltySubject),
                reason,
                scope,
                level,
                Math.max(1L, penaltySeconds));
    }

    private void onUnban(boolean cleared, String subjectType, String subject) {
        if (meterRegistry != null) {
            meterRegistry.counter(
                    METRIC_UNBAN_TOTAL,
                    "subjectType", normalizeMetricTag(subjectType),
                    "result", cleared ? "cleared" : "noop")
                    .increment();
        }
        log.info("AI abuse penalty clear requested (subjectType={}, subject={}, cleared={})",
                subjectType,
                redactPenaltySubject(subject),
                cleared);
    }

    private String normalizeMetricTag(String value) {
        if (value == null) {
            return "unknown";
        }
        String normalized = value.trim().toLowerCase();
        return normalized.isEmpty() ? "unknown" : normalized;
    }

    private String redactPenaltySubject(String subject) {
        if (subject == null || subject.isBlank()) {
            return "unknown";
        }
        if (subject.startsWith("u:")) {
            return subject;
        }
        if (subject.startsWith("ip:")) {
            String ip = subject.substring(3);
            int lastDot = ip.lastIndexOf('.');
            if (lastDot > 0) {
                return "ip:" + ip.substring(0, lastDot) + ".*";
            }
            return "ip:*";
        }
        return "unknown";
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

        cleanupWindowCounters(userCounters, nowMs);
        cleanupWindowCounters(ipCounters, nowMs);
        cleanupDailyCounters(dailyCounters, nowMs);
        cleanupPenaltyCounters(penaltyCounters, nowMs);

        int maxEntries = Math.max(1_000, properties.getMemoryMaxEntriesPerMap());
        trimToMaxSize(userCounters, maxEntries, "user-window");
        trimToMaxSize(ipCounters, maxEntries, "ip-window");
        trimToMaxSize(dailyCounters, maxEntries, "daily");
        trimToMaxSize(penaltyCounters, maxEntries, "penalty");
    }

    private void cleanupWindowCounters(Map<String, WindowCounter> counters, long nowMs) {
        for (String key : counters.keySet()) {
            WindowCounter counter = counters.get(key);
            if (counter == null) {
                continue;
            }

            boolean remove;
            synchronized (counter) {
                long effectiveWindowMs = Math.max(1_000L, counter.windowMs);
                long sinceWindowStart = nowMs - counter.windowStartMs;
                long sinceTouch = nowMs - counter.lastTouchedMs;
                remove = (counter.windowStartMs > 0 && sinceWindowStart > (effectiveWindowMs * 2))
                        || (counter.lastTouchedMs > 0 && sinceTouch > (effectiveWindowMs * 2));
            }

            if (remove) {
                counters.remove(key, counter);
            }
        }
    }

    private void cleanupDailyCounters(Map<String, DailyCounter> counters, long nowMs) {
        for (String key : counters.keySet()) {
            DailyCounter counter = counters.get(key);
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
                counters.remove(key, counter);
            }
        }
    }

    private void cleanupPenaltyCounters(Map<String, PenaltyCounter> counters, long nowMs) {
        for (String key : counters.keySet()) {
            PenaltyCounter counter = counters.get(key);
            if (counter == null) {
                continue;
            }

            boolean remove;
            synchronized (counter) {
                long expiry = Math.max(counter.blockedUntilMs, counter.strikeResetAtMs);
                if (expiry <= 0) {
                    expiry = counter.lastTouchedMs + TimeUnit.HOURS.toMillis(1);
                }
                remove = expiry > 0 && nowMs > expiry;
            }

            if (remove) {
                counters.remove(key, counter);
            }
        }
    }

    private void trimToMaxSize(Map<String, ?> map, int maxEntries, String mapName) {
        int currentSize = map.size();
        if (currentSize <= maxEntries) {
            return;
        }

        int targetRemovals = currentSize - maxEntries;
        int removed = 0;
        for (String key : map.keySet()) {
            if (removed >= targetRemovals) {
                break;
            }
            if (map.remove(key) != null) {
                removed++;
            }
        }

        if (removed > 0) {
            if (meterRegistry != null) {
                meterRegistry.counter(METRIC_MEMORY_TRIM_TOTAL, "map", mapName).increment(removed);
            }
            log.warn("AI rate-limit memory map trimmed (map={}, removed={}, maxEntries={})",
                    mapName,
                    removed,
                    maxEntries);
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
        private long windowMs = 1000L;
        private long lastTouchedMs;
        private int count;
    }

    private static final class DailyCounter {
        private long dayStartMs = -1;
        private long dayEndMs = -1;
        private long lastTouchedMs;
        private int count;
    }

    private static final class PenaltyCounter {
        private int strikes;
        private long strikeResetAtMs;
        private long blockedUntilMs;
        private long lastTouchedMs;
    }

    private static final class PenaltyState {
        private final boolean active;
        private final long retryAfterSeconds;

        private PenaltyState(boolean active, long retryAfterSeconds) {
            this.active = active;
            this.retryAfterSeconds = retryAfterSeconds;
        }

        private static PenaltyState inactive() {
            return new PenaltyState(false, 0L);
        }

        private static PenaltyState active(long retryAfterSeconds) {
            return new PenaltyState(true, Math.max(1L, retryAfterSeconds));
        }
    }
}
