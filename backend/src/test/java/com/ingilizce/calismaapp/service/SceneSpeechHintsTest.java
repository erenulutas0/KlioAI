package com.ingilizce.calismaapp.service;

import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * What a scene tells the speech recogniser about itself.
 *
 * <p>Whisper's prompt biases spelling, and the words worth biasing are the ones a learner says
 * in this scene and nowhere else. What these pin is that the distinctive words get through and
 * the scene's ordinary English does not -- a hint padded with "evening" and "something" is a
 * hint that has spent its room on words that were never at risk.
 */
class SceneSpeechHintsTest {

    private final ScenarioCatalog catalog = ScenarioCatalog.bundled();

    @Test
    void theCharactersNameComesFirst() {
        ScenarioCatalog.Scene restaurant = catalog.find("restaurant_order").orElseThrow();

        assertEquals("Luca", restaurant.speechHints().get(0));
    }

    @Test
    void theWordsTheSceneTurnsOnAreThere() {
        List<String> hints = catalog.find("restaurant_order").orElseThrow().speechHints();

        // The dish is in the scene's own examples, it is what the learner is about to order,
        // and it is not a word any recogniser gets right without being told.
        assertTrue(hints.stream().anyMatch(word -> word.equalsIgnoreCase("lasagne")), hints.toString());
    }

    @Test
    void theSceneOrdinaryEnglishIsNot() {
        List<String> hints = catalog.find("restaurant_order").orElseThrow().speechHints();

        for (String common : List.of("evening", "something", "everything", "about", "tonight")) {
            assertFalse(hints.stream().anyMatch(word -> word.equalsIgnoreCase(common)),
                    common + " spent one of the twelve on a word that was never at risk: " + hints);
        }
    }

    @Test
    void everyPlayableSceneHasHintsAndNoneOverrunsTheCap() {
        for (ScenarioCatalog.Scene scene : catalog.scenes()) {
            List<String> hints = scene.speechHints();
            assertFalse(hints.isEmpty(), scene.id() + " gives the recogniser nothing");
            assertTrue(hints.size() <= SceneSpeechHints.MAX_HINTS,
                    scene.id() + " sends " + hints.size());
            // The name is exempt from the length rule and nothing else is: Tom, Ben and Sam
            // are three letters long and are still the word the learner is about to say.
            List<String> nameWords = List.of(scene.character().toLowerCase().split("[^a-z]+"));
            for (String hint : hints) {
                // One word each. The prompt is a list of spellings; a phrase in it reads as
                // prose, which is the failure the Whisper prompt comment warns about.
                assertFalse(hint.contains(" "), scene.id() + " sent a phrase: " + hint);
                assertFalse(hint.contains("'"),
                        scene.id() + " spent a slot on a contraction: " + hint);
                assertTrue(hint.length() >= 4 || nameWords.contains(hint.toLowerCase()),
                        scene.id() + " sent a short word that is not its character: " + hint);
            }
        }
    }

    @Test
    void theSameWordIsNotSentTwiceForItsCapitals() {
        for (ScenarioCatalog.Scene scene : catalog.scenes()) {
            List<String> lowered = scene.speechHints().stream().map(String::toLowerCase).toList();

            assertEquals(lowered.size(), lowered.stream().distinct().count(),
                    scene.id() + " repeats itself: " + scene.speechHints());
        }
    }

    @Test
    void noSceneIsNotACrash() {
        assertEquals(List.of(), SceneSpeechHints.of(null));
    }
}
