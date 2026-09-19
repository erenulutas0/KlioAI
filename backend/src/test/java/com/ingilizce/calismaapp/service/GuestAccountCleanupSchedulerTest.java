package com.ingilizce.calismaapp.service;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.time.LocalDateTime;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class GuestAccountCleanupSchedulerTest {

    private static final LocalDateTime CUTOFF = LocalDateTime.of(2026, 8, 20, 3, 30);

    private GuestAccountCleanupService cleanupService;
    private GuestAccountCleanupScheduler scheduler;

    @BeforeEach
    void setUp() {
        cleanupService = mock(GuestAccountCleanupService.class);
        scheduler = new GuestAccountCleanupScheduler(cleanupService);
        ReflectionTestUtils.setField(scheduler, "batchSize", 200);
        ReflectionTestUtils.setField(scheduler, "maxBatches", 25);
        ReflectionTestUtils.setField(scheduler, "enabled", true);
        ReflectionTestUtils.setField(scheduler, "retentionDays", 30);
    }

    @Test
    void batchesAreTakenUntilThereAreNoneLeft() {
        when(cleanupService.purgeBatch(any(), anyInt())).thenReturn(200, 200, 37, 0);

        assertEquals(437, scheduler.run(CUTOFF));
        verify(cleanupService, times(4)).purgeBatch(CUTOFF, 200);
    }

    @Test
    void aBacklogIsDrainedOverSeveralNightsRatherThanOneLongRun() {
        ReflectionTestUtils.setField(scheduler, "maxBatches", 3);
        when(cleanupService.purgeBatch(any(), anyInt())).thenReturn(200);

        assertEquals(600, scheduler.run(CUTOFF));
        verify(cleanupService, times(3)).purgeBatch(CUTOFF, 200);
    }

    @Test
    void aDisabledCleanupDeletesNothing() {
        ReflectionTestUtils.setField(scheduler, "enabled", false);

        scheduler.purgeExpiredGuests();

        verify(cleanupService, never()).purgeBatch(any(), anyInt());
    }

    @Test
    void aFailedSweepIsContained() {
        when(cleanupService.purgeBatch(any(), anyInt())).thenThrow(new IllegalStateException("db down"));

        scheduler.purgeExpiredGuests();  // must not throw into the scheduler thread
    }
}
