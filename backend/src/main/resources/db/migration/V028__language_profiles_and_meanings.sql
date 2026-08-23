-- Language profiles and word meanings.
--
-- Two structural changes, both decided:
--   1. A user has one or more language profiles (source -> target language, level, goal);
--      exactly one is active. Every word belongs to a profile.
--   2. A word has one or more meanings; a sentence may be attached to one meaning, or to
--      none ("unassigned" -- the UI treats that as "all meanings").
--
-- The app is English-only today, so the backfill gives every user a single Turkish -> English
-- profile and hangs every existing word on it. words.turkish_meaning is NOT modified: the
-- shipped client reads it, and it stays a denormalised copy of the meanings.
--
-- Everything here is written to be safe to re-run on a database where part of it has already
-- happened (IF NOT EXISTS, NOT EXISTS guards, IS NULL guards).

-- Flyway runs on the application's Hikari pool, whose connection-init-sql caps every statement
-- at 5 s (spring.datasource.hikari.connection-init-sql). The backfill below is three full-table
-- passes over words; measured locally, the first UPDATE alone crosses 5 s somewhere between
-- 70k and 100k rows, and a cancelled statement rolls the whole migration back and stops the
-- backend from booting until an operator raises the cap. SET LOCAL lifts it for this
-- transaction only: Flyway wraps PostgreSQL migrations in one, so the pooled session keeps
-- its 5 s cap once the migration commits.
SET LOCAL statement_timeout = 0;

CREATE TABLE IF NOT EXISTS language_profiles (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    source_language VARCHAR(32) NOT NULL,
    target_language VARCHAR(32) NOT NULL,
    level VARCHAR(8) NOT NULL DEFAULT 'B1',
    learning_goal VARCHAR(32),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT uk_language_profiles_user_target UNIQUE (user_id, target_language),
    CONSTRAINT fk_language_profiles_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_language_profiles_user ON language_profiles(user_id);

CREATE TABLE IF NOT EXISTS word_meanings (
    id BIGSERIAL PRIMARY KEY,
    word_id BIGINT NOT NULL,
    translation VARCHAR(255) NOT NULL,
    definition TEXT,
    position INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_word_meanings_word FOREIGN KEY (word_id) REFERENCES words(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_word_meanings_word ON word_meanings(word_id);

ALTER TABLE words ADD COLUMN IF NOT EXISTS language_profile_id BIGINT;
ALTER TABLE words ADD COLUMN IF NOT EXISTS origin VARCHAR(32);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_words_language_profile') THEN
        ALTER TABLE words
            ADD CONSTRAINT fk_words_language_profile
            FOREIGN KEY (language_profile_id) REFERENCES language_profiles(id);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_words_language_profile ON words(language_profile_id);

ALTER TABLE sentences ADD COLUMN IF NOT EXISTS meaning_id BIGINT;

-- ON DELETE SET NULL: deleting a meaning must not delete the sentences written under it.
-- They become "unassigned", which the UI already has to handle for every pre-existing sentence.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_sentences_meaning') THEN
        ALTER TABLE sentences
            ADD CONSTRAINT fk_sentences_meaning
            FOREIGN KEY (meaning_id) REFERENCES word_meanings(id) ON DELETE SET NULL;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_sentences_meaning ON sentences(meaning_id);

-- ---------------------------------------------------------------------------------------
-- Backfill
-- ---------------------------------------------------------------------------------------

-- One Turkish -> English profile for every user. Users with no words still get one, so the
-- "no profile row" case only exists as a guard in code, never as data this migration leaves.
-- words.user_id references users(id), so the UNION is belt and braces, not a real widening.
INSERT INTO language_profiles (user_id, source_language, target_language, level, is_active)
SELECT u.user_id, 'Turkish', 'English', 'B1', TRUE
FROM (
    SELECT id AS user_id FROM users
    UNION
    SELECT DISTINCT user_id FROM words WHERE user_id IS NOT NULL
) u
WHERE NOT EXISTS (
    SELECT 1 FROM language_profiles lp
    WHERE lp.user_id = u.user_id AND lp.target_language = 'English'
);

UPDATE words w
SET language_profile_id = lp.id
FROM language_profiles lp
WHERE lp.user_id = w.user_id
  AND lp.target_language = 'English'
  AND w.language_profile_id IS NULL;

-- Provenance. The daily-words flow marked its saves by embedding a literal star in the
-- meaning string (the client's isFromDailyWords reads it). chr(11088) is U+2B50 (the emoji
-- star) and chr(9733) is U+2605 (the black star); spelled as code points so this file does
-- not depend on how a literal glyph survives an editor or a checkout.
UPDATE words
SET origin = CASE
    WHEN turkish_meaning LIKE '%' || chr(11088) || '%'
      OR turkish_meaning LIKE '%' || chr(9733) || '%'
    THEN 'daily_words'
    ELSE 'manual'
END
WHERE origin IS NULL;

-- Meanings: split turkish_meaning on ',' ';' and ' / ' into trimmed, non-empty parts with
-- the star markers stripped, de-duplicated case-insensitively keeping the first occurrence,
-- position = order of appearance. A word whose meaning string is blank gets no rows.
-- Only words with no meanings yet are touched, so re-running is a no-op.
WITH parts AS (
    SELECT w.id AS word_id,
           BTRIM(p.part) AS translation,
           p.ord
    FROM words w
    CROSS JOIN LATERAL regexp_split_to_table(
        REPLACE(REPLACE(COALESCE(w.turkish_meaning, ''), chr(11088), ''), chr(9733), ''),
        '\s*[,;]\s*|\s+/\s+'
    ) WITH ORDINALITY AS p(part, ord)
    WHERE NOT EXISTS (SELECT 1 FROM word_meanings wm WHERE wm.word_id = w.id)
),
firsts AS (
    SELECT DISTINCT ON (word_id, LOWER(translation))
           word_id, translation, ord
    FROM parts
    WHERE translation <> ''
    ORDER BY word_id, LOWER(translation), ord
)
INSERT INTO word_meanings (word_id, translation, position)
SELECT word_id,
       LEFT(translation, 255),
       ROW_NUMBER() OVER (PARTITION BY word_id ORDER BY ord) - 1
FROM firsts;

-- sentences.meaning_id deliberately stays NULL. We do not know which meaning a sentence was
-- written for; guessing would be a lie the learner sees later.
