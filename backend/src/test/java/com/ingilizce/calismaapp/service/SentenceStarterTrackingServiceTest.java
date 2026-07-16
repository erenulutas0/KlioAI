package com.ingilizce.calismaapp.service;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.redis.core.ListOperations;
import org.springframework.data.redis.core.RedisTemplate;

import java.time.Duration;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class SentenceStarterTrackingServiceTest {

    private static final String KEY = "sentences:starters:user:42:recent";

    @Mock
    private RedisTemplate<String, Object> redisTemplate;

    @Mock
    private ListOperations<String, Object> listOperations;

    private SentenceStarterTrackingService service;

    @BeforeEach
    void setUp() {
        service = new SentenceStarterTrackingService(redisTemplate);
        lenient().when(redisTemplate.opsForList()).thenReturn(listOperations);
    }

    @Test
    void recentStarters_ShouldReturnStoredStringEntries() {
        when(listOperations.range(KEY, -10, -1)).thenReturn(List.of("The", "I", "", "Please"));

        List<String> starters = service.recentStarters(42L);

        assertEquals(List.of("The", "I", "Please"), starters);
    }

    @Test
    void recentStarters_ShouldDegradeToEmpty_WhenRedisFails() {
        when(listOperations.range(anyString(), eq(-10L), eq(-1L)))
                .thenThrow(new RuntimeException("redis down"));

        assertTrue(service.recentStarters(42L).isEmpty());
    }

    @Test
    void recentStarters_ShouldDegradeToEmpty_WithoutRedisOrUser() {
        assertTrue(new SentenceStarterTrackingService(null).recentStarters(42L).isEmpty());
        assertTrue(service.recentStarters(null).isEmpty());
    }

    @Test
    void recordStarters_ShouldPushEachTrimAndRefreshTtl() {
        service.recordStarters(42L, List.of("The", "Please"));

        verify(listOperations).rightPush(KEY, "The");
        verify(listOperations).rightPush(KEY, "Please");
        verify(listOperations).trim(KEY, -20, -1);
        verify(redisTemplate).expire(KEY, Duration.ofHours(24));
    }

    @Test
    void recordStarters_ShouldSkipBlankEntries() {
        java.util.List<String> starters = new java.util.ArrayList<>();
        starters.add("The");
        starters.add(" ");
        starters.add(null);
        service.recordStarters(42L, starters);

        verify(listOperations).rightPush(KEY, "The");
        verify(listOperations, never()).rightPush(KEY, " ");
    }

    @Test
    void recordStarters_ShouldNoOp_WhenListEmptyOrUserMissing() {
        service.recordStarters(42L, List.of());
        service.recordStarters(null, List.of("The"));
        new SentenceStarterTrackingService(null).recordStarters(42L, List.of("The"));

        verify(listOperations, never()).rightPush(anyString(), org.mockito.ArgumentMatchers.any());
    }
}
