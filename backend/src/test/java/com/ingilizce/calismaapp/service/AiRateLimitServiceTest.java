package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.config.AiRateLimitProperties;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;

import java.util.List;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
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
        properties.setAbusePenaltyEnabled(false);
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

    @SuppressWarnings("unchecked")
    @Test
    void checkAndConsume_ShouldUseRedisDailyQuotaAndReturnRetryAfter() {
        AiRateLimitProperties properties = new AiRateLimitProperties();
        properties.setEnabled(true);
        properties.setRedisEnabled(true);
        properties.setAbusePenaltyEnabled(false);
        properties.setUserWindowMaxRequests(50);
        properties.setIpWindowMaxRequests(50);
        properties.setDailyQuotaPerUser(1);

        StringRedisTemplate redisTemplate = mock(StringRedisTemplate.class);
        ValueOperations<String, String> valueOperations = mock(ValueOperations.class);
        when(redisTemplate.opsForValue()).thenReturn(valueOperations);
        when(valueOperations.increment(anyString())).thenReturn(1L, 1L, 2L);
        when(redisTemplate.getExpire(anyString(), eq(TimeUnit.SECONDS))).thenReturn(45L);

        AiRateLimitService service = new AiRateLimitService(properties, redisTemplate, null);
        AiRateLimitService.Decision decision = service.checkAndConsume(16L, "10.0.0.16", "chat");

        assertTrue(decision.blocked());
        assertEquals("daily-quota", decision.reason());
        assertEquals(45, decision.retryAfterSeconds());
    }

    @SuppressWarnings("unchecked")
    @Test
    void checkAndConsume_ShouldUseRedisScopeDailyQuota() {
        AiRateLimitProperties properties = new AiRateLimitProperties();
        properties.setEnabled(true);
        properties.setRedisEnabled(true);
        properties.setAbusePenaltyEnabled(false);
        properties.setUserWindowMaxRequests(50);
        properties.setIpWindowMaxRequests(50);
        properties.setDailyQuotaPerUser(100);
        AiRateLimitProperties.ScopeLimits chatScope = new AiRateLimitProperties.ScopeLimits();
        chatScope.setDailyQuotaPerUser(1);
        properties.getScopes().put("chat", chatScope);

        StringRedisTemplate redisTemplate = mock(StringRedisTemplate.class);
        ValueOperations<String, String> valueOperations = mock(ValueOperations.class);
        when(redisTemplate.opsForValue()).thenReturn(valueOperations);
        when(valueOperations.increment(anyString())).thenReturn(1L, 1L, 1L, 2L);
        when(redisTemplate.getExpire(anyString(), eq(TimeUnit.SECONDS))).thenReturn(90L);

        AiRateLimitService service = new AiRateLimitService(properties, redisTemplate, null);
        AiRateLimitService.Decision decision = service.checkAndConsume(17L, "10.0.0.17", "chat");

        assertTrue(decision.blocked());
        assertEquals("daily-quota", decision.reason());
        assertEquals(90, decision.retryAfterSeconds());
    }

    @Test
    void checkAndConsume_ShouldApplyScopeWindowOverridesInMemoryMode() {
        AiRateLimitProperties properties = new AiRateLimitProperties();
        properties.setEnabled(true);
        properties.setRedisEnabled(false);
        properties.setUserWindowMaxRequests(50);
        properties.setIpWindowMaxRequests(50);
        properties.setWindowSeconds(60);
        properties.setDailyQuotaPerUser(100);
        properties.setAbusePenaltyEnabled(false);
        AiRateLimitProperties.ScopeLimits chatScope = new AiRateLimitProperties.ScopeLimits();
        chatScope.setUserWindowMaxRequests(1);
        chatScope.setIpWindowMaxRequests(5);
        chatScope.setWindowSeconds(2L);
        chatScope.setDailyQuotaPerUser(50);
        properties.getScopes().put("chat", chatScope);

        TestableAiRateLimitService service = new TestableAiRateLimitService(properties);

        assertFalse(service.checkAndConsume(21L, "10.0.0.21", " chat ").blocked());
        AiRateLimitService.Decision second = service.checkAndConsume(21L, "10.0.0.21", " CHAT ");

        assertTrue(second.blocked());
        assertEquals("user-burst", second.reason());
        assertEquals(2, second.retryAfterSeconds());
    }

    @SuppressWarnings("unchecked")
    @Test
    void checkAndConsume_ShouldApplyRedisPenaltyAndRecordMetrics() {
        AiRateLimitProperties properties = new AiRateLimitProperties();
        properties.setEnabled(true);
        properties.setRedisEnabled(true);
        properties.setUserWindowMaxRequests(1);
        properties.setIpWindowMaxRequests(50);
        properties.setDailyQuotaPerUser(100);
        properties.setAbusePenaltyEnabled(true);
        properties.setAbusePenaltySeconds(List.of(30L, 60L, 150L));
        properties.setAbuseStrikeResetSeconds(900);

        StringRedisTemplate redisTemplate = mock(StringRedisTemplate.class);
        ValueOperations<String, String> valueOperations = mock(ValueOperations.class);
        when(redisTemplate.opsForValue()).thenReturn(valueOperations);
        when(redisTemplate.getExpire(anyString(), eq(TimeUnit.SECONDS))).thenReturn(0L, 0L, 12L);
        when(valueOperations.increment(anyString())).thenReturn(2L, 2L);
        SimpleMeterRegistry meterRegistry = new SimpleMeterRegistry();

        AiRateLimitService service = new AiRateLimitService(properties, redisTemplate, meterRegistry);
        AiRateLimitService.Decision decision = service.checkAndConsume(22L, "10.0.0.22", "chat");

        assertTrue(decision.blocked());
        assertEquals("user-burst", decision.reason());
        assertEquals(60, decision.retryAfterSeconds());
        assertEquals(2, decision.penaltyLevel());
        assertEquals(150, decision.nextPenaltySeconds());
        assertEquals(1.0, meterRegistry.counter(
                "ai.rate.limit.abuse.penalty.apply.total",
                "backend", "redis",
                "reason", "user-burst",
                "scope", "chat",
                "level", "2").count());
        assertEquals(1.0, meterRegistry.counter(
                "ai.rate.limit.block.total",
                "reason", "user-burst",
                "scope", "chat").count());
    }

    @SuppressWarnings("unchecked")
    @Test
    void checkAndConsume_ShouldReturnActiveRedisPenaltyBeforeIncrementingWindows() {
        AiRateLimitProperties properties = new AiRateLimitProperties();
        properties.setEnabled(true);
        properties.setRedisEnabled(true);
        properties.setAbusePenaltyEnabled(true);
        properties.setAbusePenaltySeconds(List.of(30L, 60L, 150L));

        StringRedisTemplate redisTemplate = mock(StringRedisTemplate.class);
        ValueOperations<String, String> valueOperations = mock(ValueOperations.class);
        when(redisTemplate.opsForValue()).thenReturn(valueOperations);
        when(redisTemplate.getExpire(anyString(), eq(TimeUnit.SECONDS))).thenReturn(22L);
        when(valueOperations.get(anyString())).thenReturn("2");

        AiRateLimitService service = new AiRateLimitService(properties, redisTemplate, null);
        AiRateLimitService.Decision decision = service.checkAndConsume(18L, "10.0.0.18", "chat");

        assertTrue(decision.blocked());
        assertEquals("abuse-ban", decision.reason());
        assertEquals(22, decision.retryAfterSeconds());
        assertEquals(2, decision.penaltyLevel());
        assertEquals(150, decision.nextPenaltySeconds());
    }

    @Test
    void clearAbusePenalty_ShouldDeleteRedisPenaltyKeys() {
        AiRateLimitProperties properties = new AiRateLimitProperties();
        properties.setEnabled(true);
        properties.setRedisEnabled(true);

        StringRedisTemplate redisTemplate = mock(StringRedisTemplate.class);
        when(redisTemplate.delete("ai:rl:penalty:ban:u:19")).thenReturn(true);
        when(redisTemplate.delete("ai:rl:penalty:strike:u:19")).thenReturn(false);
        when(redisTemplate.delete("ai:rl:penalty:ban:ip:10.0.0.19")).thenReturn(false);
        when(redisTemplate.delete("ai:rl:penalty:strike:ip:10.0.0.19")).thenReturn(true);

        AiRateLimitService service = new AiRateLimitService(properties, redisTemplate, null);
        AiRateLimitService.UnbanResult result = service.clearAbusePenalty(19L, "10.0.0.19");

        assertTrue(result.userSubjectRequested());
        assertTrue(result.ipSubjectRequested());
        assertTrue(result.userPenaltyCleared());
        assertTrue(result.ipPenaltyCleared());
        assertEquals("u:19", result.userSubject());
        assertEquals("ip:10.0.0.19", result.ipSubject());
        verify(redisTemplate).delete("ai:rl:penalty:ban:u:19");
        verify(redisTemplate).delete("ai:rl:penalty:strike:ip:10.0.0.19");
    }

    @Test
    void getAbusePenaltyStatus_ShouldReadRedisPenaltyTtl() {
        AiRateLimitProperties properties = new AiRateLimitProperties();
        properties.setEnabled(true);
        properties.setRedisEnabled(true);

        StringRedisTemplate redisTemplate = mock(StringRedisTemplate.class);
        when(redisTemplate.getExpire("ai:rl:penalty:ban:u:20", TimeUnit.SECONDS)).thenReturn(75L);
        when(redisTemplate.getExpire("ai:rl:penalty:ban:ip:10.0.0.20", TimeUnit.SECONDS)).thenReturn(0L);

        AiRateLimitService service = new AiRateLimitService(properties, redisTemplate, null);
        AiRateLimitService.AbusePenaltyStatus status = service.getAbusePenaltyStatus(20L, "10.0.0.20");

        assertTrue(status.userSubjectRequested());
        assertTrue(status.ipSubjectRequested());
        assertTrue(status.userPenaltyActive());
        assertFalse(status.ipPenaltyActive());
        assertEquals(75L, status.userRetryAfterSeconds());
    }

    @Test
    void checkAndConsume_ShouldApplyProgressiveAbusePenaltyInMemoryMode() {
        AiRateLimitProperties properties = new AiRateLimitProperties();
        properties.setEnabled(true);
        properties.setRedisEnabled(false);
        properties.setUserWindowMaxRequests(1);
        properties.setIpWindowMaxRequests(100);
        properties.setWindowSeconds(60);
        properties.setDailyQuotaPerUser(100);
        properties.setAbusePenaltyEnabled(true);
        properties.setAbusePenaltySeconds(List.of(30L, 60L, 150L));
        properties.setAbuseStrikeResetSeconds(3600);

        TestableAiRateLimitService service = new TestableAiRateLimitService(properties);

        assertFalse(service.checkAndConsume(8L, "10.0.0.8", "chat").blocked());

        AiRateLimitService.Decision firstBlock = service.checkAndConsume(8L, "10.0.0.8", "chat");
        assertTrue(firstBlock.blocked());
        assertEquals("user-burst", firstBlock.reason());
        assertEquals(30, firstBlock.retryAfterSeconds());
        assertEquals(1, firstBlock.penaltyLevel());
        assertEquals(60, firstBlock.nextPenaltySeconds());

        service.advanceSeconds(30);
        AiRateLimitService.Decision secondBlock = service.checkAndConsume(8L, "10.0.0.8", "chat");
        assertTrue(secondBlock.blocked());
        assertEquals("user-burst", secondBlock.reason());
        assertEquals(60, secondBlock.retryAfterSeconds());
        assertEquals(2, secondBlock.penaltyLevel());
        assertEquals(150, secondBlock.nextPenaltySeconds());

        service.advanceSeconds(60);
        assertFalse(service.checkAndConsume(8L, "10.0.0.8", "chat").blocked());
        AiRateLimitService.Decision thirdBlock = service.checkAndConsume(8L, "10.0.0.8", "chat");
        assertTrue(thirdBlock.blocked());
        assertEquals("user-burst", thirdBlock.reason());
        assertEquals(150, thirdBlock.retryAfterSeconds());
        assertEquals(3, thirdBlock.penaltyLevel());
        assertEquals(150, thirdBlock.nextPenaltySeconds());
    }

    @Test
    void checkAndConsume_ShouldReturnAbuseBanWhilePenaltyWindowActive() {
        AiRateLimitProperties properties = new AiRateLimitProperties();
        properties.setEnabled(true);
        properties.setRedisEnabled(false);
        properties.setUserWindowMaxRequests(1);
        properties.setIpWindowMaxRequests(100);
        properties.setWindowSeconds(60);
        properties.setDailyQuotaPerUser(100);
        properties.setAbusePenaltyEnabled(true);
        properties.setAbusePenaltySeconds(List.of(30L, 60L, 150L));
        properties.setAbuseStrikeResetSeconds(3600);

        TestableAiRateLimitService service = new TestableAiRateLimitService(properties);
        assertFalse(service.checkAndConsume(9L, "10.0.0.9", "chat").blocked());
        assertTrue(service.checkAndConsume(9L, "10.0.0.9", "chat").blocked());

        AiRateLimitService.Decision activeBan = service.checkAndConsume(9L, "10.0.0.9", "chat");
        assertTrue(activeBan.blocked());
        assertEquals("abuse-ban", activeBan.reason());
        assertEquals(1, activeBan.penaltyLevel());
        assertEquals(60, activeBan.nextPenaltySeconds());
    }

    @Test
    void checkAndConsume_ShouldResetPenaltyLevelAfterStrikeWindowExpires() {
        AiRateLimitProperties properties = new AiRateLimitProperties();
        properties.setEnabled(true);
        properties.setRedisEnabled(false);
        properties.setUserWindowMaxRequests(1);
        properties.setIpWindowMaxRequests(100);
        properties.setWindowSeconds(1);
        properties.setDailyQuotaPerUser(100);
        properties.setAbusePenaltyEnabled(true);
        properties.setAbusePenaltySeconds(List.of(30L, 60L, 150L));
        properties.setAbuseStrikeResetSeconds(10);

        TestableAiRateLimitService service = new TestableAiRateLimitService(properties);
        assertFalse(service.checkAndConsume(10L, "10.0.0.10", "chat").blocked());
        assertTrue(service.checkAndConsume(10L, "10.0.0.10", "chat").blocked());

        service.advanceSeconds(31);
        service.advanceSeconds(11);

        assertFalse(service.checkAndConsume(10L, "10.0.0.10", "chat").blocked());
        AiRateLimitService.Decision blockAfterReset = service.checkAndConsume(10L, "10.0.0.10", "chat");
        assertTrue(blockAfterReset.blocked());
        assertEquals("user-burst", blockAfterReset.reason());
        assertEquals(1, blockAfterReset.penaltyLevel());
        assertEquals(30, blockAfterReset.retryAfterSeconds());
    }

    @Test
    void authenticatedUsers_ShouldNotEscalateBanFromIpBurstOnly() {
        AiRateLimitProperties properties = new AiRateLimitProperties();
        properties.setEnabled(true);
        properties.setRedisEnabled(false);
        properties.setUserWindowMaxRequests(100);
        properties.setIpWindowMaxRequests(1);
        properties.setWindowSeconds(60);
        properties.setDailyQuotaPerUser(100);
        properties.setAbusePenaltyEnabled(true);
        properties.setAbusePenaltySeconds(List.of(30L, 60L, 150L));
        properties.setAbuseStrikeResetSeconds(900);

        TestableAiRateLimitService service = new TestableAiRateLimitService(properties);

        assertFalse(service.checkAndConsume(11L, "10.0.0.11", "chat").blocked());

        AiRateLimitService.Decision ipBlocked = service.checkAndConsume(12L, "10.0.0.11", "chat");
        assertTrue(ipBlocked.blocked());
        assertEquals("ip-burst", ipBlocked.reason());
        assertEquals(0, ipBlocked.penaltyLevel());
        assertEquals(0, ipBlocked.nextPenaltySeconds());
    }

    @Test
    void clearAbusePenalty_ShouldRemoveActiveUserBanInMemory() {
        AiRateLimitProperties properties = new AiRateLimitProperties();
        properties.setEnabled(true);
        properties.setRedisEnabled(false);
        properties.setUserWindowMaxRequests(1);
        properties.setIpWindowMaxRequests(100);
        properties.setWindowSeconds(60);
        properties.setDailyQuotaPerUser(100);
        properties.setAbusePenaltyEnabled(true);
        properties.setAbusePenaltySeconds(List.of(30L, 60L, 150L));
        properties.setAbuseStrikeResetSeconds(900);

        TestableAiRateLimitService service = new TestableAiRateLimitService(properties);
        assertFalse(service.checkAndConsume(13L, "10.0.0.13", "chat").blocked());
        AiRateLimitService.Decision blocked = service.checkAndConsume(13L, "10.0.0.13", "chat");
        assertTrue(blocked.blocked());
        assertEquals("user-burst", blocked.reason());

        AiRateLimitService.UnbanResult cleared = service.clearAbusePenalty(13L, null);
        assertTrue(cleared.userPenaltyCleared());
        assertFalse(cleared.ipPenaltyCleared());
        assertEquals("u:13", cleared.userSubject());

        AiRateLimitService.Decision afterClear = service.checkAndConsume(13L, "10.0.0.13", "chat");
        assertTrue(afterClear.blocked());
        assertEquals("user-burst", afterClear.reason());
    }

    @Test
    void anonymousUsers_ShouldEscalateBanFromIpBurst() {
        AiRateLimitProperties properties = new AiRateLimitProperties();
        properties.setEnabled(true);
        properties.setRedisEnabled(false);
        properties.setUserWindowMaxRequests(100);
        properties.setIpWindowMaxRequests(1);
        properties.setWindowSeconds(60);
        properties.setDailyQuotaPerUser(100);
        properties.setAbusePenaltyEnabled(true);
        properties.setAbusePenaltySeconds(List.of(30L, 60L, 150L));
        properties.setAbuseStrikeResetSeconds(900);

        TestableAiRateLimitService service = new TestableAiRateLimitService(properties);

        assertFalse(service.checkAndConsume(null, "10.0.0.12", "chat").blocked());
        AiRateLimitService.Decision ipBlocked = service.checkAndConsume(null, "10.0.0.12", "chat");

        assertTrue(ipBlocked.blocked());
        assertEquals("ip-burst", ipBlocked.reason());
        assertEquals(1, ipBlocked.penaltyLevel());
        assertEquals(30, ipBlocked.retryAfterSeconds());
        assertEquals(60, ipBlocked.nextPenaltySeconds());
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

    @Test
    void getAbusePenaltyStatus_ShouldReportActiveUserPenalty() {
        AiRateLimitProperties properties = new AiRateLimitProperties();
        properties.setEnabled(true);
        properties.setRedisEnabled(false);
        properties.setUserWindowMaxRequests(1);
        properties.setIpWindowMaxRequests(100);
        properties.setWindowSeconds(60);
        properties.setDailyQuotaPerUser(100);
        properties.setAbusePenaltyEnabled(true);
        properties.setAbusePenaltySeconds(List.of(30L, 60L, 150L));
        properties.setAbuseStrikeResetSeconds(900);

        TestableAiRateLimitService service = new TestableAiRateLimitService(properties);
        assertFalse(service.checkAndConsume(14L, "10.0.0.14", "chat").blocked());
        assertTrue(service.checkAndConsume(14L, "10.0.0.14", "chat").blocked());

        AiRateLimitService.AbusePenaltyStatus status = service.getAbusePenaltyStatus(14L, null);

        assertTrue(status.userSubjectRequested());
        assertEquals("u:14", status.userSubject());
        assertTrue(status.userPenaltyActive());
        assertEquals(30L, status.userRetryAfterSeconds());
        assertFalse(status.ipPenaltyActive());
    }

    @Test
    void getAbuseStats_ShouldExposeMemoryPenaltyCounters() {
        AiRateLimitProperties properties = new AiRateLimitProperties();
        properties.setEnabled(true);
        properties.setRedisEnabled(false);
        properties.setUserWindowMaxRequests(1);
        properties.setIpWindowMaxRequests(100);
        properties.setWindowSeconds(60);
        properties.setDailyQuotaPerUser(100);
        properties.setAbusePenaltyEnabled(true);
        properties.setAbusePenaltySeconds(List.of(30L, 60L, 150L));
        properties.setAbuseStrikeResetSeconds(900);

        TestableAiRateLimitService service = new TestableAiRateLimitService(properties);
        assertFalse(service.checkAndConsume(15L, "10.0.0.15", "chat").blocked());
        assertTrue(service.checkAndConsume(15L, "10.0.0.15", "chat").blocked());

        AiRateLimitService.AbuseStats stats = service.getAbuseStats();
        assertTrue(stats.enabled());
        assertTrue(stats.abusePenaltyEnabled());
        assertNotNull(stats.abusePenaltySeconds());
        assertEquals(3, stats.abusePenaltySeconds().size());
        assertEquals(1, stats.memoryPenaltySubjects());
        assertEquals(1, stats.memoryActivePenaltySubjects());
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

        private void advanceSeconds(long seconds) {
            nowMs += TimeUnit.SECONDS.toMillis(seconds);
        }
    }
}
