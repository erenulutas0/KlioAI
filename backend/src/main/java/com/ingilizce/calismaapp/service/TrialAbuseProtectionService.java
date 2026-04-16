package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.config.TrialAbuseProtectionProperties;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicBoolean;

@Service
public class TrialAbuseProtectionService {

    private static final Logger log = LoggerFactory.getLogger(TrialAbuseProtectionService.class);
    private static final String DEVICE_PREFIX = "auth:trial:device:";
    private static final String IP_PREFIX = "auth:trial:ip:";

    public record TrialDecision(boolean trialEligible, String reason) {
        public static TrialDecision allowed() {
            return new TrialDecision(true, "allowed");
        }

        public static TrialDecision blocked(String reason) {
            return new TrialDecision(false, reason);
        }
    }

    private static class AttemptState {
        private final Deque<Long> events = new ArrayDeque<>();
    }

    private final TrialAbuseProtectionProperties properties;
    private final StringRedisTemplate stringRedisTemplate;
    private final AtomicBoolean redisFailureLogged = new AtomicBoolean(false);
    private final ConcurrentHashMap<String, AttemptState> deviceAttempts = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<String, AttemptState> ipAttempts = new ConcurrentHashMap<>();

    @Autowired
    public TrialAbuseProtectionService(TrialAbuseProtectionProperties properties,
                                       @Qualifier("securityStringRedisTemplate")
                                       @Autowired(required = false) StringRedisTemplate stringRedisTemplate) {
        this.properties = properties;
        this.stringRedisTemplate = stringRedisTemplate;
    }

    TrialAbuseProtectionService(TrialAbuseProtectionProperties properties) {
        this(properties, null);
    }

    public TrialDecision evaluate(String deviceId, String clientIp) {
        if (!properties.isEnabled()) {
            return TrialDecision.allowed();
        }

        String normalizedDeviceId = normalizeDeviceId(deviceId);
        if (normalizedDeviceId != null) {
            long deviceCount = getCount(DEVICE_PREFIX + normalizedDeviceId, deviceAttempts);
            if (deviceCount >= properties.getMaxTrialAccountsPerDevice()) {
                return TrialDecision.blocked("device-limit");
            }
        }

        String normalizedIp = normalizeIp(clientIp);
        if (normalizedIp != null) {
            long ipCount = getCount(IP_PREFIX + normalizedIp, ipAttempts);
            if (ipCount >= properties.getMaxTrialAccountsPerIp()) {
                return TrialDecision.blocked("ip-limit");
            }
        }

        return TrialDecision.allowed();
    }

    public void recordTrialGrant(String deviceId, String clientIp) {
        if (!properties.isEnabled()) {
            return;
        }

        String normalizedDeviceId = normalizeDeviceId(deviceId);
        if (normalizedDeviceId != null) {
            increment(DEVICE_PREFIX + normalizedDeviceId, deviceAttempts);
        }

        String normalizedIp = normalizeIp(clientIp);
        if (normalizedIp != null) {
            increment(IP_PREFIX + normalizedIp, ipAttempts);
        }
    }

    private long getCount(String key, Map<String, AttemptState> localAttempts) {
        if (canUseRedis()) {
            try {
                String value = stringRedisTemplate.opsForValue().get(key);
                onRedisSuccess();
                return parseLong(value);
            } catch (Exception ex) {
                onRedisFailure("getCount", ex);
                if (isFailClosedMode()) {
                    return Long.MAX_VALUE;
                }
            }
        }

        AttemptState state = localAttempts.get(key);
        if (state == null) {
            return 0L;
        }

        synchronized (state) {
            prune(state, currentTimeMillis());
            if (state.events.isEmpty()) {
                localAttempts.remove(key, state);
                return 0L;
            }
            return state.events.size();
        }
    }

    private void increment(String key, Map<String, AttemptState> localAttempts) {
        if (canUseRedis()) {
            try {
                Long count = stringRedisTemplate.opsForValue().increment(key);
                if (count != null && count == 1L) {
                    stringRedisTemplate.expire(key, Duration.ofHours(properties.getWindowHours()));
                }
                onRedisSuccess();
                return;
            } catch (Exception ex) {
                onRedisFailure("increment", ex);
                if (isFailClosedMode()) {
                    return;
                }
            }
        }

        AttemptState state = localAttempts.computeIfAbsent(key, unused -> new AttemptState());
        synchronized (state) {
            long now = currentTimeMillis();
            prune(state, now);
            state.events.addLast(now);
        }
    }

    protected long currentTimeMillis() {
        return System.currentTimeMillis();
    }

    private void prune(AttemptState state, long nowMs) {
        long threshold = nowMs - Duration.ofHours(properties.getWindowHours()).toMillis();
        while (!state.events.isEmpty() && state.events.peekFirst() < threshold) {
            state.events.removeFirst();
        }
    }

    private boolean canUseRedis() {
        return properties.isRedisEnabled() && stringRedisTemplate != null;
    }

    private boolean isFailClosedMode() {
        String mode = properties.getRedisFallbackMode();
        return mode != null && "deny".equalsIgnoreCase(mode.trim());
    }

    private long parseLong(String value) {
        if (value == null || value.isBlank()) {
            return 0L;
        }
        try {
            return Long.parseLong(value.trim());
        } catch (NumberFormatException ex) {
            return 0L;
        }
    }

    private String normalizeDeviceId(String deviceId) {
        if (deviceId == null) {
            return null;
        }
        String normalized = deviceId.trim().toLowerCase();
        if (normalized.isEmpty() || "unknown-device".equals(normalized)) {
            return null;
        }
        return normalized;
    }

    private String normalizeIp(String clientIp) {
        if (clientIp == null) {
            return null;
        }
        String normalized = clientIp.trim().toLowerCase();
        return normalized.isEmpty() || "unknown".equals(normalized) ? null : normalized;
    }

    private void onRedisFailure(String operation, Exception ex) {
        if (redisFailureLogged.compareAndSet(false, true)) {
            log.warn("Trial abuse Redis path failed, falling back to local memory (operation={})", operation, ex);
        }
    }

    private void onRedisSuccess() {
        if (redisFailureLogged.compareAndSet(true, false)) {
            log.info("Trial abuse Redis path recovered");
        }
    }
}
