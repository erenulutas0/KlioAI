package com.ingilizce.calismaapp.service;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Whisper does not return nothing when it hears nothing.
 *
 * <p>Handed a four-second recording of an empty room, it returned: "English learning
 * conversation. Transcribe or the stream of language can be seen in general. Transcription
 * by CastingWords. You can still explain your presence in learning..." — fluent, confident,
 * and entirely invented from the subtitle files in its training data.
 *
 * <p>The speaking screen auto-sends the transcript the moment it arrives, so a learner who
 * taps the microphone and hesitates gets words put in their mouth, watches the tutor answer
 * a question they never asked, and pays for it from their daily token budget. Somebody
 * learning the language cannot tell "the app misheard me" from "I said it wrong", which
 * makes this a worse failure here than in most places.
 */
class SilenceHallucinationTest {

    @Test
    void theTranscriptSilenceActuallyProduced() {
        // Captured from a real recording of a quiet room on a physical device.
        assertTrue(GroqSpeechToTextService.isHallucinatedSilence(
                "English learning conversation. Transcribe or the stream of language can be "
                        + "seen in general. Transcription by CastingWords You can still explain "
                        + "your presence in learning but also if you like to explain your "
                        + "business Thank you."));
    }

    @Test
    void theUsualSubtitleBoilerplateIsRejected() {
        assertTrue(GroqSpeechToTextService.isHallucinatedSilence("Subtitles by the Amara.org community"));
        assertTrue(GroqSpeechToTextService.isHallucinatedSilence("Thanks for watching!"));
        assertTrue(GroqSpeechToTextService.isHallucinatedSilence("Please subscribe to the channel"));
        assertTrue(GroqSpeechToTextService.isHallucinatedSilence("[Music]"));
        assertTrue(GroqSpeechToTextService.isHallucinatedSilence("Altyazı M.K."));
    }

    @Test
    void nothingAndPunctuationAreNotSpeech() {
        assertTrue(GroqSpeechToTextService.isHallucinatedSilence(null));
        assertTrue(GroqSpeechToTextService.isHallucinatedSilence("   "));
        assertTrue(GroqSpeechToTextService.isHallucinatedSilence("..."));
        assertTrue(GroqSpeechToTextService.isHallucinatedSilence("?!"));
    }

    @Test
    void realSpeechIsLeftAlone() {
        // The list stays narrow on purpose. A false positive silently deletes something the
        // learner actually said, which is the failure this exists to prevent — so anything
        // that is not unmistakably boilerplate has to pass through.
        assertFalse(GroqSpeechToTextService.isHallucinatedSilence("Hello, my name is Eren."));
        assertFalse(GroqSpeechToTextService.isHallucinatedSilence(
                "I usually spend my weekends watching films with my family."));
        assertFalse(GroqSpeechToTextService.isHallucinatedSilence("Thank you."));
        assertFalse(GroqSpeechToTextService.isHallucinatedSilence(
                "I want to talk about my business trip to London."));
    }

    @Test
    void theModelsOwnConfidenceCatchesWhatWordingCannot() {
        // The marker list caught the subtitle boilerplate, and the very next recording of
        // the same silent room came back as "Thank you." — also a common Whisper silence
        // output, and also something a learner might genuinely say. No wording separates
        // those two. no_speech_prob does.
        assertTrue(GroqSpeechToTextService.segmentsLookLikeSilence(java.util.List.of(
                java.util.Map.of("no_speech_prob", 0.94, "avg_logprob", -1.7))));
    }

    @Test
    void aQuietButRealAttemptSurvives() {
        // Both thresholds have to trip. High no-speech probability on its own fires on
        // quiet speech; a poor log-probability on its own fires on a strong accent — which
        // is most of this app's audience.
        assertFalse(GroqSpeechToTextService.segmentsLookLikeSilence(java.util.List.of(
                java.util.Map.of("no_speech_prob", 0.91, "avg_logprob", -0.4))));
        assertFalse(GroqSpeechToTextService.segmentsLookLikeSilence(java.util.List.of(
                java.util.Map.of("no_speech_prob", 0.10, "avg_logprob", -1.9))));
    }

    @Test
    void oneRealSegmentKeepsTheWholeTranscript() {
        assertFalse(GroqSpeechToTextService.segmentsLookLikeSilence(java.util.List.of(
                java.util.Map.of("no_speech_prob", 0.95, "avg_logprob", -1.8),
                java.util.Map.of("no_speech_prob", 0.02, "avg_logprob", -0.3))));
    }

    @Test
    void missingConfidenceFieldsAreNotTreatedAsSilence() {
        // Absent data is not evidence of silence. Deleting a learner's words because the
        // provider changed its response shape would be the worse failure.
        assertFalse(GroqSpeechToTextService.segmentsLookLikeSilence(java.util.List.of(
                java.util.Map.of("text", "hello"))));
        assertFalse(GroqSpeechToTextService.segmentsLookLikeSilence(java.util.List.of()));
        assertFalse(GroqSpeechToTextService.segmentsLookLikeSilence(null));
    }
}
