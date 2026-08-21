package com.ingilizce.calismaapp.service;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Whether a sentence uses a word, in both directions that matter.
 *
 * <p>A false negative clears a targetWord the question legitimately used, so the learner
 * loses the review credit they earned. A false positive credits a word the question never
 * tested. Both are quiet, so both need cases here.
 */
class WordFormsTest {

    @Test
    void ordinaryInflectionCounts() {
        assertTrue(WordForms.contains("The team evaluated three suppliers.", "evaluate"));
        assertTrue(WordForms.contains("She is evaluating the offer.", "evaluate"));
        assertTrue(WordForms.contains("The flight was delayed by rain.", "delay"));
        assertTrue(WordForms.contains("Her insights changed the plan.", "insight"));
    }

    @Test
    void theYToIInflectionCounts() {
        // Caught by a live eval run: "qualify" was reported as missing from "He qualified
        // for the next round", because the shared prefix ends where the y becomes an i.
        assertTrue(WordForms.contains("He qualified for the next round.", "qualify"));
        assertTrue(WordForms.contains("She studied all evening.", "study"));
        assertTrue(WordForms.contains("He carries the bag.", "carry"));
    }

    @Test
    void aDifferentWordDoesNotCount() {
        // "resilience" is not "resilient": crediting the learner's saved word for a
        // question that tested another one is the thing being prevented.
        assertFalse(WordForms.contains("They showed great resilience.", "resilient"));
        assertFalse(WordForms.contains("She usually walks to work.", "all"));
        assertFalse(WordForms.contains("The project has included many changes.", "mitigate"));
    }

    @Test
    void anEmptyWordIsNotAClaim() {
        // No target word means nothing to verify, not a failure.
        assertTrue(WordForms.contains("Anything at all.", ""));
        assertTrue(WordForms.contains("Anything at all.", "   "));
    }

    @Test
    void aMissingSentenceIsNotAMatch() {
        assertFalse(WordForms.contains(null, "delay"));
        assertFalse(WordForms.contains("The flight was delayed.", null));
    }
}
