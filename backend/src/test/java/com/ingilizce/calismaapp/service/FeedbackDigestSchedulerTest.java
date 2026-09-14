package com.ingilizce.calismaapp.service;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.time.LocalDate;
import java.time.LocalDateTime;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class FeedbackDigestSchedulerTest {

    private static final LocalDateTime END = LocalDateTime.of(2026, 9, 14, 18, 0);
    private static final LocalDate DAY = LocalDate.of(2026, 9, 14);

    private FeedbackDigestService digests;
    private TelegramNotifier telegram;
    private FeedbackDigestScheduler scheduler;

    @BeforeEach
    void setUp() {
        digests = mock(FeedbackDigestService.class);
        telegram = mock(TelegramNotifier.class);
        scheduler = new FeedbackDigestScheduler(digests, telegram);
    }

    @Test
    void aDayWithFeedbackIsSent() {
        when(digests.build(any(), any(), any()))
                .thenReturn(new FeedbackDigestService.Digest("KlioAI · 3 puan", false));
        when(telegram.isConfigured()).thenReturn(true);
        when(telegram.send(anyString())).thenReturn(true);

        assertTrue(scheduler.run(END.minusHours(24), END, DAY));
        verify(telegram).send("KlioAI · 3 puan");
    }

    @Test
    void aQuietDayIsSentByDefault_AndNotWhenTurnedOff() {
        when(digests.build(any(), any(), any()))
                .thenReturn(new FeedbackDigestService.Digest("bugün yeni puan ya da ticket yok", true));
        when(telegram.isConfigured()).thenReturn(true);
        when(telegram.send(anyString())).thenReturn(true);

        assertTrue(scheduler.run(END.minusHours(24), END, DAY));

        ReflectionTestUtils.setField(scheduler, "sendWhenEmpty", false);
        assertFalse(scheduler.run(END.minusHours(24), END, DAY));
    }

    @Test
    void withoutABotTheDigestStaysInTheLog() {
        when(digests.build(any(), any(), any()))
                .thenReturn(new FeedbackDigestService.Digest("KlioAI · 1 puan", false));
        when(telegram.isConfigured()).thenReturn(false);

        assertFalse(scheduler.run(END.minusHours(24), END, DAY));
        verify(telegram, never()).send(anyString());
    }

    @Test
    void aDisabledDigestDoesNotEvenBuild() {
        ReflectionTestUtils.setField(scheduler, "enabled", false);

        scheduler.sendDaily();

        verify(digests, never()).build(any(), any(), any());
    }

    @Test
    void aFailureInsideTheDigestIsContained() {
        when(digests.build(any(), any(), any())).thenThrow(new IllegalStateException("db down"));

        scheduler.sendDaily();  // must not throw into the scheduler thread
    }
}
