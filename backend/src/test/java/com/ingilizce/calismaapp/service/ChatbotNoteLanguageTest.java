package com.ingilizce.calismaapp.service;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * A correction note the learner can read, or no note.
 *
 * <p>On a device, a Turkish learner who said "I had like to have a cup of coffee" got a card
 * whose note read: "had like" yanlış, "would like" is the correct way to express a wish.
 * The prompt had asked for Turkish in three places and demonstrated it twice; the long
 * English paragraph about what a reason is pulled the reason into English anyway. The
 * prompt now carries a one-line anchor in the note's own language, and that is the fix.
 * This is the net under it: a note that has plainly strayed into English is dropped rather
 * than shown, and the correction it came with is kept.
 *
 * <p>Deterministic, because it runs on every turn and must never invent a problem: only
 * three distinct English function words outside quotation marks count, and the quoted
 * English -- the words being corrected -- never does.
 */
class ChatbotNoteLanguageTest {

    private static ChatbotService.Correction card(String note) {
        return new ChatbotService.Correction("I had like to have", "I would like to have", note);
    }

    @Test
    @DisplayName("the note that shipped is dropped, and the correction is not")
    void theHalfEnglishNoteIsDroppedAlone() {
        ChatbotService.Correction kept = ChatbotService.withoutStrayNote(
                card("\"had like\" yanlış, \"would like\" is the correct way to express a wish."),
                "Turkish");

        assertNull(kept.note());
        assertEquals("I had like to have", kept.said());
        assertEquals("I would like to have", kept.better());
    }

    @Test
    @DisplayName("a note in the learner's language is left exactly as it is")
    void aProperNoteIsUntouched() {
        ChatbotService.Correction original =
                card("\"agree\" tek başına \"katılıyorum\" demek; önüne \"am\" gelmez.");

        assertSame(original, ChatbotService.withoutStrayNote(original, "Turkish"));
    }

    @Test
    @DisplayName("the quoted English is the point, and never counts")
    void quotedEnglishNeverCounts() {
        // Every function word here sits inside quotation marks: it is what is being
        // explained, not the explanation.
        assertFalse(ChatbotService.noteStraysFromLanguage(
                "\"would you like\" ile \"is it for you\" kalıpları nazik isteklerde kullanılır.",
                "Turkish"));
    }

    @Test
    @DisplayName("an English learner's note is English by design")
    void englishLearnersKeepEnglishNotes() {
        assertFalse(ChatbotService.noteStraysFromLanguage(
                "\"I am boring\" means you make other people bored; the word for the feeling is \"bored\".",
                "English"));
    }

    @Test
    @DisplayName("the other languages' own little words do not trip it")
    void noFalsePositivesInTheOtherLanguages() {
        // Each of these is the worked example the prompt itself carries for that language.
        assertFalse(ChatbotService.noteStraysFromLanguage(
                "\"agree\" heißt schon \"zustimmen\"; ein \"am\" davor braucht es nicht.", "German"));
        assertFalse(ChatbotService.noteStraysFromLanguage(
                "\"I am boring\" veut dire que tu ennuies les autres ; le sentiment se dit \"bored\".", "French"));
        assertFalse(ChatbotService.noteStraysFromLanguage(
                "\"agree\" ya significa \"estar de acuerdo\"; no lleva \"am\".", "Spanish"));
        assertFalse(ChatbotService.noteStraysFromLanguage(
                "\"agree\" já quer dizer \"concordar\"; não precisa de \"am\".", "Portuguese"));
        assertFalse(ChatbotService.noteStraysFromLanguage(
                "\"agree\" significa già \"essere d'accordo\"; non serve \"am\".", "Italian"));
    }

