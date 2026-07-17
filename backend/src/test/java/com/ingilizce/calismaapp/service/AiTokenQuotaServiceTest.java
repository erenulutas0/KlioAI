package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.config.AiTokenQuotaProperties;
import org.junit.jupiter.api.Test;
import org.springframework.data.redis.core.StringRedisTemplate;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyLong;
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

        AiTokenQuotaService.UsageStats stats = service.getUsageStats();
        assertEquals(1, stats.quotaBlocks().size());
        assertEquals("daily-token-quota", stats.quotaBlocks().get(0).reason());
        assertEquals("chat", stats.quotaBlocks().get(0).scope());
        assertEquals(1, stats.quotaBlocks().get(0).count());
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
    void entitlementDisabled_ShouldBlockCheckAndSkipConsume() {
        AiTokenQuotaProperties properties = new AiTokenQuotaProperties();
        properties.setEnabled(true);
        properties.setRedisEnabled(false);

        AiEntitlementService entitlementService = mock(AiEntitlementService.class);
        when(entitlementService.resolve(12L)).thenReturn(new AiEntitlementService.Entitlement(
                AiPlanTier.FREE,
                "FREE",
                false,
                1500,
                false,
                0));

        TestableAiTokenQuotaService service = new TestableAiTokenQuotaService(properties, entitlementService);

        AiTokenQuotaService.Decision decision = service.check(12L, "chat");
        AiTokenQuotaService.Usage usage = service.consume(12L, "chat", 100);

        assertTrue(decision.blocked());
        assertEquals("ai-access-disabled", decision.reason());
        assertEquals(1500, decision.tokenLimit());
        assertEquals(0, usage.tokensUsed());
        assertEquals(0, usage.tokensRemaining());
        assertEquals(1500, usage.tokenLimit());
    }

    @Test
    void consumeZeroTokens_ShouldNotIncrementExistingCounters() {
        AiTokenQuotaProperties properties = new AiTokenQuotaProperties();
        properties.setEnabled(true);
        properties.setRedisEnabled(false);
        properties.setDailyTokenQuotaPerUser(50_000);

        AiTokenQuotaProperties.ScopeLimits chatLimits = new AiTokenQuotaProperties.ScopeLimits();
        chatLimits.setDailyTokenQuotaPerUser(100L);
        properties.getScopes().put("chat", chatLimits);

        TestableAiTokenQuotaService service = new TestableAiTokenQuotaService(properties);
        service.consume(7L, "CHAT", 25);

        AiTokenQuotaService.Usage usage = service.consume(7L, " chat ", 0);

        assertEquals(0, usage.tokensUsed());
        assertEquals(0, usage.tokensRemaining());
        assertEquals(0, usage.tokenLimit());
        assertEquals(25, service.getGlobalUsage(7L).tokensUsed());
    }

    @Test
    void anonymousUnknownScope_ShouldBeNormalizedInUsageStats() {
        AiTokenQuotaProperties properties = new AiTokenQuotaProperties();
        properties.setEnabled(true);
        properties.setRedisEnabled(false);
        properties.setDailyTokenQuotaPerUser(1000);

        TestableAiTokenQuotaService service = new TestableAiTokenQuotaService(properties);
        service.consume(null, "  ", 33);

        AiTokenQuotaService.UsageStats stats = service.getUsageStats();

        assertEquals("anonymous", stats.topUsers().get(0).subject());
        assertEquals(33, stats.topUsers().get(0).tokensUsed());
        assertTrue(stats.topScopes().isEmpty());
    }

    @Test
    void memoryCounters_ShouldRollAtUtcDayBoundary() {
        AiTokenQuotaProperties properties = new AiTokenQuotaProperties();
        properties.setEnabled(true);
        properties.setRedisEnabled(false);
        properties.setDailyTokenQuotaPerUser(100);

        TestableAiTokenQuotaService service = new TestableAiTokenQuotaService(properties);
        service.setNowMs(1_000L);
        service.consume(4L, "chat", 90);
        assertEquals(90, service.getGlobalUsage(4L).tokensUsed());

        service.setNowMs(86_400_000L + 1_000L);

        AiTokenQuotaService.Usage usage = service.getGlobalUsage(4L);
        assertEquals(0, usage.tokensUsed());
        assertEquals(100, usage.tokensRemaining());
    }

    @Test
    void redisFailureInAllowMode_ShouldFallBackToMemoryAndExposeFallbackStats() {
        AiTokenQuotaProperties properties = new AiTokenQuotaProperties();
        properties.setEnabled(true);
        properties.setRedisEnabled(true);
        properties.setRedisFallbackMode("allow");
        properties.setDailyTokenQuotaPerUser(100);

        StringRedisTemplate redisTemplate = mock(StringRedisTemplate.class);
        when(redisTemplate.opsForValue()).thenThrow(new RuntimeException("redis-down"));

        AiTokenQuotaService service = new AiTokenQuotaService(properties, redisTemplate, null);
        AiTokenQuotaService.Decision decision = service.check(4L, "chat");

        assertFalse(decision.blocked());
        assertTrue(service.getUsageStats().redisFallbackActive());
    }

    @Test
    void nonPaidAggregateDeviceBudget_ShouldBlockAcrossFreeTrialAccounts() {
        AiTokenQuotaProperties properties = new AiTokenQuotaProperties();
        properties.setEnabled(true);
        properties.setRedisEnabled(false);
        properties.setNonPaidAggregateDailyTokenQuotaPerDevice(10_000);
        properties.setNonPaidAggregateDailyTokenQuotaPerIp(0);

        AiEntitlementService entitlementService = mock(AiEntitlementService.class);
        when(entitlementService.resolve(anyLong())).thenReturn(freeTrialEntitlement(50_000));

        TestableAiTokenQuotaService service = new TestableAiTokenQuotaService(properties, entitlementService);
        service.consume(1L, "chat", 4_000, "device-a", "10.0.0.1");
        service.consume(2L, "chat", 6_000, "device-a", "10.0.0.2");

        AiTokenQuotaService.Decision decision = service.check(3L, "chat", "device-a", "10.0.0.3");

        assertTrue(decision.blocked());
        assertEquals("non-paid-device-token-quota", decision.reason());
        assertEquals(10_000, decision.tokenLimit());
        assertEquals(10_000, decision.tokensUsed());
    }

    @Test
    void nonPaidAggregateIpBudget_ShouldBlockFifthFreeTrialAccountOnSharedIp() {
        AiTokenQuotaProperties properties = new AiTokenQuotaProperties();
        properties.setEnabled(true);
        properties.setRedisEnabled(false);
        properties.setNonPaidAggregateDailyTokenQuotaPerDevice(0);
        properties.setNonPaidAggregateDailyTokenQuotaPerIp(20_000);

        AiEntitlementService entitlementService = mock(AiEntitlementService.class);
        when(entitlementService.resolve(anyLong())).thenReturn(freeTrialEntitlement(50_000));

        TestableAiTokenQuotaService service = new TestableAiTokenQuotaService(properties, entitlementService);
        for (long userId = 1; userId <= 4; userId++) {
            String deviceId = "device-" + userId;
            assertFalse(service.check(userId, "chat", deviceId, "10.0.0.1").blocked());
            service.consume(userId, "chat", 5_000, deviceId, "10.0.0.1");
        }

        AiTokenQuotaService.Decision decision = service.check(5L, "chat", "device-5", "10.0.0.1");

        assertTrue(decision.blocked());
        assertEquals("non-paid-ip-token-quota", decision.reason());
        assertEquals(20_000, decision.tokenLimit());
        assertEquals(20_000, decision.tokensUsed());
    }

    @Test
    void nonPaidAggregateIpBudget_ShouldNotBlockPremiumUsers() {
        AiTokenQuotaProperties properties = new AiTokenQuotaProperties();
        properties.setEnabled(true);
        properties.setRedisEnabled(false);
        properties.setNonPaidAggregateDailyTokenQuotaPerDevice(0);
        properties.setNonPaidAggregateDailyTokenQuotaPerIp(20_000);

        AiEntitlementService entitlementService = mock(AiEntitlementService.class);
        when(entitlementService.resolve(anyLong())).thenAnswer(invocation -> {
            Long userId = invocation.getArgument(0);
            if (userId != null && userId == 99L) {
                return premiumEntitlement();
            }
            return freeTrialEntitlement(50_000);
        });

        TestableAiTokenQuotaService service = new TestableAiTokenQuotaService(properties, entitlementService);
        for (long userId = 1; userId <= 4; userId++) {
            service.consume(userId, "chat", 5_000, "device-" + userId, "10.0.0.1");
        }

        AiTokenQuotaService.Decision decision = service.check(99L, "chat", "premium-device", "10.0.0.1");

        assertFalse(decision.blocked());
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
        assertEquals(1001, stats.utcDayElapsedSeconds());
        assertTrue(stats.projectedTokensUsedToday() > stats.totalTokensUsed());
        assertTrue(stats.projectedCostUsdToday() > stats.estimatedCostUsd());
        assertEquals("7", stats.topUsers().get(0).subject());
        assertEquals(12_500, stats.topUsers().get(0).tokensUsed());
        assertEquals("chat", stats.topScopes().get(0).subject());
        assertEquals(12_500, stats.topScopes().get(0).tokensUsed());
    }

    private static final class TestableAiTokenQuotaService extends AiTokenQuotaService {
        private long nowMs = 1_000_000L;

        private TestableAiTokenQuotaService(AiTokenQuotaProperties properties) {
            super(properties);
        }

        private TestableAiTokenQuotaService(AiTokenQuotaProperties properties,
                                            AiEntitlementService aiEntitlementService) {
            super(properties, null, null, aiEntitlementService);
        }

        @Override
        protected long currentTimeMillis() {
            return nowMs;
        }

        private void setNowMs(long nowMs) {
            this.nowMs = nowMs;
        }
    }

    private static AiEntitlementService.Entitlement freeTrialEntitlement(long dailyLimit) {
        return new AiEntitlementService.Entitlement(
                AiPlanTier.FREE_TRIAL_7D,
                "FREE_TRIAL_7D",
                true,
                dailyLimit,
                true,
                7);
    }

    private static AiEntitlementService.Entitlement premiumEntitlement() {
        return new AiEntitlementService.Entitlement(
                AiPlanTier.PREMIUM,
                "PREMIUM",
                true,
                30_000,
                false,
                0);
    }
}
