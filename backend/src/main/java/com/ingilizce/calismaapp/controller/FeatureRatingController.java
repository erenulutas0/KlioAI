package com.ingilizce.calismaapp.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ingilizce.calismaapp.service.FeatureRatingService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * {@code POST /api/feedback/ratings} -- a learner's 1-5 answer to "how was this?".
 *
 * <pre>{"feature": "TUTOR", "stars": 4, "note": "...", "sceneId": "restaurant_order",
 *  "locale": "tr", "appVersion": "1.4.1+484", "context": {"turns": 6}}</pre>
 */
@RestController
@RequestMapping("/api/feedback/ratings")
public class FeatureRatingController {

    private static final ObjectMapper JSON = new ObjectMapper();

    private final FeatureRatingService service;

    public FeatureRatingController(FeatureRatingService service) {
        this.service = service;
    }

    @PostMapping
    public ResponseEntity<Map<String, Object>> submit(
            @RequestHeader("X-User-Id") Long userId,
            @RequestBody Map<String, Object> body) {
        Integer stars = stars(body.get("stars"));
        try {
            Map<String, Object> saved = service.submit(
                    userId,
                    text(body.get("feature")),
                    stars,
                    text(body.get("note")),
                    text(body.get("sceneId")),
                    text(body.get("locale")),
                    text(body.get("appVersion")),
                    context(body.get("context")));
            return ResponseEntity.status(HttpStatus.CREATED).body(saved);
        } catch (IllegalArgumentException invalid) {
            return ResponseEntity.badRequest().body(Map.of("error", "stars must be 1 to 5"));
        } catch (IllegalStateException limited) {
            return ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS)
                    .body(Map.of("error", "daily rating limit reached"));
        }
    }

    /** A number or a numeric string; anything else is not a rating. */
    private static Integer stars(Object raw) {
        if (raw instanceof Number number) {
            double value = number.doubleValue();
            return value == Math.rint(value) ? (int) value : null;
        }
        if (raw instanceof String text) {
            try {
                return Integer.valueOf(text.trim());
            } catch (NumberFormatException ignored) {
                return null;
            }
        }
        return null;
    }

    private static String text(Object raw) {
        return raw instanceof String text ? text : null;
    }

    /** An object from the app, stored as JSON; a string is taken as already being JSON. */
    private static String context(Object raw) {
        if (raw == null) {
            return null;
        }
        if (raw instanceof String text) {
            return text;
        }
        try {
            return JSON.writeValueAsString(raw);
        } catch (Exception unserialisable) {
            return null;
        }
    }
}
