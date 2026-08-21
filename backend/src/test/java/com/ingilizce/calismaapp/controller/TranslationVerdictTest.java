package com.ingilizce.calismaapp.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.lang.reflect.Method;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Reading the verdict on a learner's translation.
 *
 * <p>This grades the learner's own work and writes the outcome to the spaced-repetition
 * scheduler, so a wrong verdict is not a cosmetic bug: a wrong answer marked right suppresses
 * the correction and lengthens the review interval for a word they had just failed.
 *
 * <p>The version these tests replaced inferred the verdict from the text whenever the payload
 * was not JSON, and the inference defaulted to correct.
 */
class TranslationVerdictTest {

    private final ChatbotController controller = new ChatbotController();

    private Map<String, Object> parse(String response) throws Exception {
        ReflectionTestUtils.setField(controller, "objectMapper", new ObjectMapper());
        Method method = ChatbotController.class.getDeclaredMethod("parseJsonResponse", String.class);
        method.setAccessible(true);
        @SuppressWarnings("unchecked")
        Map<String, Object> result = (Map<String, Object>) method.invoke(controller, response);
        return result;
    }

    @Test
    void aBlankReplyReportsNoVerdictRatherThanCorrect() throws Exception {
        // The worst case, and the one that shipped. With an empty string every contains()
        // probe was false, so the negated clause returned true and the learner's answer was
        // marked correct by a check that had read nothing at all.
        assertFalse(parse("").containsKey("isCorrect"));
        assertFalse(parse(null).containsKey("isCorrect"));
        assertFalse(parse("   ").containsKey("isCorrect"));
    }

    @Test
    void feedbackNamingTheCorrectTranslationIsNotItselfAVerdict() throws Exception {
        // The feedback a WRONG answer gets begins "Doğru çeviri:" - the correct translation
        // being exactly what a wrong answer is shown. The old check matched "doğru" anywhere
        // in the reply and marked it right.
        assertFalse(parse("Doğru çeviri: The flight was delayed.").containsKey("isCorrect"));
    }

    @Test
    void prosePastTheJsonModeRetryReportsNoVerdict() throws Exception {
        assertFalse(parse("I think the learner's translation is fine overall.").containsKey("isCorrect"));
    }

    @Test
    void aRealVerdictIsReadInBothDirections() throws Exception {
        Map<String, Object> right = parse(
                "{\"isCorrect\": true, \"correctTranslation\": \"\", \"feedback\": \"Tam isabet.\"}");
        assertEquals(true, right.get("isCorrect"));

        Map<String, Object> wrong = parse(
                "{\"isCorrect\": false, \"correctTranslation\": \"The flight was delayed.\","
                        + " \"feedback\": \"Zaman uyumu eksik.\"}");
        assertEquals(false, wrong.get("isCorrect"));
        assertEquals("The flight was delayed.", wrong.get("correctTranslation"));
    }

    @Test
    void aQuotedTokenInTheFeedbackNoLongerTruncatesTheExplanation() throws Exception {
        // The prompt asks the model to name the transfer-error pattern, and the patterns it
        // is given are quoted tokens - "a/an/the", "do/does". The old regex ("([^"]+)")
        // could not cross an escaped quote, so the explanation of the learner's mistake was
        // cut off mid-sentence on exactly the answers they got wrong.
        Map<String, Object> result = parse(
                "{\"isCorrect\": false, \"correctTranslation\": \"He is a teacher.\","
                        + " \"feedback\": \"Türkçede artikel yok, bu yüzden \\\"a/an/the\\\" atlanıyor.\"}");

        String feedback = result.get("feedback").toString();
        assertTrue(feedback.endsWith("atlanıyor."), feedback);
        assertTrue(feedback.contains("a/an/the"), feedback);
    }

    @Test
    void aMarkdownFencedPayloadIsStillRead() throws Exception {
        Map<String, Object> result = parse("```json\n{\"isCorrect\": false, \"feedback\": \"Eksik.\"}\n```");
        assertEquals(false, result.get("isCorrect"));
    }
}
