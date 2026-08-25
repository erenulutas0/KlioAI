-- Reading: public-domain books, split into the sentences the app shows.
--
-- A learner reads a book one sentence at a time, taps a word they do not know,
-- and that word enters their existing deck with this sentence as its context.
-- The sentence is therefore not decoration: it becomes review material, which
-- is why it is stored as a first-class row rather than sliced out of a blob at
-- read time.
--
-- Only works whose copyright has expired go in here. The text is imported once,
-- translated once, and served from the database — no per-read AI cost.

CREATE TABLE IF NOT EXISTS books (
    id              BIGSERIAL PRIMARY KEY,

    -- Stable identifier used by the client and by the import script, so a
    -- re-import updates a book instead of creating a second copy of it.
    slug            VARCHAR(120) NOT NULL UNIQUE,

    title           VARCHAR(300) NOT NULL,
    author          VARCHAR(200) NOT NULL,

    -- The language the book is IN, matching language_profiles.target_language.
    -- English today; the column is what lets a German shelf exist later without
    -- a migration.
    language        VARCHAR(40)  NOT NULL DEFAULT 'English',

    -- Rough CEFR reading level, for ordering the shelf. Null when unjudged.
    level           VARCHAR(10),

    -- Where the text came from, e.g. 'gutenberg:1661'. Kept so the provenance
    -- of every sentence in the library can be answered years later.
    source          VARCHAR(200),

    -- Denormalised for the shelf, which needs a length without counting rows.
    sentence_count  INTEGER      NOT NULL DEFAULT 0,

    created_at      TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS book_sentences (
    id              BIGSERIAL PRIMARY KEY,
    book_id         BIGINT       NOT NULL REFERENCES books(id) ON DELETE CASCADE,

    -- Position in the book as a whole. This is what progress points at, so it
    -- must be stable: a re-import that renumbered would move every reader.
    sentence_index  INTEGER      NOT NULL,

    chapter_index   INTEGER      NOT NULL DEFAULT 0,
    chapter_title   VARCHAR(300),

    text            TEXT         NOT NULL,

    -- Translated once at import. Null means "not translated yet", which the
    -- reader shows as an unavailable translation rather than as an empty one.
    translation     TEXT,

    CONSTRAINT uq_book_sentence_position UNIQUE (book_id, sentence_index)
);

CREATE INDEX IF NOT EXISTS idx_book_sentences_book_position
    ON book_sentences (book_id, sentence_index);

CREATE TABLE IF NOT EXISTS book_progress (
    id                   BIGSERIAL PRIMARY KEY,
    user_id              BIGINT    NOT NULL,
    book_id              BIGINT    NOT NULL REFERENCES books(id) ON DELETE CASCADE,

    -- The last sentence the learner finished. Zero means "opened, read nothing",
    -- which is different from having no row at all: one is a book on the shelf,
    -- the other is a book never started.
    last_sentence_index  INTEGER   NOT NULL DEFAULT 0,

    updated_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_book_progress_user_book UNIQUE (user_id, book_id)
);

CREATE INDEX IF NOT EXISTS idx_book_progress_user ON book_progress (user_id);
