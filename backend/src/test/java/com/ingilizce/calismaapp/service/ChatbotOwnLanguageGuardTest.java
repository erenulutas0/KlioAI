package com.ingilizce.calismaapp.service;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * The better side of a card is English.
 *
 * <p>Measured on a device: a learner asked for water half in Turkish, the transcript came back
 * with "birasso", and the card offered "bir biras\u0131" -- broken Turkish for "a beer" -- as the
 * right way to say it.
 */
class ChatbotOwnLanguageGuardTest {

    @Test
    void aTurkishBetterWayIsNotEnglish() {
        assertTrue(ChatbotService.bringsInOwnLanguage("bir biras\u0131", "birasso", "Turkish"));
    }

    @Test
    void turkishWordsWithoutTurkishLettersAreStillCaught() {
        // "bir" is on the list of words a Turkish sentence can hardly avoid.
        assertTrue(ChatbotService.bringsInOwnLanguage("bir bira", "birasso", "Turkish"));
    }

    @Test
    void englishIsEnglish() {
        assertFalse(ChatbotService.bringsInOwnLanguage("some water", "biraz su", "Turkish"));
        assertFalse(ChatbotService.bringsInOwnLanguage("I agree", "I am agree", "Turkish"));
    }

    @Test
    void aSignAlreadyInTheirOwnWordsIsTheirs() {
        // Somebody who lives in \u00dcmraniye says so; that is not the model bringing Turkish in.
        assertFalse(ChatbotService.bringsInOwnLanguage(
                "I live in \u00dcmraniye", "I am live in \u00dcmraniye", "Turkish"));
    }

    @Test
    void aLearnerWhoseOwnLanguageIsEnglishHasNothingToBringIn() {
        assertFalse(ChatbotService.bringsInOwnLanguage("bir biras\u0131", "birasso", "English"));
    }
}
