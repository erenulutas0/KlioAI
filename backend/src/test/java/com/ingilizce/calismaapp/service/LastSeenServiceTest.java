package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.repository.UserRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * last_seen_at is the only thing that can answer "did they come back the next day", and it is
 * written on the way through every authenticated request -- so it has to be both written and
 * cheap, and it may never be the reason a request fails.
 */
class LastSeenServiceTest {

    /** A clock the test moves by hand, so the throttle window can be crossed without waiting. */
    private static class TestClock extends Clock {
        private Instant now = Instant.parse("2026-09-19T09:00:00Z");

        void advance(Duration amount) {
            now = now.plus(amount);
        }

        @Override
        public ZoneId getZone() {
            return ZoneId.of("UTC");
        }

        @Override
        public Clock withZone(ZoneId zone) {
            return this;
        }

        @Override
        public Instant instant() {
            return now;
        }
    }

    private UserRepository userRepository;
    private TestClock clock;
    private LastSeenService service;

    @BeforeEach
    void setUp() {
        userRepository = mock(UserRepository.class);
        clock = new TestClock();
        service = new LastSeenService(userRepository, clock);
    }

    @Test
    void theFirstRequestOfALearnerIsWritten() {
        service.touch(42L);

        verify(userRepository).markLastSeen(eq(42L), any(LocalDateTime.class));
    }

    @Test
    void everyRequestInsideTheWindowCostsNoWrite() {
        service.touch(42L);

        for (int i = 0; i < 50; i++) {
            clock.advance(Duration.ofSeconds(10));
            service.touch(42L);
        }

        verify(userRepository, times(1)).markLastSeen(anyLong(), any());
    }

    @Test
    void afterTheWindowItIsWrittenAgain() {
        service.touch(42L);
        clock.advance(LastSeenService.WRITE_INTERVAL.plusSeconds(1));
        service.touch(42L);

        verify(userRepository, times(2)).markLastSeen(eq(42L), any());
    }

    @Test
    void twoLearnersAreThrottledSeparately() {
        service.touch(42L);
        service.touch(43L);

        verify(userRepository).markLastSeen(eq(42L), any());
        verify(userRepository).markLastSeen(eq(43L), any());
    }

    @Test
    void aDatabaseThatRefusesTheWriteDoesNotReachTheCaller() {
        when(userRepository.markLastSeen(anyLong(), any()))
                .thenThrow(new RuntimeException("connection pool exhausted"));

        service.touch(42L);  // must not throw: the caller is somebody's lesson

        // And it is not retried on the next request either, or a database that is down would
        // be asked again by every request of every learner until it came back.
        clock.advance(Duration.ofSeconds(30));
        service.touch(42L);
        verify(userRepository, times(1)).markLastSeen(anyLong(), any());
    }

    @Test
    void aRequestWithoutAUserWritesNothing() {
        service.touch(null);

        verify(userRepository, never()).markLastSeen(any(), any());
    }
}
