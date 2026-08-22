package com.ingilizce.calismaapp.service;

import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Found on a real device: a reading question answered correctly, marked wrong, with the
 * explanation underneath confirming the choice. The screen grades by the option's position
 * letter, so an answer written out in full matches nothing at all.
 */
class ReadingAnswersTest {

    private static Map<String, Object> question(List<String> options, String answer) {
        return Map.of("question", "Q?", "options", options, "correctAnswer", answer);
    }

    @Test
    void anAnswerGivenAsOptionTextBecomesItsLetter() {
        Map<String, Object> payload = Map.of("questions", List.of(
                question(List.of("Gasoline", "Electric", "Diesel", "Steam"), "Electric")));

        List<?> questions = (List<?>) ReadingAnswers.normalize(payload).get("questions");

        assertEquals("B", ((Map<?, ?>) questions.get(0)).get("correctAnswer"));
    }

    @Test
    void theMatchIgnoresCaseAndSurroundingSpace() {
        Map<String, Object> payload = Map.of("questions", List.of(
                question(List.of("Gasoline", "Electric"), "  electric ")));

        List<?> questions = (List<?>) ReadingAnswers.normalize(payload).get("questions");

        assertEquals("B", ((Map<?, ?>) questions.get(0)).get("correctAnswer"));
    }

    @Test
    void aRealLetterIsLeftExactlyAsItIs() {
        Map<String, Object> payload = Map.of("questions", List.of(
                question(List.of("a", "b", "c", "d"), "C")));

        assertSame(payload, ReadingAnswers.normalize(payload));
    }

    @Test
    void anAnswerMatchingNoOptionIsNotGuessedAt() {
        // A different defect, and one the eval should report rather than this hiding.
        Map<String, Object> payload = Map.of("questions", List.of(
                question(List.of("a", "b", "c", "d"), "something else")));

        List<?> questions = (List<?>) ReadingAnswers.normalize(payload).get("questions");

        assertEquals("something else", ((Map<?, ?>) questions.get(0)).get("correctAnswer"));
    }

    @Test
    void aLetterBeyondTheOptionsIsTreatedAsText() {
        // "D" with two options names nothing, so it is not a letter for this question.
        assertFalse(ReadingAnswers.isLetterInRange("D", 2));
        assertTrue(ReadingAnswers.isLetterInRange("B", 2));
    }

    @Test
    void aPayloadWithNoQuestionsIsReturnedUntouched() {
        assertSame(null, ReadingAnswers.normalize(null));
        Map<String, Object> empty = Map.of("title", "T");
        assertSame(empty, ReadingAnswers.normalize(empty));
    }
}
