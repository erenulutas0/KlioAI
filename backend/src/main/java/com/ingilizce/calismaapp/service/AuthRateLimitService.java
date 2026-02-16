package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.config.AuthRateLimitProperties;
import io.micrometer.core.instrument.MeterRegistry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.util.ArrayDeque;
import java.util.Arrays;
import java.util.Deque;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

@Service
public class AuthRateLimitService {
    private static final Logger log = LoggerFactory.getLogger(AuthRateLimitService.class);
    private static final String COUNTER_PREFIX = "auth:rl:cnt:";
    private static final String BLOCK_PREFIX = "auth:rl:block:";
    private static final String REDIS_FAILURE_TOTAL_METRIC = "auth.rate.limit.redis.failure.total";
    private static final String REDIS_FALLBACK_TRANSITION_TOTAL_METRIC = "auth.rate.limit.redis.fallback.transition.total";
    private static final String REDIS_FALLBACK_ACTIVE_METRIC = "auth.rate.limit.redis.fallback.active";
    private static final String REDIS_FAIL_CLOSED_BLOCK_TOTAL_METRIC = "auth.rate.limit.redis.fail.closed.block.total";

    public record RateLimitDecision(boolean blocked, long retryAfterSeconds) {
        public static RateLimitDecision allowed() {
            return new RateLimitDecision(false, 0);
        }

        public static RateLimitDecision blocked(long retryAfterSeconds) {
            return new RateLimitDecision(true, Math.max(1, retryAfterSeconds));
        }
    }

    private static class AttemptState {
        private final Deque<Long> failures = new ArrayDeque<>();
        private long blockedUntilEpochMs = 0;
    }

    private final AuthRateLimitProperties properties;
    private final StringRedisTemplate stringRedisTemplate;
    private final MeterRegistry meterRegistry;
    private final AtomicBoolean redisFailureLogged = new AtomicBoolean(false);
    private final AtomicInteger redisFallbackActive = new AtomicInteger(0);

    private final ConcurrentHashMap<String, AttemptState> loginPrincipalAttempts = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<String, AttemptState> loginIpAttempts = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<String, AttemptState> registerIpAttempts = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<String, AttemptState> passwordResetIpAttempts = new ConcurrentHashMap<>();

    @Autowired
    public AuthRateLimitService(AuthRateLimitProperties properties,
                                @Qualifier("securityStringRedisTemplate")
                                @Autowired(required = false) StringRedisTemplate stringRedisTemplate,
                                @Autowired(required = false) MeterRegistry meterRegistry) {
        this.properties = properties;
        this.stringRedisTemplate = stringRedisTemplate;
        this.meterRegistry = meterRegistry;
        if (meterRegistry != null) {
            meterRegistry.gauge(REDIS_FALLBACK_ACTIVE_METRIC, redisFallbackActive);
        }
    }

    AuthRateLimitService(AuthRateLimitProperties properties) {
        this(properties, null, null);
    }

    AuthRateLimitService(AuthRateLimitProperties properties, StringRedisTemplate stringRedisTemplate) {
        this(properties, stringRedisTemplate, null);
    }

    public RateLimitDecision checkLogin(String emailOrTag, String clientIp) {
        if (!properties.isEnabled()) {
            return RateLimitDecision.allowed();
        }

        String principalKey = "login:principal:" + normalizeValue(emailOrTag);
        String ipKey = "login:ip:" + normalizeValue(clientIp);

        if (canUseRedis()) {
            try {
                RateLimitDecision principalRedisDecision = checkRedisLimit(principalKey);
                if (principalRedisDecision.blocked()) {
                    return principalRedisDecision;
                }

                return checkRedisLimit(ipKey);
            } catch (Exception ex) {
                onRedisFailure("checkLogin", ex);
                if (isFailClosedMode()) {
                    return denyByRedisFailure("checkLogin");
                }
            }
        }

        RateLimitDecision principalDecision = check(principalKey, loginPrincipalAttempts,
                properties.getLoginPrincipalWindowSeconds(), properties.getLoginPrincipalBlockSeconds());
        if (principalDecision.blocked()) {
            return principalDecision;
        }

        return check(ipKey, loginIpAttempts,
                properties.getLoginIpWindowSeconds(), properties.getLoginIpBlockSeconds());
    }

    public void recordLoginFailure(String emailOrTag, String clientIp) {
        if (!properties.isEnabled()) {
            return;
        }

        if (canUseRedis()) {
            try {
                recordRedisFailure("login:principal:" + normalizeValue(emailOrTag),
                        properties.getLoginPrincipalWindowSeconds(),
                        properties.getLoginPrincipalBlockSeconds(),
                        properties.getLoginPrincipalMaxAttempts());

                recordRedisFailure("login:ip:" + normalizeValue(clientIp),
                        properties.getLoginIpWindowSeconds(),
                        properties.getLoginIpBlockSeconds(),
                        properties.getLoginIpMaxAttempts());
                return;
            } catch (Exception ex) {
                onRedisFailure("recordLoginFailure", ex);
            }
        }

        recordFailure("login:principal:" + normalizeValue(emailOrTag), loginPrincipalAttempts,
                properties.getLoginPrincipalWindowSeconds(), properties.getLoginPrincipalBlockSeconds(),
                properties.getLoginPrincipalMaxAttempts());

        recordFailure("login:ip:" + normalizeValue(clientIp), loginIpAttempts,
                properties.getLoginIpWindowSeconds(), properties.getLoginIpBlockSeconds(),
                properties.getLoginIpMaxAttempts());
    }

