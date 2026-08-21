package com.ingilizce.calismaapp.service;

import java.util.Locale;
import java.util.regex.Pattern;

/**
 * Whether a piece of text actually uses a given word.
 *
 * <p>Shared deliberately. Two callers need this and they must agree: the grammar quiz
 * blanks out a targetWord the question does not use, and the offline eval reports the same
 * condition as a failure. If those two drifted apart, the eval would pass content the
 * server had already decided was mislabelled, or flag content it had just repaired — and
 * one fact answered differently in two places is the bug that keeps recurring in this
 * codebase.
 */
public final class WordForms {

    private WordForms() {}

    /**
     * Allows ordinary inflection, not derivation.
     *
     * <p>"evaluate" has to match "evaluated" and "evaluating", or correct sentences get
     * reported as broken and people stop reading the report. A bare substring is too loose
     * in the other direction — "all" inside "usually" — so the match is anchored on word
     * boundaries with a short suffix allowance.
     *
     * <p>The allowance stops short of derived forms on purpose: "resilience" is a different
     * word from "resilient", and crediting the learner's saved word for a question that
     * tested another one is the thing being prevented.
     */
    public static boolean contains(String haystack, String word) {
        if (haystack == null || word == null) {
            return false;
        }
        String stem = word.trim().toLowerCase(Locale.ROOT);
        if (stem.isEmpty()) {
            return true;
        }
        // Drop a trailing 'e' so "evaluate" also matches "evaluating".
        String root = stem.endsWith("e") && stem.length() > 3 ? stem.substring(0, stem.length() - 1) : stem;
        return Pattern.compile("(?i)\\b" + Pattern.quote(root) + "\\w{0,3}\\b").matcher(haystack).find();
    }
}
