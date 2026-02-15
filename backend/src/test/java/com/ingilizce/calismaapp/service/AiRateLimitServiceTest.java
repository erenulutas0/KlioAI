package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.config.AiRateLimitProperties;
import org.junit.jupiter.api.Test;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;

import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class AiRateLimitServiceTest {

    @Test
    void checkAndConsume_ShouldBlockWhenUserBurstExceeded() {
        AiRateLimitProperties properties = new AiRateLimitProperties();
        properties.setEnabled(true);
        properties.setRedisEnabled(false);
        properties.setUserWindowMaxRequests(1);
        properties.setIpWindowMaxRequests(100);
        properties.setWindowSeconds(60);
        properties.setDailyQuotaPerUser(100);

        TestableAiRateLimitService service = new TestableAiRateLimitService(properties);

        assertFalse(service.checkAndConsume(1L, "10.0.0.1", "chat").blocked());
        assertTrue(service.checkAndConsume(1L, "10.0.0.1", "chat").blocked());
    }

    @Test
    void checkAndConsume_ShouldBlockWhenDailyQuotaExceeded() {
        AiRateLimitProperties properties = new AiRateLimitProperties();
        properties.setEnabled(true);
        properties.setRedisEnabled(false);
        properties.setUserWindowMaxRequests(100);
        properties.setIpWindowMaxRequests(100);
        properties.setWindowSeconds(60);
        properties.setDailyQuotaPerUser(1);

        TestableAiRateLimitService service = new TestableAiRateLimitService(properties);

        assertFalse(service.checkAndConsume(2L, "10.0.0.2", "generate-sentences").blocked());
        assertTrue(service.checkAndConsume(2L, "10.0.0.2", "generate-sentences").blocked());
    }

    @Test
    void disabledMode_ShouldAlwaysAllow() {
        AiRateLimitProperties properties = new AiRateLimitProperties();
        properties.setEnabled(false);

        TestableAiRateLimitService service = new TestableAiRateLimitService(properties);
        assertFalse(service.checkAndConsume(3L, "10.0.0.3", "chat").blocked());
        assertFalse(service.checkAndConsume(3L, "10.0.0.3", "chat").blocked());
    }

    @Test
    void checkAndConsume_ShouldBlockWhenRedisFailsInDenyMode() {
        AiRateLimitProperties properties = new AiRateLimitProperties();
        properties.setEnabled(true);
        properties.setRedisEnabled(true);
        properties.setRedisFallbackMode("deny");
        properties.setRedisFailureBlockSeconds(77);

        StringRedisTemplate redisTemplate = mock(StringRedisTemplate.class);
        when(redisTemplate.opsForValue()).thenThrow(new RuntimeException("redis-down"));

        AiRateLimitService service = new AiRateLimitService(properties, redisTemplate, null);
        AiRateLimitService.Decision decision = service.checkAndConsume(4L, "10.0.0.4", "chat");

        assertTrue(decision.blocked());
        assertEquals("redis-fail-closed", decision.reason());
        assertEquals(77, decision.retryAfterSeconds());
    }

    @Test
    void checkAndConsume_ShouldFallbackToMemoryWhenRedisFailsInMemoryMode() {
        AiRateLimitProperties properties = new AiRateLimitProperties();
        properties.setEnabled(true);
        properties.setRedisEnabled(true);
        properties.setRedisFallbackMode("memory");
        properties.setUserWindowMaxRequests(1);
        properties.setIpWindowMaxRequests(100);
        properties.setDailyQuotaPerUser(100);

        StringRedisTemplate redisTemplate = mock(StringRedisTemplate.class);
        when(redisTemplate.opsForValue()).thenThrow(new RuntimeException("redis-down"));

        AiRateLimitService service = new AiRateLimitService(properties, redisTemplate, null);
        assertFalse(service.checkAndConsume(5L, "10.0.0.5", "chat").blocked());

        AiRateLimitService.Decision second = service.checkAndConsume(5L, "10.0.0.5", "chat");
        assertTrue(second.blocked());
        assertEquals("user-burst", second.reason());
    }

    @SuppressWarnings("unchecked")
    @Test
    void checkAndConsume_ShouldUseRedisWindowAndReturnRetryAfter() {
        AiRateLimitProperties properties = new AiRateLimitProperties();
        properties.setEnabled(true);
        properties.setRedisEnabled(true);
        properties.setUserWindowMaxRequests(1);
        properties.setIpWindowMaxRequests(50);
        properties.setDailyQuotaPerUser(100);

        StringRedisTemplate redisTemplate = mock(StringRedisTemplate.class);
        ValueOperations<String, String> valueOperations = mock(ValueOperations.class);
        when(redisTemplate.opsForValue()).thenReturn(valueOperations);
        when(valueOperations.increment(anyString())).thenReturn(2L);
        when(redisTemplate.getExpire(anyString(), eq(TimeUnit.SECONDS))).thenReturn(15L);

        AiRateLimitService service = new AiRateLimitService(properties, redisTemplate, null);
        AiRateLimitService.Decision decision = service.checkAndConsume(6L, "10.0.0.6", "chat");

        assertTrue(decision.blocked());
        assertEquals("user-burst", decision.reason());
        assertEquals(15, decision.retryAfterSeconds());
    }

    @Test
    void scopeQuota_ShouldBlockWhenScopeDailyQuotaExceeded() {
        AiRateLimitProperties properties = new AiRateLimitProperties();
        properties.setEnabled(true);
        properties.setRedisEnabled(false);
        properties.setUserWindowMaxRequests(100);
        properties.setIpWindowMaxRequests(100);
        properties.setWindowSeconds(60);
        properties.setDailyQuotaPerUser(1000); // global is high

        AiRateLimitProperties.ScopeLimits chatScope = new AiRateLimitProperties.ScopeLimits();
        chatScope.setDailyQuotaPerUser(1);
        properties.getScopes().put("chat", chatScope);

        TestableAiRateLimitService service = new TestableAiRateLimitService(properties);

        assertFalse(service.checkAndConsume(7L, "10.0.0.7", "chat").blocked());
        assertTrue(service.checkAndConsume(7L, "10.0.0.7", "chat").blocked());
        // Other scopes should still be allowed (scope quota is specific).
        assertFalse(service.checkAndConsume(7L, "10.0.0.7", "speaking-evaluate").blocked());
    }

    private static final class TestableAiRateLimitService extends AiRateLimitService {
        private long nowMs = 1_000_000L;

        private TestableAiRateLimitService(AiRateLimitProperties properties) {
            super(properties);
        }

        @Override
        protected long currentTimeMillis() {
            return nowMs;
        }
    }
}
