-- A learner's 1-5 answer to "how was this?", asked right after they used a feature.
--
-- Until this table the app could hear only complaints. The question it already asked --
-- "is KlioAI improving your English?" -- sent a ticket for "not really" and kept "yes" on
-- the phone, so the server saw a stream of unhappy answers and nothing to set them against:
-- no ratio, no trend, no way to tell a bad week from a quiet one. And it was never asked
-- after the tutor at all, which is the feature the app is sold on.
--
-- Every answer lands here, five stars included, with what it was about: the feature, the
-- scene for a tutor conversation, the app version. A daily digest reads it
-- (FeedbackDigestService).
--
-- Not a support ticket. Tickets are requests for help, capped at three a day per learner;
-- a rating is a measurement, and mixing the two would put both limits and both meanings on
-- one row.
--
-- Keyed by user_id like support_tickets. Account deletion is handled by hand from an
-- ACCOUNT_DELETION ticket: it has to clear this table too, because a note is the learner's
-- own words.

CREATE TABLE IF NOT EXISTS feature_ratings (
    id            BIGSERIAL    PRIMARY KEY,
    user_id       BIGINT       NOT NULL,

    -- TUTOR, READING, WRITING, SESSION, PRACTICE. A string rather than a CHECK list, so a
    -- new surface needs no migration (the lesson of V027).
    feature       VARCHAR(32)  NOT NULL,

    stars         INTEGER      NOT NULL CHECK (stars BETWEEN 1 AND 5),

    -- Optional. Asked for when the stars are low: a number says something is wrong, the
    -- note says what.
    note          TEXT,

    -- The scene a tutor conversation was set in, e.g. restaurant_order. Null elsewhere.
    scene_id      VARCHAR(64),

    locale        VARCHAR(16),
    app_version   VARCHAR(32),

    -- Anything else worth keeping: turns in the conversation, level. Free-form for the same
    -- reason as support_tickets.context_json.
    context_json  TEXT,

    created_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_feature_ratings_created
    ON feature_ratings(created_at);

CREATE INDEX IF NOT EXISTS idx_feature_ratings_user_created
    ON feature_ratings(user_id, created_at DESC);
