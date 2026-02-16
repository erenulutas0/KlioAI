-- Optimizes word detail/list hydration and sentence delete lookups.
CREATE INDEX IF NOT EXISTS idx_sentence_word_id ON sentences(word_id, id);
