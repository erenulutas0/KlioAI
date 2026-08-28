package com.ingilizce.calismaapp.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

/**
 * Pulling the correction out of a spoken turn's reply.
 *
 * <p>Everything here is about one asymmetry. The correction is asked for as a marked
 * final line rather than by making the whole turn JSON, because the two fail differently:
 * bad JSON costs the REPLY and leaves a conversation answering with a canned fallback,
 * while a bad marker costs only the correction. So every malformed case below has the
 * same required outcome — no correction, and a reply the learner would not know was ever
 * supposed to carry one.
 *
 * <p>The other half is that the marker must never reach the screen. A model that says
 * "[[FIX]]" out loud in the middle of a sentence has not produced a correction, but it
 * has produced something a learner will read.
 */
class ChatbotCorrectionTest {

    @Nested
    @DisplayName("a correction is found")
    class Found {

        @Test
        @DisplayName("on a final marked line")
        void trailingLine() {
            String content = "That sounds lovely! Where did you go?\n"
                    + "[[FIX]] I go to Paris yesterday -> I went to Paris yesterday";

            ChatbotService.Correction correction = ChatbotService.extractCorrection(content);

            assertNotNull(correction);
            assertEquals("I go to Paris yesterday", correction.said());
            assertEquals("I went to Paris yesterday", correction.better());
        }

        @Test
        @DisplayName("and the reply keeps none of it")
        void replyIsClean() {
            String content = "That sounds lovely! Where did you go?\n"
                    + "[[FIX]] I go -> I went";

            assertEquals("That sounds lovely! Where did you go?",
                    ChatbotService.stripCorrection(content));
        }

        @Test
        @DisplayName("even when the model repeats itself, taking the last word")
        void lastMarkerWins() {
            // A model that corrects twice has replaced its own first answer. Taking the
            // first would show the learner something the model went on to think better of.
            String content = "Nice.\n[[FIX]] a -> b\n[[FIX]] I has -> I have";

            ChatbotService.Correction correction = ChatbotService.extractCorrection(content);

            assertNotNull(correction);
            assertEquals("I have", correction.better());
            assertEquals("Nice.", ChatbotService.stripCorrection(content));
        }

        @Test
        @DisplayName("mid-line, where models often put it")
        void markerNotAtLineStart() {
            // Models put the marker after a bullet, after a space, or on the end of the
            // sentence they just finished. Refusing to read it there left the raw
            // "I go -> I went" sitting in the reply, on screen and read aloud.
            String content = "Nice work. [[FIX]] I go -> I went";

            ChatbotService.Correction correction = ChatbotService.extractCorrection(content);

            assertNotNull(correction);
            assertEquals("I go", correction.said());
            assertEquals("I went", correction.better());
            assertEquals("Nice work.", ChatbotService.stripCorrection(content));
        }
    }

    @Nested
    @DisplayName("nothing is invented")
    class NotFound {

        @Test
        @DisplayName("when the model simply did not correct")
        void noMarker() {
            String content = "That sounds lovely! Where did you go?";

            assertNull(ChatbotService.extractCorrection(content));
            assertEquals(content, ChatbotService.stripCorrection(content));
        }

        @Test
        @DisplayName("when the marker line has no arrow")
        void noSeparator() {
            String content = "Nice.\n[[FIX]] I went to Paris yesterday";

            assertNull(ChatbotService.extractCorrection(content));
            assertEquals("Nice.", ChatbotService.stripCorrection(content),
                    "a malformed marker must still not reach the screen");
        }

        @Test
        @DisplayName("when a second arrow makes the halves ambiguous")
        void twoArrows() {
            // "the sign say A -> B" corrected to "the sign says A -> B" is a real
            // sentence a learner could say, and nothing in the line says which arrow
            // divides it. Either split produces a confident wrong answer, so this
            // degrades like every other malformed case: no correction.
            //
            // The test that stood here asserted only the half that happened to come
            // out right, which is how the other half stayed wrong.
            String content = "Sure.\n[[FIX]] the sign say A -> B -> the sign says A -> B";

            assertNull(ChatbotService.extractCorrection(content));
            assertEquals("Sure.", ChatbotService.stripCorrection(content),
                    "an unreadable correction must still not reach the screen");
        }

        @Test
        @DisplayName("when either half is empty")
        void emptyHalf() {
            assertNull(ChatbotService.extractCorrection("Nice.\n[[FIX]]  -> I went"));
            assertNull(ChatbotService.extractCorrection("Nice.\n[[FIX]] I go -> "));
        }

        @Test
        @DisplayName("when the two halves are the same")
        void nothingChanged() {
            // "Corrected" to what they already said. Showing that teaches nothing and
            // tells the learner they were wrong when they were not.
            assertNull(ChatbotService.extractCorrection("Nice.\n[[FIX]] I went -> I went"));
        }

        @Test
        @DisplayName("when the line runs away")
        void tooLong() {
            String runaway = "x".repeat(400);
            assertNull(ChatbotService.extractCorrection("Nice.\n[[FIX]] I go -> " + runaway));
        }

        @Test
        @DisplayName("on a null completion")
        void nullContent() {
            assertNull(ChatbotService.extractCorrection(null));
            assertNull(ChatbotService.stripCorrection(null));
        }
    }

    @Nested
    @DisplayName("the marker never reaches the learner")
    class NeverLeaks {

        @Test
        @DisplayName("with nothing usable after it")
        void markerWithoutACorrection() {
            String content = "You could say [[FIX]] here, but it is fine.";

            assertNull(ChatbotService.extractCorrection(content));
            // Everything from the marker onward is dropped, including the words after
            // it. The model lost the thread at the marker, and half a sentence beats a
            // sentence with a correction format in the middle of it.
            assertEquals("You could say", ChatbotService.stripCorrection(content));
        }

        @Test
        @DisplayName("when the whole reply is the marker and nothing else")
        void onlyAMarker() {
            // The reply is then empty. This comment used to say the speaking screen
            // handled that. It did not: it appended a blank bubble with a play button
            // that read out nothing. The screen skips it now, and this assertion is
            // only about what this method returns.
            assertEquals("", ChatbotService.stripCorrection("[[FIX]] a -> b"));
        }

        @Test
        @DisplayName("with indentation in front of it")
        void indentedMarker() {
            String content = "Nice.\n   [[FIX]] I go -> I went";

            assertNotNull(ChatbotService.extractCorrection(content));
            assertTrue(ChatbotService.stripCorrection(content).equals("Nice."));
        }
    }
}