    public void resetLogin(String emailOrTag, String clientIp) {
        if (!properties.isEnabled()) {
            return;
        }

        if (canUseRedis()) {
            try {
                resetRedisKey("login:principal:" + normalizeValue(emailOrTag));
                resetRedisKey("login:ip:" + normalizeValue(clientIp));
                return;
            } catch (Exception ex) {
                onRedisFailure("resetLogin", ex);
            }
        }

        loginPrincipalAttempts.remove("login:principal:" + normalizeValue(emailOrTag));
        loginIpAttempts.remove("login:ip:" + normalizeValue(clientIp));
    }

    public RateLimitDecision checkRegister(String clientIp) {
        if (!properties.isEnabled()) {
            return RateLimitDecision.allowed();
        }

        if (canUseRedis()) {
            try {
                return checkRedisLimit("register:ip:" + normalizeValue(clientIp));
            } catch (Exception ex) {
                onRedisFailure("checkRegister", ex);
                if (isFailClosedMode()) {
                    return denyByRedisFailure("checkRegister");
                }
            }
        }

        return check("register:ip:" + normalizeValue(clientIp), registerIpAttempts,
                properties.getRegisterIpWindowSeconds(), properties.getRegisterIpBlockSeconds());
    }

    public void recordRegisterFailure(String clientIp) {
        if (!properties.isEnabled()) {
            return;
        }

        if (canUseRedis()) {
            try {
                recordRedisFailure("register:ip:" + normalizeValue(clientIp),
                        properties.getRegisterIpWindowSeconds(),
                        properties.getRegisterIpBlockSeconds(),
                        properties.getRegisterIpMaxAttempts());
                return;
            } catch (Exception ex) {
                onRedisFailure("recordRegisterFailure", ex);
            }
        }

        recordFailure("register:ip:" + normalizeValue(clientIp), registerIpAttempts,
                properties.getRegisterIpWindowSeconds(), properties.getRegisterIpBlockSeconds(),
                properties.getRegisterIpMaxAttempts());
    }

    public void resetRegister(String clientIp) {
        if (!properties.isEnabled()) {
            return;
        }

        if (canUseRedis()) {
            try {
                resetRedisKey("register:ip:" + normalizeValue(clientIp));
                return;
            } catch (Exception ex) {
                onRedisFailure("resetRegister", ex);
            }
        }

        registerIpAttempts.remove("register:ip:" + normalizeValue(clientIp));
    }

    public RateLimitDecision checkPasswordResetRequest(String clientIp) {
        if (!properties.isEnabled()) {
            return RateLimitDecision.allowed();
        }

        if (canUseRedis()) {
            try {
                return checkRedisLimit("password-reset:ip:" + normalizeValue(clientIp));
            } catch (Exception ex) {
                onRedisFailure("checkPasswordResetRequest", ex);
                if (isFailClosedMode()) {
                    return denyByRedisFailure("checkPasswordResetRequest");
                }
            }
        }

        return check("password-reset:ip:" + normalizeValue(clientIp), passwordResetIpAttempts,
                properties.getPasswordResetIpWindowSeconds(), properties.getPasswordResetIpBlockSeconds());
    }

    public void recordPasswordResetRequest(String clientIp) {
        if (!properties.isEnabled()) {
            return;
        }

        if (canUseRedis()) {
            try {
                recordRedisFailure("password-reset:ip:" + normalizeValue(clientIp),
                        properties.getPasswordResetIpWindowSeconds(),
                        properties.getPasswordResetIpBlockSeconds(),
                        properties.getPasswordResetIpMaxAttempts());
                return;
            } catch (Exception ex) {
                onRedisFailure("recordPasswordResetRequest", ex);
            }
        }

        recordFailure("password-reset:ip:" + normalizeValue(clientIp), passwordResetIpAttempts,
                properties.getPasswordResetIpWindowSeconds(), properties.getPasswordResetIpBlockSeconds(),
                properties.getPasswordResetIpMaxAttempts());
    }

    protected long currentTimeMillis() {
        return System.currentTimeMillis();
    }

    private RateLimitDecision check(String key, Map<String, AttemptState> attemptMap,
                                    long windowSeconds, long blockSeconds) {
        AttemptState state = attemptMap.computeIfAbsent(key, k -> new AttemptState());
        long now = currentTimeMillis();

        synchronized (state) {
            pruneOldFailures(state, now, windowSeconds);
            if (state.blockedUntilEpochMs > now) {
                long retryAfterSeconds = (state.blockedUntilEpochMs - now + 999) / 1000;
                return RateLimitDecision.blocked(retryAfterSeconds);
            }

            if (state.failures.isEmpty() && state.blockedUntilEpochMs <= now) {
                attemptMap.remove(key, state);
            }
            return RateLimitDecision.allowed();
        }
    }