    @Test
    @DisplayName("two stray words are not a verdict; three are")
    void theLineIsThreeDistinctWords() {
        assertFalse(ChatbotService.noteStraysFromLanguage(
                "\"is\" fiili the ile kullanılmaz, to da gelmez.", "Turkish"),
                "two English function words in a Turkish sentence happen");
        assertTrue(ChatbotService.noteStraysFromLanguage(
                "Bu yanlış because it is not the correct way to say it.", "Turkish"));
    }

    @Test
    @DisplayName("a short note in English is still English")
    void shortEnglishNotesAreCaught() {
        // 475, on a device: English from end to end, and it passed, because outside the
        // quotes only "is" and "you" were on the list.
        assertTrue(ChatbotService.noteStraysFromLanguage(
                "\"Emi\" is a different name; you meant \"Amy\".", "Turkish"));
        assertTrue(ChatbotService.noteStraysFromLanguage(
                "\"more simpler\" is wrong, native speakers only say \"simpler\".", "Turkish"));
        assertTrue(ChatbotService.noteStraysFromLanguage(
                "This sounds better: \"I'm bored\".", "German"));
    }

    @Test
    @DisplayName("and the notes that shipped in the learner's language still pass")
    void theDeviceNotesInTurkishStillPass() {
        // Every one of these was on a card on a device, in Turkish, and was right.
        assertFalse(ChatbotService.noteStraysFromLanguage(
                "\"complicating\" yerine \"complicated\" kullanılır.", "Turkish"));
        assertFalse(ChatbotService.noteStraysFromLanguage(
                "\"more simpler\" çift karşılaştırma, tek \"simpler\" yeter.", "Turkish"));
        assertFalse(ChatbotService.noteStraysFromLanguage(
                "\"what's\" tek başına \"what is\" demek, burada \"what ... are\" gerekir.", "Turkish"));
        assertFalse(ChatbotService.noteStraysFromLanguage(
                "\"I am boring\" karşındakini sıkıyorsun demek; senin hissettiğin şey \"bored\".", "Turkish"));
        assertFalse(ChatbotService.noteStraysFromLanguage(
                "\"I am boring\" artinya kamu membuat orang lain bosan; perasaannya \"bored\".", "Indonesian"));
    }

    @Test
    @DisplayName("a note with no sign of the learner's language is not in it")
    void aNoteWithoutTheLanguageIsCaught() {
        // 475, on a device, the card after the "Emi" one: not a single English function
        // word outside the quotes, so counting them could never have caught it.
        assertTrue(ChatbotService.noteStraysFromLanguage(
                "\"a\" unnecessary before abstract game terms.", "Turkish"));
        assertTrue(ChatbotService.noteStraysFromLanguage(
                "\"a\" unnecessary before abstract game terms.", "Indonesian"));
    }

    @Test
    @DisplayName("a Turkish note without one Turkish letter still shows its words")
    void turkishWithoutTurkishLettersPasses() {
        assertFalse(ChatbotService.noteStraysFromLanguage(
                "\"a\" burada gereksiz, sadece \"crit\" yeter.", "Turkish"));
    }

    @Test
    @DisplayName("too little outside the quotes to judge is left alone")
    void tooShortToJudge() {
        assertFalse(ChatbotService.noteStraysFromLanguage("\"a\" gereksiz.", "Turkish"));
        assertFalse(ChatbotService.noteStraysFromLanguage("\"a\" extra here.", "Turkish"),
                "two words are not a verdict");
        assertFalse(ChatbotService.noteStraysFromLanguage(
                "\"a\" unnecessary before abstract game terms.", "Japanese"),
                "a language with no signs listed is judged by the English count alone");
    }

    @Test
    @DisplayName("nothing to drop leaves nothing changed")
    void absentNotesAndAbsentCorrectionsPassThrough() {
        ChatbotService.Correction bare = new ChatbotService.Correction("I go", "I went");
        assertSame(bare, ChatbotService.withoutStrayNote(bare, "Turkish"));
        assertNull(ChatbotService.withoutStrayNote(null, "Turkish"));
    }
}
