package com.ingilizce.calismaapp.entity;

/**
 * The surfaces that can produce a graded recall attempt.
 *
 * <p>Kept as constants rather than an enum column so a new surface can start logging without
 * a schema migration, and so an unrecognised value from an older client is stored rather than
 * rejected -- losing the observation would be worse than storing a name we do not know yet.
 *
 * <p>Only {@link #CLASSIC_REVIEW} and {@link #WORD_GALAXY} feed the scheduler today. The rest
 * are surfaces that already decide whether the learner was right and then throw that
 * judgement away: translation practice checks a translation, the exam scores an answer,
 * grammar practice will judge a tense. Every one of them is evidence about memory that the
 * scheduler never sees.
 */
public final class ReviewSource {

    private ReviewSource() {
    }

    public static final String CLASSIC_REVIEW = "classic_review";
    public static final String WORD_GALAXY = "word_galaxy";
    public static final String TRANSLATION_PRACTICE = "translation_practice";
    public static final String GRAMMAR_PRACTICE = "grammar_practice";
    public static final String EXAM = "exam";
    public static final String WRITING_PRACTICE = "writing_practice";
    public static final String NEURAL_GAME = "neural_game";

    /** Used when a client sends a grade without naming its surface. */
    public static final String UNSPECIFIED = "unspecified";
}