    private void recordFailure(String key, Map<String, AttemptState> attemptMap, long windowSeconds,
                               long blockSeconds, int maxAttempts) {
        AttemptState state = attemptMap.computeIfAbsent(key, k -> new AttemptState());
        long now = currentTimeMillis();

        synchronized (state) {
            if (state.blockedUntilEpochMs > now) {
                return;
            }

            pruneOldFailures(state, now, windowSeconds);
            state.failures.addLast(now);

            if (state.failures.size() >= maxAttempts) {
                state.blockedUntilEpochMs = now + (blockSeconds * 1000);
                state.failures.clear();
            }
        }
    }

    private void pruneOldFailures(AttemptState state, long now, long windowSeconds) {
        long threshold = now - (windowSeconds * 1000);
        while (!state.failures.isEmpty() && state.failures.peekFirst() < threshold) {
            state.failures.removeFirst();
        }
    }

    private boolean canUseRedis() {
        return properties.isRedisEnabled() && stringRedisTemplate != null;
    }

    private RateLimitDecision checkRedisLimit(String key) {
        String blockKey = buildBlockKey(key);
        Boolean blocked = stringRedisTemplate.hasKey(blockKey);
        if (Boolean.TRUE.equals(blocked)) {
            Long ttl = stringRedisTemplate.getExpire(blockKey, TimeUnit.SECONDS);
            long retryAfter = (ttl == null || ttl < 1) ? 1 : ttl;
            onRedisSuccess();
            return RateLimitDecision.blocked(retryAfter);
        }
        onRedisSuccess();
        return RateLimitDecision.allowed();
    }

    private void recordRedisFailure(String key, long windowSeconds, long blockSeconds, int maxAttempts) {
        String blockKey = buildBlockKey(key);
        if (Boolean.TRUE.equals(stringRedisTemplate.hasKey(blockKey))) {
            onRedisSuccess();
            return;
        }

        ValueOperations<String, String> valueOps = stringRedisTemplate.opsForValue();
        String counterKey = buildCounterKey(key);

        Long count = valueOps.increment(counterKey);
        if (count == null) {
            return;
        }

        if (count == 1L) {
            stringRedisTemplate.expire(counterKey, Duration.ofSeconds(Math.max(1, windowSeconds)));
        }

        if (count >= maxAttempts) {
            valueOps.set(blockKey, "1", Duration.ofSeconds(Math.max(1, blockSeconds)));
            stringRedisTemplate.delete(counterKey);
        }
        onRedisSuccess();
    }

    private void resetRedisKey(String key) {
        stringRedisTemplate.delete(Arrays.asList(buildCounterKey(key), buildBlockKey(key)));
        onRedisSuccess();
    }

    private String buildCounterKey(String key) {
        return COUNTER_PREFIX + key;
    }

    private String buildBlockKey(String key) {
        return BLOCK_PREFIX + key;
    }

    private void onRedisFailure(String operation, Exception ex) {
        incrementRedisFailureMetric(operation);
        if (redisFailureLogged.compareAndSet(false, true)) {
            redisFallbackActive.set(1);
            incrementRedisFallbackTransitionMetric("activated");
            log.warn("Redis rate-limit path failed, falling back to local memory (operation={})", operation, ex);
        }
    }

    private void onRedisSuccess() {
        if (redisFailureLogged.compareAndSet(true, false)) {
            redisFallbackActive.set(0);
            incrementRedisFallbackTransitionMetric("recovered");
            log.info("Redis rate-limit path recovered");
        }
    }

    private void incrementRedisFailureMetric(String operation) {
        if (meterRegistry == null) {
            return;
        }
        meterRegistry.counter(REDIS_FAILURE_TOTAL_METRIC, "operation", operation).increment();
    }

    private void incrementRedisFallbackTransitionMetric(String state) {
        if (meterRegistry == null) {
            return;
        }
        meterRegistry.counter(REDIS_FALLBACK_TRANSITION_TOTAL_METRIC, "state", state).increment();
    }

    private boolean isFailClosedMode() {
        String mode = properties.getRedisFallbackMode();
        return mode != null && "deny".equalsIgnoreCase(mode.trim());
    }

    private RateLimitDecision denyByRedisFailure(String operation) {
        if (meterRegistry != null) {
            meterRegistry.counter(REDIS_FAIL_CLOSED_BLOCK_TOTAL_METRIC, "operation", operation).increment();
        }
        return RateLimitDecision.blocked(Math.max(1, properties.getRedisFailureBlockSeconds()));
    }

    private String normalizeValue(String value) {
        if (value == null) {
            return "unknown";
        }
        String normalized = value.trim().toLowerCase();
        return normalized.isEmpty() ? "unknown" : normalized;
    }
}
