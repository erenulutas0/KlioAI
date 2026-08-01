-- An append-only log of every graded recall attempt.
--
-- Until now nothing recorded that a review happened. The words table carries only the
-- scheduler's current state -- next_review_date, ease_factor, review_count -- so each grade
-- overwrote the previous one and the history was gone. That made the product's central
-- claim, a memory of how this learner is doing, unbacked by any data.
--
-- With this log: a scheduler can be fitted to the individual (FSRS is trained on exactly
-- this shape), confusable pairs can be surfaced, a real forgetting curve can be drawn, and
-- a change to the app can be measured against retention instead of guessed at.
--
-- Both the before and after state are stored on each row so a row can be read on its own.
-- Reconstructing "before" by replaying earlier rows would break the moment a backfill, a
-- manual correction or a scheduler change enters the history.

CREATE TABLE IF NOT EXISTS review_events (
    id                    BIGSERIAL PRIMARY KEY,
    user_id               BIGINT       NOT NULL,
    word_id               BIGINT       NOT NULL,
    source_feature        VARCHAR(40)  NOT NULL,
    grade                 INTEGER      NOT NULL,
    interval_before_days  INTEGER,
    interval_after_days   INTEGER,
    ease_before           DOUBLE PRECISION,
    ease_after            DOUBLE PRECISION,
    repetition_before     INTEGER,
    response_ms           INTEGER,
    created_at            TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- "This learner's history in order" and "this word's history in order" are the two reads
-- everything else is built from.
CREATE INDEX IF NOT EXISTS idx_review_events_user_created
    ON review_events (user_id, created_at);

CREATE INDEX IF NOT EXISTS idx_review_events_word_created
    ON review_events (word_id, created_at);

-- SM-2 grades are 0-5. A row outside that range is a bug in a caller, and silently storing
-- it would poison every model fitted on this table later.
ALTER TABLE review_events
    ADD CONSTRAINT chk_review_events_grade CHECK (grade >= 0 AND grade <= 5);

-- No foreign keys to words on purpose: deleting a word must not delete the evidence that it
-- was once studied, and a cascade here would quietly destroy history.
