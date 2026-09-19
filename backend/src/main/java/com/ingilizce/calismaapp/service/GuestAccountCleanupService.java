package com.ingilizce.calismaapp.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;

/**
 * Deletes guest accounts that were never signed into. See V032 for what a guest account is.
 *
 * <p>A guest row is created on first launch without anyone asking for it, so most of them are
 * someone who opened the app once and never came back. They are not empty markers: they carry
 * words, conversations, refresh sessions and push tokens. Left alone they would outnumber the
 * accounts that belong to people inside a month, which turns every "how many learners do we
 * have" query into a lie and makes the retention number this whole change exists to move
 * unreadable.
 *
 * <p>Children are deleted by hand, before their parent, rather than left to ON DELETE CASCADE.
 * A third of the tables carrying a user_id -- support_tickets, feature_ratings,
 * device_push_tokens, review_events, book_progress -- have no foreign key to users at all, so
 * a cascade would quietly leave their rows behind pointing at an id that no longer exists.
 * The legacy social tables (posts, comments, post_likes, messages, friendships, and the
 * user_profiles family from V001) are deliberately not listed: no code in this backend has
 * ever written a row to any of them, and in Postgres they cascade anyway.
 *
 * <p>The {@code is_guest = TRUE} in the final DELETE is not redundant with the SELECT that
 * chose the ids. It is the one line standing between a mistake anywhere above it and the
 * deletion of an account somebody paid for.
 */
@Service
public class GuestAccountCleanupService {

    private static final Logger log = LoggerFactory.getLogger(GuestAccountCleanupService.class);

    /**
     * The two extra conditions are not about guests being old enough. Nothing stops a learner
     * from subscribing before they sign in -- Google Play takes the money from the device, not
     * from an account -- and deleting a row somebody has paid against would destroy the only
     * record of what they bought. A guest who has paid stays until a person decides otherwise.
     */
    private static final String SELECT_EXPIRED_GUESTS =
            "SELECT id FROM users u"
                    + " WHERE u.is_guest = TRUE"
                    + " AND u.created_at < :cutoff"
                    + " AND u.subscription_end_date IS NULL"
                    + " AND NOT EXISTS (SELECT 1 FROM payment_transactions p WHERE p.user_id = u.id)"
                    + " ORDER BY u.id LIMIT :limit";

    /**
     * Everything keyed on a user this backend writes, in an order no foreign key objects to.
     * The three that are not obvious: a word's sentences, reviews and meanings go before the
     * word itself; language_profiles goes after words, because words point at profiles rather
     * than the other way round; and notification_delivery_log goes before device_push_tokens,
     * which it references.
     */
    private static final List<String> CHILD_DELETES = List.of(
            "DELETE FROM sentences WHERE word_id IN (SELECT id FROM words WHERE user_id IN (:ids))",
            "DELETE FROM word_reviews WHERE word_id IN (SELECT id FROM words WHERE user_id IN (:ids))",
            "DELETE FROM word_meanings WHERE word_id IN (SELECT id FROM words WHERE user_id IN (:ids))",
            "DELETE FROM words WHERE user_id IN (:ids)",
            "DELETE FROM language_profiles WHERE user_id IN (:ids)",
            "DELETE FROM notification_delivery_log WHERE user_id IN (:ids)",
            "DELETE FROM device_push_tokens WHERE user_id IN (:ids)",
            "DELETE FROM notification_preferences WHERE user_id IN (:ids)",
            "DELETE FROM book_progress WHERE user_id IN (:ids)",
            "DELETE FROM feature_ratings WHERE user_id IN (:ids)",
            "DELETE FROM support_tickets WHERE user_id IN (:ids)",
            "DELETE FROM review_events WHERE user_id IN (:ids)",
            "DELETE FROM sentence_practices WHERE user_id IN (:ids)",
            "DELETE FROM user_achievements WHERE user_id IN (:ids)",
            "DELETE FROM user_activities WHERE user_id IN (:ids)",
            "DELETE FROM user_progress WHERE user_id IN (:ids)",
            "DELETE FROM payment_transactions WHERE user_id IN (:ids)",
            "DELETE FROM refresh_token_sessions WHERE user_id IN (:ids)",
            "DELETE FROM password_reset_tokens WHERE user_id IN (:ids)",
            "DELETE FROM email_verification_tokens WHERE user_id IN (:ids)");

    private static final String DELETE_GUESTS =
            "DELETE FROM users WHERE id IN (:ids) AND is_guest = TRUE";

    private final NamedParameterJdbcTemplate jdbc;

    public GuestAccountCleanupService(NamedParameterJdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /**
     * Deletes at most {@code batchSize} guest accounts created before {@code cutoff}, with
     * everything that hangs off them, and returns how many accounts went. Zero means there is
     * nothing left to collect.
     *
     * <p>One transaction per batch rather than one for the whole run: a batch must be all or
     * nothing -- a half-deleted account is rows pointing at an id that is gone -- but wrapping
     * every batch of a backlog in a single transaction would hold locks on twenty tables for
     * as long as the backlog takes and throw away the whole night's work on the last failure.
     */
    @Transactional
    public int purgeBatch(LocalDateTime cutoff, int batchSize) {
        List<Long> ids = jdbc.queryForList(
                SELECT_EXPIRED_GUESTS,
                new MapSqlParameterSource()
                        .addValue("cutoff", cutoff)
                        .addValue("limit", batchSize),
                Long.class);
        if (ids.isEmpty()) {
            return 0;
        }

        MapSqlParameterSource params = new MapSqlParameterSource("ids", ids);
        for (String sql : CHILD_DELETES) {
            jdbc.update(sql, params);
        }
        int deleted = jdbc.update(DELETE_GUESTS, params);
        log.info("Guest cleanup deleted {} account(s) older than {}", deleted, cutoff);
        return deleted;
    }
}
