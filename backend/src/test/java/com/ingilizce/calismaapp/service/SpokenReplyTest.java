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

    @Test
    void nothingToSayIsNotACrash() {
        assertEquals(new SpokenReply.Split("", ""), SpokenReply.of(null));
        assertEquals(new SpokenReply.Split("", ""), SpokenReply.of("   "));
    }
}
