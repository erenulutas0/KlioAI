package com.ingilizce.calismaapp.entity;

/**
 * Where a word came from; the values stored in {@code words.origin}.
 *
 * <p>Before V028 this was encoded by embedding a literal star in {@code turkish_meaning}
 * (the shipped client's {@code isFromDailyWords} still reads it). Constants rather than an
 * enum column so a new source can be stored without a migration.
 */
public final class WordOrigin {

    private WordOrigin() {
    }

    /** Saved from the daily-words flow. */
    public static final String DAILY_WORDS = "daily_words";

    /** Added by hand, or from the dictionary; everything that is not daily words. */
    public static final String MANUAL = "manual";

    /** The two characters the old encoding used; the backfill strips both. */
    public static final String DAILY_WORDS_MARKER_EMOJI = "⭐";
    public static final String DAILY_WORDS_MARKER_BLACK_STAR = "★";

    /** Whether a legacy meaning string carries the daily-words marker. */
    public static boolean hasDailyWordsMarker(String turkishMeaning) {
        return turkishMeaning != null
                && (turkishMeaning.contains(DAILY_WORDS_MARKER_EMOJI)
                        || turkishMeaning.contains(DAILY_WORDS_MARKER_BLACK_STAR));
    }
}
