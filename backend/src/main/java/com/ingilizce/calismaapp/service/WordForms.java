package com.ingilizce.calismaapp.service;

import java.util.Locale;
import java.util.LinkedHashSet;
import java.util.Set;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

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
        String alternation = inflectionsOf(stem).stream()
                .map(Pattern::quote)
                .collect(Collectors.joining("|"));
        return Pattern.compile("(?i)" + BOUNDARY + "(?:" + alternation + ")" + BOUNDARY)
                .matcher(haystack)
                .find();
    }

    private static final String BOUNDARY = "\\b";

    /**
     * The forms of a word a sentence may legitimately use.
     *
     * <p>Spelled out rather than approximated with a suffix wildcard. The wildcard version
     * matched "evaluate" to "evaluated" but missed "qualify" in "He qualified for the next
     * round", because the y becomes an i and the shared prefix ends early - the eval caught
     * a perfectly good example sentence being reported as not containing its own word.
     * Widening the wildcard to cover it would have started matching unrelated words, and
     * this list is both stricter and easier to reason about.
     */
    static Set<String> inflectionsOf(String stem) {
        Set<String> forms = new LinkedHashSet<>();
        forms.add(stem);
        forms.add(stem + "s");
        forms.add(stem + "es");
        forms.add(stem + "ed");
        forms.add(stem + "ing");
        forms.add(stem + "er");
        forms.add(stem + "est");
        if (stem.length() > 3 && stem.endsWith("e")) {
            String root = stem.substring(0, stem.length() - 1);
            forms.add(root + "ed");
            forms.add(root + "es");
            forms.add(root + "ing");
            forms.add(root + "er");
            forms.add(root + "est");
        }
        // study -> studied, qualify -> qualified, carry -> carries.
        if (stem.length() > 3 && stem.endsWith("y") && !isVowel(stem.charAt(stem.length() - 2))) {
            String root = stem.substring(0, stem.length() - 1);
            forms.add(root + "ies");
            forms.add(root + "ied");
            forms.add(root + "ier");
            forms.add(root + "iest");
        }
        return forms;
    }

    private static boolean isVowel(char c) {
        return "aeiou".indexOf(Character.toLowerCase(c)) >= 0;
    }
}
