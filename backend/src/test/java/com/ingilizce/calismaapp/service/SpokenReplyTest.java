package com.ingilizce.calismaapp.service;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class SpokenReplyTest {

    @Test
    void aShortReplyIsSpokenInOnePiece() {
        SpokenReply.Split split = SpokenReply.of("Of course. A table for two, this way please.");

        assertTrue(split.isWhole());
        assertEquals("Of course. A table for two, this way please.", split.lead());
    }

    @Test
    void aLongReplyIsCutAtItsFirstFullStop() {
        String reply = "I'm afraid the lasagne is sold out tonight. The penne arrabbiata is very "
                + "good though, and the kitchen can have it out to you in a few minutes. Would you "
                + "like me to put that in?";

        SpokenReply.Split split = SpokenReply.of(reply);

        assertFalse(split.isWhole());
        assertEquals("I'm afraid the lasagne is sold out tonight.", split.lead());
        assertTrue(split.rest().startsWith("The penne arrabbiata"));
        assertTrue(split.rest().endsWith("put that in?"));
    }

    @Test
    void theLeadAndTheRestAreTheWholeReply() {
        String reply = "That sounds lovely, thank you very much indeed. I'll bring the bread out "
                + "first, and the wine list is just here if you would like to look at it while you "
                + "decide.";

        SpokenReply.Split split = SpokenReply.of(reply);

        assertFalse(split.isWhole());
        assertEquals(reply, (split.lead() + " " + split.rest()).trim());
    }

    @Test
    void anOpenerTooShortToBeWorthASeamIsKeptWithWhatFollows() {
        // "Of course!" is under a second of speech; cutting there would have the learner hear
        // it and then wait again, which is the very thing the split is meant to remove.
        String reply = "Of course! The kitchen is still open for another hour, so there is no "
                + "rush at all. Take your time with the menu and wave me over when you are ready.";

        SpokenReply.Split split = SpokenReply.of(reply);

        assertEquals("Of course! The kitchen is still open for another hour, so there is no rush at all.",
                split.lead());
    }

    @Test
    void aTitleIsNotAFullStop() {
        String reply = "Let me check with the kitchen for you, Mr. Rossi. It should only take a "
                + "moment, and I will come straight back with an answer about the table by the window.";

        SpokenReply.Split split = SpokenReply.of(reply);

        assertEquals("Let me check with the kitchen for you, Mr. Rossi.", split.lead());
    }

    @Test
    void aLongReplyWithNoFullStopIsSpokenInOnePiece() {
        String reply = "well I was thinking we could go to the market first and then walk down "
                + "to the harbour and see whether that little place with the blue tables is open today";

        SpokenReply.Split split = SpokenReply.of(reply);

        assertTrue(split.isWhole());
        assertEquals(reply, split.lead());
    }

    @Test
    void aTrailingFragmentIsNotWorthASeamEither() {
        // The seam has to buy time: a remainder of a few words is synthesised in the gap
        // between the two clips anyway, and only adds a pause where none belongs.
        String reply = "I completely understand, and I am sorry about the wait -- the kitchen had "
                + "a very busy half hour just before you arrived, which is no excuse at all. Sorry.";

        SpokenReply.Split split = SpokenReply.of(reply);

        assertTrue(split.isWhole());
    }

    /**
     * The replies the tutor actually sends are split too.
     *
     * <p>The first threshold was 140 characters, set before the prompt was tightened. Measured
     * on the server afterwards, real replies came in at 125 to 180 -- so most of them fell
     * under it and paid the full 2.3 to 2.5 seconds, while the one that did split answered in
     * 871 ms. The threshold was the bug.
     */
    @Test
    void aReplyOfTheLengthTheTutorActuallySendsIsSplit() {
        String reply = "Good evening! Of course, we have a lovely table by the window. "
                + "Would you like to see the wine list while you settle in?";

        SpokenReply.Split split = SpokenReply.of(reply);

        assertFalse(split.isWhole());
        assertEquals("Good evening! Of course, we have a lovely table by the window.", split.lead());
    }

    /**
     * A long reply needs a longer opening, not the same one.
     *
     * <p>The opening has to keep playing until the remainder has been made. A fixed floor that
     * suits a short reply leaves a long one silent in the middle, so the floor rises with the
     * length: here the first sentence is past the old 40 and still too thin.
     */
    @Test
    void aLongReplyGetsAnOpeningLongEnoughToCoverTheRest() {
        String reply = "I am so sorry about that. The kitchen has been under real pressure "
                + "since a large party arrived just before you did, and your main course is "
                + "plated and coming out to you right now. Can I bring you anything while you "
                + "wait, on the house?";

        SpokenReply.Split split = SpokenReply.of(reply);

        assertFalse(split.isWhole());
        assertTrue(split.lead().length() >= reply.length() / 5,
                "an opening that runs out before the rest arrives is a silence mid-reply: "
                        + split.lead().length() + " of " + reply.length());
        // Not the first sentence: "I am so sorry about that." is 25 characters, which would
        // have run out well before the remaining 228 had been synthesised. The second sentence
        // is far too long to wait for, so the cut lands at its comma.
        assertTrue(split.lead().endsWith("just before you did,"), split.lead());
    }

    /**
     * An opening sentence too long to wait for is cut at a comma.
     *
     * <p>Two replies in one conversation opened with a 121- and a 131-character sentence, and
     * speaking those cost 2.0 s where the short openings in the same conversation cost 0.86 s.
     * There was no full stop to use. A comma is where the speaker was going to pause anyway,
     * and a pause there is less noticeable than two seconds of nothing.
     */
    @Test
    void anOpeningSentenceTooLongToWaitForIsCutWhereTheSpeakerBreathes() {
        // Shaped like the replies that were measured at 2.0 s: a 129-character opening
        // sentence inside a 158-character reply, with nowhere to cut but a comma.
        String reply = "I would honestly recommend the seafood risotto tonight, because the fish "
                + "came in this morning and the kitchen is very proud of it. Does that sound good "
                + "to you?";

        SpokenReply.Split split = SpokenReply.of(reply);

        assertEquals("I would honestly recommend the seafood risotto tonight,", split.lead());
        assertTrue(split.rest().startsWith("because the fish"));
    }

    @Test
    void anOpeningSentenceShortEnoughIsLeftWhole() {
        // The comma is there, but the full stop comes soon enough that cutting at the comma
        // would buy nothing and cost a seam mid-sentence.
        String reply = "Yes, of course, we have a table by the window. The kitchen is still "
                + "open for another hour, so there is no rush at all.";

        SpokenReply.Split split = SpokenReply.of(reply);

        assertEquals("Yes, of course, we have a table by the window.", split.lead());
    }

    @Test
    void nothingToSayIsNotACrash() {
        assertEquals(new SpokenReply.Split("", ""), SpokenReply.of(null));
        assertEquals(new SpokenReply.Split("", ""), SpokenReply.of("   "));
    }
}
