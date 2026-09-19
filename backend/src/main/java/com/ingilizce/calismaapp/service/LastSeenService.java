package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.repository.UserRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDateTime;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Stamps {@code users.last_seen_at} when a learner is seen.
 *
 * <p>The column has been in the schema since V000 and nothing has ever written to it. So the
 * one question worth asking after removing the sign-in wall -- do people come back on a second
 * day -- could only be put to Firebase, which counts devices rather than accounts, and the
 * best answer anyone could produce was 11 of 105 accounts.
 *
 * <p>An UPDATE per authenticated request would be a write on every word list, every SRS poll
 * and every turn of a conversation, for a column whose finest useful resolution is the day.
 * So the last write per learner is kept in this JVM's memory and the UPDATE is skipped while
 * it is inside {@link #WRITE_INTERVAL}. The cost of that memory being wrong -- a restart, a
 * second instance, an eviction -- is one extra write, which is why it is memory and not a
 * read of the row it is about to write.
 */
@Service
public class LastSeenService {

    private static final Logger log = LoggerFactory.getLogger(LastSeenService.class);

    /**
     * How long a stamp is treated as current. Ten minutes because the questions this column
     * answers are all counted in days; anything finer is paid for on every request and read
     * by nobody.
     */
    static final Duration WRITE_INTERVAL = Duration.ofMinutes(10);

    /**
     * Above this many tracked learners the map is emptied rather than grown. It is a cache of
     * "written recently", so losing it costs one extra UPDATE per active learner and nothing
     * else -- and an unbounded map keyed by user id is a slow leak in a process that is meant
     * to run for months.
     */
    static final int MAX_TRACKED_USERS = 50_000;

    private final ConcurrentHashMap<Long, Instant> lastWrites = new ConcurrentHashMap<>();

    private final UserRepository userRepository;
    private final Clock clock;

    @Autowired
    public LastSeenService(UserRepository userRepository) {
        this(userRepository, Clock.systemDefaultZone());
    }

    LastSeenService(UserRepository userRepository, Clock clock) {
        this.userRepository = userRepository;
        this.clock = clock;
    }

    /**
     * Records that this learner is here, at most once per {@link #WRITE_INTERVAL}.
     *
     * <p>Nothing that happens in here may reach the caller: this is a measurement taken on the
     * way through somebody's lesson, and a retention number that can turn a conversation into
     * a 500 is worth less than no retention number at all.
     */
    public void touch(Long userId) {
        if (userId == null) {
            return;
        }
        try {
            Instant now = clock.instant();
            Instant threshold = now.minus(WRITE_INTERVAL);
            // compute, not get-then-put: two requests from the same learner arriving together
            // have to produce one UPDATE rather than two. The map keeps the older stamp when
            // it is still current, so the reference test below tells the winner from the rest.
            Instant mark = lastWrites.compute(userId,
                    (id, previous) -> (previous != null && previous.isAfter(threshold)) ? previous : now);
            if (mark != now) {
                return;
            }
            if (lastWrites.size() > MAX_TRACKED_USERS) {
                lastWrites.clear();
            }
            userRepository.markLastSeen(userId, LocalDateTime.now(clock));
        } catch (RuntimeException e) {
            // The stamp stays in the map even though the write failed, on purpose: a database
            // that is refusing writes should be asked again in ten minutes, not on every
            // request of every learner for as long as it is down.
            log.debug("last_seen_at not stamped for userId={}: {}", userId, e.toString());
        }
    }
}
