package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.config.AiTokenQuotaProperties;
import org.junit.jupiter.api.Test;
import org.springframework.data.redis.core.StringRedisTemplate;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class AiTokenQuotaServiceTest {

    @Test
    void disabledMode_ShouldAlwaysAllow() {
        AiTokenQuotaProperties properties = new AiTokenQuotaProperties();
        properties.setEnabled(false);

        AiTokenQuotaService service = new AiTokenQuotaService(properties);
        assertFalse(service.check(1L, "chat").blocked());
        assertFalse(service.check(1L, "chat").blocked());
    }

    @Test
    void globalBudget_ShouldBlockWhenExceeded() {
        AiTokenQuotaProperties properties = new AiTokenQuotaProperties();
        properties.setEnabled(true);
        properties.setRedisEnabled(false);
        properties.setDailyTokenQuotaPerUser(10);

        TestableAiTokenQuotaService service = new TestableAiTokenQuotaService(properties);

        assertFalse(service.check(1L, "chat").blocked());
        service.consume(1L, "chat", 6);
        assertFalse(service.check(1L, "chat").blocked());
        service.consume(1L, "chat", 5);
        AiTokenQuotaService.Decision decision = service.check(1L, "chat");
        assertTrue(decision.blocked());
        assertEquals("daily-token-quota", decision.reason());
        assertEquals(10, decision.tokenLimit());
        assertEquals(11, decision.tokensUsed());
    }

    @Test
    void scopeBudget_ShouldBlockWhenExceeded_EvenIfGlobalDisabled() {
        AiTokenQuotaProperties properties = new AiTokenQuotaProperties();
        properties.setEnabled(true);
        properties.setRedisEnabled(false);
        properties.setDailyTokenQuotaPerUser(0);

        AiTokenQuotaProperties.ScopeLimits chatLimits = new AiTokenQuotaProperties.ScopeLimits();
        chatLimits.setDailyTokenQuotaPerUser(5L);
        properties.getScopes().put("chat", chatLimits);

        TestableAiTokenQuotaService service = new TestableAiTokenQuotaService(properties);

        service.consume(2L, "chat", 5);
        AiTokenQuotaService.Decision blocked = service.check(2L, "chat");
        assertTrue(blocked.blocked());
        assertEquals("daily-token-quota", blocked.reason());
        assertEquals(5, blocked.tokenLimit());
        assertEquals(5, blocked.tokensUsed());
    }

    @Test
    void check_ShouldBlockWhenRedisFailsInDenyMode() {
        AiTokenQuotaProperties properties = new AiTokenQuotaProperties();
        properties.setEnabled(true);
        properties.setRedisEnabled(true);
        properties.setRedisFallbackMode("deny");
        properties.setRedisFailureBlockSeconds(77);
        properties.setDailyTokenQuotaPerUser(1);

        StringRedisTemplate redisTemplate = mock(StringRedisTemplate.class);
        when(redisTemplate.opsForValue()).thenThrow(new RuntimeException("redis-down"));

        AiTokenQuotaService service = new AiTokenQuotaService(properties, redisTemplate, null);
        AiTokenQuotaService.Decision decision = service.check(4L, "chat");

        assertTrue(decision.blocked());
        assertEquals("redis-fail-closed", decision.reason());
        assertEquals(77, decision.retryAfterSeconds());
    }

    @Test
    void globalUsage_ShouldReturnUsedAndRemainingInMemoryMode() {
        AiTokenQuotaProperties properties = new AiTokenQuotaProperties();
        properties.setEnabled(true);
        properties.setRedisEnabled(false);
        properties.setDailyTokenQuotaPerUser(50_000);

        TestableAiTokenQuotaService service = new TestableAiTokenQuotaService(properties);
        service.consume(7L, "chat", 12_345);

        AiTokenQuotaService.Usage usage = service.getGlobalUsage(7L);
        assertEquals(50_000, usage.tokenLimit());
        assertEquals(12_345, usage.tokensUsed());
        assertEquals(37_655, usage.tokensRemaining());
    }

    @Test
    void usageStats_ShouldExposeMemoryTotalsAndEstimatedCost() {
        AiTokenQuotaProperties properties = new AiTokenQuotaProperties();
        properties.setEnabled(true);
        properties.setRedisEnabled(false);
        properties.setDailyTokenQuotaPerUser(50_000);
        properties.setEstimatedCostUsdPerMillionTokens(0.20);

        AiTokenQuotaProperties.ScopeLimits chatLimits = new AiTokenQuotaProperties.ScopeLimits();
        chatLimits.setDailyTokenQuotaPerUser(20_000L);
        properties.getScopes().put("chat", chatLimits);

        TestableAiTokenQuotaService service = new TestableAiTokenQuotaService(properties);
        service.consume(7L, "chat", 12_500);

        AiTokenQuotaService.UsageStats stats = service.getUsageStats();

        assertTrue(stats.enabled());
        assertFalse(stats.redisEnabled());
        assertEquals(1, stats.memoryGlobalSubjects());
        assertEquals(1, stats.memoryScopeSubjects());
        assertEquals(12_500, stats.memoryTokensUsed());
        assertEquals(12_500, stats.totalTokensUsed());
        assertEquals(0.0025, stats.estimatedCostUsd());
    }

    private static final class TestableAiTokenQuotaService extends AiTokenQuotaService {
        private long nowMs = 1_000_000L;

        private TestableAiTokenQuotaService(AiTokenQuotaProperties properties) {
            super(properties);
        }

        @Override
        protected long currentTimeMillis() {
            return nowMs;
        }
    }
}
