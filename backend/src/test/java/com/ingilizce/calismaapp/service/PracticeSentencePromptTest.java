package com.ingilizce.calismaapp.service;

import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Pins the practice-sentence prompt.
 *
 * <p>The golden below started as the exact string the controller built before this prompt was
 * extracted from it, which proved the extraction changed nothing. It now serves the other
 * purpose it was written for: every prompt edit shows up as a diff in review. The last line
 * was added because three consecutive eval runs flagged the same unnatural output — "The
 * train delays commuters" — and the diff is how anyone reading the history can see that a
 * prompt changed and why.
 *
 * <p>A failure here is not necessarily a bug: if the change was intended, update the golden
 * in the same commit. That is the point — a prompt change should be a visible decision, not
 * a line that slipped through inside an unrelated refactor.
 */
class PracticeSentencePromptTest {

    private static final PracticeSentencePrompt.Inputs CANONICAL = new PracticeSentencePrompt.Inputs(
            List.of("delay"),
            Map.of("delay", "gecikme"),
            "SOURCE_TO_TARGET",
            List.of("B1"),
            List.of("short", "medium"),
            List.of("present perfect", "past simple"),
            List.of("The", "She"),
            LearningLanguageProfile.defaultProfile(),
            false,
            0L);

    private static final String GOLDEN = """
            Return EXACTLY 5 natural translation-practice sentences inside a JSON object with key 'sentences'.
            Target word: delay
            Known learner meaning: gecikme
            Every English sentence must use this target word naturally, without quotation marks.
            Practice direction: SOURCE_TO_TARGET
            For source-to-English practice, think of the source-language sentence first, then provide the natural English equivalent. Avoid awkward literal translation.
            Requested level/length combinations:
            - Level: B1, Length: short
            - Level: B1, Length: medium
            Distribute the 5 sentences across these combinations as evenly as possible.
            Soft grammar pattern slots, use when natural:
            - Sentence 1: present perfect
            - Sentence 2: past simple
            Use these real-life context slots exactly once:
            - travel, transport, or appointment
            - work, school, or planning
            - family, friend, or daily life
            - news, public service, or community
            - personal decision, problem, or opinion
            Avoid generic textbook frames and avoid paraphrasing the same idea with tiny wording changes.
            If the word has multiple natural senses/collocations, cover more than one.
            Do NOT write meta sentences about the target word itself. Forbidden frames: "the word ...", "used ... to describe", "explained ...", "heard ...", "practice ...", "remember ...".
            Do not start more than one sentence with a personal pronoun. At least one sentence must be a question.
            This learner has recently seen sentences starting with: The, She. Avoid starting any new sentence with these same words.
            Prefer natural, idiomatic Turkish phrasing that a native speaker would actually write; avoid literal, translated-sounding wording.
            Think in Turkish first for the full-sentence translation, not as a word-for-word translation of the English sentence.
            Lengths must be meaningfully different: short=4-8 words, medium=9-15 words, long=16+ words.
            Good example for target word 'delay': The flight was delayed by heavy rain.
            Bad example for target word 'delay': A short news article used "delay" to describe the problem.
            Give the word the grammatical role and the subject and object a native speaker would give it. A train is delayed; it does not delay commuters. If the natural sentence needs the passive, the past, or a different subject, write it that way rather than forcing the word into the active voice.""";

    @Test
    void thePromptIsExactlyWhatIsPinnedHere() {
        assertEquals(GOLDEN, PracticeSentencePrompt.build(CANONICAL));
    }

    @Test
    void theSameInputsAlwaysProduceTheSameString() {
        // The variation seed is passed in rather than read from the clock, so the prompt is
        // reproducible and the offline eval compares like with like.
        assertEquals(PracticeSentencePrompt.build(CANONICAL), PracticeSentencePrompt.build(CANONICAL));
    }

    @Test
    void multipleTargetWordsSwitchToRotationRules() {
        // One sentence per word, and never the comma-separated list read as one phrase —
        // "Maya noticed evaluate during the trip" is what forcing a list into one sentence
        // looks like.
        String prompt = PracticeSentencePrompt.build(new PracticeSentencePrompt.Inputs(
                List.of("delay", "insight"), Map.of("delay", "gecikme", "insight", "içgörü"),
                "MIXED", List.of("B1"), List.of("short"), List.of(), List.of(),
                LearningLanguageProfile.defaultProfile(), false, 0L));

        assertTrue(prompt.contains("Target words: delay, insight"), prompt);
        assertTrue(prompt.contains("Known learner meanings: delay = gecikme; insight = içgörü"), prompt);
        assertTrue(prompt.contains("exactly ONE target word per sentence"), prompt);
        assertFalse(prompt.contains("Target word: delay\n"), prompt);
    }

    @Test
    void aFreshRequestCarriesItsSeed() {
        String prompt = PracticeSentencePrompt.build(new PracticeSentencePrompt.Inputs(
                List.of("delay"), Map.of(), "SOURCE_TO_TARGET", List.of("B1"), List.of("short"),
                List.of(), List.of(), LearningLanguageProfile.defaultProfile(), true, 12345L));

        assertTrue(prompt.endsWith("variationSeed=12345"), prompt);
        assertTrue(prompt.contains("Generate a fresh new set."), prompt);
    }

    @Test
    void aNonTurkishLearnerIsNotToldToThinkInTurkish() {
        // The app supports other source languages; this branch existed because a Spanish
        // speaker was being handed Turkish translations.
        LearningLanguageProfile spanish =
                new LearningLanguageProfile("Spanish", "English", "Spanish", "B1", "Speaking");

        String prompt = PracticeSentencePrompt.build(new PracticeSentencePrompt.Inputs(
                List.of("delay"), Map.of(), "SOURCE_TO_TARGET", List.of("B1"), List.of("short"),
                List.of(), List.of(), spanish, false, 0L));

        assertTrue(prompt.contains("All source-language translations must be in Spanish"), prompt);
        assertFalse(prompt.contains("Think in Turkish first"), prompt);
    }

    @Test
    void noMeaningMeansNoEmptyHintLine() {
        String prompt = PracticeSentencePrompt.build(new PracticeSentencePrompt.Inputs(
                List.of("delay"), Map.of(), "SOURCE_TO_TARGET", List.of("B1"), List.of("short"),
                List.of(), List.of(), LearningLanguageProfile.defaultProfile(), false, 0L));

        assertFalse(prompt.contains("Known learner meaning:"), prompt);
    }
}
