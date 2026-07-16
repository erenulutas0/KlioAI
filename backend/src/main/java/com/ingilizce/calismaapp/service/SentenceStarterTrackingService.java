package com.ingilizce.calismaapp.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;

/**
 * Redis-backed per-user history of recent translation-practice sentence
 * starters (prompt strategy Phase 2, "recentSentencePatterns").
 *
 * Sentence content itself is cached globally (shared across users for the
 * same word/profile/pattern combination), but starter-word repetition is a
 * per-user experience problem, so this tracks it separately. Degrades safely
 * to no tracking when Redis is unavailable.
 */
@Service
public class SentenceStarterTrackingService {

    private static final Logger log = LoggerFactory.getLogger(SentenceStarterTrackingService.class);

    private static final String KEY_PREFIX = "sentences:starters:user:";
    private static final Duration TTL = Duration.ofHours(24);
    private static final int MAX_STORED_STARTERS = 20;
    private static final int CONTEXT_STARTERS = 10;

    private final RedisTemplate<String, Object> redisTemplate;

    public SentenceStarterTrackingService(
            @Autowired(required = false) RedisTemplate<String, Object> redisTemplate) {
        this.redisTemplate = redisTemplate;
    }

    /**
     * Last few sentence-starter words this user has already seen, oldest first.
     */
    public List<String> recentStarters(Long userId) {
        if (userId == null || redisTemplate == null) {
            return List.of();
        }
        try {
            List<Object> stored = redisTemplate.opsForList().range(key(userId), -CONTEXT_STARTERS, -1);
            if (stored == null || stored.isEmpty()) {
                return List.of();
            }
            List<String> starters = new ArrayList<>(stored.size());
            for (Object entry : stored) {
                if (entry instanceof String text && !text.isBlank()) {
                    starters.add(text);
                }
            }
            return starters;
        } catch (Exception e) {
            log.debug("Sentence starter history unavailable for userId={}: {}", userId, e.toString());
            return List.of();
        }
    }

    /**
     * Appends the starters this user was just shown and refreshes the TTL.
     */
    public void recordStarters(Long userId, List<String> starters) {
        if (userId == null || redisTemplate == null || starters == null || starters.isEmpty()) {
            return;
        }
        try {
            String key = key(userId);
            for (String starter : starters) {
                if (starter != null && !starter.isBlank()) {
                    redisTemplate.opsForList().rightPush(key, starter);
                }
            }
            redisTemplate.opsForList().trim(key, -MAX_STORED_STARTERS, -1);
            redisTemplate.expire(key, TTL);
        } catch (Exception e) {
            log.debug("Could not record sentence starters for userId={}: {}", userId, e.toString());
        }
    }

    private String key(Long userId) {
        return KEY_PREFIX + userId + ":recent";
    }
}
