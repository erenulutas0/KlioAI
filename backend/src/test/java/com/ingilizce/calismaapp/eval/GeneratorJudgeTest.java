package com.ingilizce.calismaapp.eval;

import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * How the judge's own output is read, without spending a token on it.
 *
 * <p>The failure worth guarding here is not a wrong verdict — that is what calibration is
 * for — but a judge whose silence or malformed output reads as approval. That is the shape
 * of the original bug in this codebase: an empty completion counted as a success.
 */
class GeneratorJudgeTest {

    @Test
    void aFailureWithNothingQuotedIsDiscarded() {
        // The judge is told to quote the span that fails. One that cannot is asserting
        // rather than finding, and an eval full of assertions gets ignored within a week.
        List<GeneratorJudge.Verdict> verdicts = GeneratorJudge.parse("""
                {"verdicts":[
                  {"criterion":"natural","passed":false,"evidence":"","reason":"feels off"},
                  {"criterion":"level-appropriate","passed":true,"evidence":"","reason":"fine"}
                ]}
                """);

        assertEquals(1, verdicts.size());
        assertEquals("level-appropriate", verdicts.get(0).criterion());
    }

    @Test
    void aFailureThatQuotesTheContentIsKept() {
        List<GeneratorJudge.Verdict> verdicts = GeneratorJudge.parse("""
                {"verdicts":[{"criterion":"natural","passed":false,
                  "evidence":"Maya noticed evaluate during the trip.",
                  "reason":"the target word is jammed into the wrong slot"}]}
                """);

        assertEquals(1, verdicts.size());
        assertFalse(verdicts.get(0).passed());
        assertTrue(GeneratorJudge.failures(verdicts).get(0).contains("Maya noticed evaluate"));
    }

    @Test
    void anEmptyVerdictListIsAFailureNotAPass() {
        // Nothing came back. That is a broken judge, not clean content.
        assertFalse(GeneratorJudge.parse("{\"verdicts\":[]}").get(0).passed());
    }

    @Test
    void unreadableOutputIsAFailureNotAPass() {
        assertFalse(GeneratorJudge.parse("I think it looks good overall").get(0).passed());
        assertFalse(GeneratorJudge.parse("").get(0).passed());
    }

    @Test
    void aMarkdownFencedVerdictIsStillRead() {
        List<GeneratorJudge.Verdict> verdicts = GeneratorJudge.parse(
                "```json\n{\"verdicts\":[{\"criterion\":\"useful\",\"passed\":true}]}\n```");

        assertTrue(verdicts.get(0).passed());
    }

    @Test
    void contentThatPassesEverythingProducesNoFailureLines() {
        List<GeneratorJudge.Verdict> verdicts = GeneratorJudge.parse("""
                {"verdicts":[
                  {"criterion":"natural","passed":true},
                  {"criterion":"teaches-the-word","passed":true},
                  {"criterion":"level-appropriate","passed":true}
                ]}
                """);

        assertEquals(List.of(), GeneratorJudge.failures(verdicts));
    }
}
