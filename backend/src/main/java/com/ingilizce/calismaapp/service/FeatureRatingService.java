package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.entity.FeatureRating;
import com.ingilizce.calismaapp.repository.FeatureRatingRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;
import java.util.regex.Pattern;

/**
 * Takes a learner's 1-5 answer to "how was this?" and keeps it. See V031.
 *
 * <p>Everything a rating carries comes from the app and is written by a learner, so each
 * field is bounded here rather than trusted: stars must be 1-5, the note and context are
 * capped, and a scene id that is not a plain catalog id is dropped rather than stored.
 */
@Service
public class FeatureRatingService {

    private static final Logger logger = LoggerFactory.getLogger(FeatureRatingService.class);

    /**
     * More than a learner could honestly give in a day -- the app asks at most once a day --
     * and few enough that a script hammering the endpoint cannot bury the digest.
     */
    static final int DAILY_LIMIT = 10;

    static final int NOTE_MAX = 1000;
    static final int CONTEXT_MAX = 2000;

    /** Catalog ids are lower snake case: restaurant_order, cafe_order. */
    private static final Pattern SCENE_ID = Pattern.compile("[a-z0-9_]{1,64}");

    private final FeatureRatingRepository repository;

    public FeatureRatingService(FeatureRatingRepository repository) {
        this.repository = repository;
    }

    @Transactional
    public Map<String, Object> submit(Long userId, String feature, Integer stars, String note,
            String sceneId, String locale, String appVersion, String contextJson) {
        if (stars == null || stars < 1 || stars > 5) {
            throw new IllegalArgumentException("INVALID_STARS");
        }
        if (countToday(userId) >= DAILY_LIMIT) {
            throw new IllegalStateException("DAILY_LIMIT_REACHED");
        }

        FeatureRating rating = new FeatureRating();
        rating.setUserId(userId);
        rating.setFeature(parseFeature(feature));
        rating.setStars(stars);
        rating.setNote(bounded(note, NOTE_MAX));
        rating.setSceneId(sceneId(sceneId));
        rating.setLocale(bounded(locale, 16));
        rating.setAppVersion(bounded(appVersion, 32));
        // Truncated rather than rejected, as for support tickets: an oversized context is
        // still worth most of its value, and refusing the rating over it would lose the rating.
        rating.setContextJson(bounded(contextJson, CONTEXT_MAX));

        FeatureRating saved = repository.save(rating);
        // Without the note: that is the learner's own words, and it goes to the digest.
        logger.info("Rating feature={} stars={} scene={} user={} note={}",
                saved.getFeature(), saved.getStars(), saved.getSceneId(), userId,
                saved.getNote() == null ? "no" : "yes");

        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("id", saved.getId());
        payload.put("feature", saved.getFeature().name());
        payload.put("stars", saved.getStars());
        payload.put("createdAt", saved.getCreatedAt());
        return payload;
    }

    static FeatureRating.Feature parseFeature(String raw) {
        if (raw == null || raw.isBlank()) {
            return FeatureRating.Feature.PRACTICE;
        }
        try {
            // Locale.ROOT: on a Turkish JVM "writing".toUpperCase() is "WRİTİNG".
            return FeatureRating.Feature.valueOf(raw.trim().toUpperCase(Locale.ROOT));
        } catch (IllegalArgumentException unknown) {
            return FeatureRating.Feature.PRACTICE;
        }
    }

    private static String sceneId(String raw) {
        if (raw == null) {
            return null;
        }
        String trimmed = raw.trim();
        return SCENE_ID.matcher(trimmed).matches() ? trimmed : null;
    }

    private static String bounded(String raw, int max) {
        if (raw == null) {
            return null;
        }
        String trimmed = raw.trim();
        if (trimmed.isEmpty()) {
            return null;
        }
        return trimmed.length() > max ? trimmed.substring(0, max) : trimmed;
    }

    private long countToday(Long userId) {
        LocalDate today = LocalDate.now();
        return repository.countByUserIdAndCreatedAtBetween(userId,
                LocalDateTime.of(today, LocalTime.MIN), LocalDateTime.of(today, LocalTime.MAX));
    }
}
