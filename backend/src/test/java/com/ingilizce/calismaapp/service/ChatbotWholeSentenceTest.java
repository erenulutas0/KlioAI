package com.ingilizce.calismaapp.service;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.lang.reflect.Method;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * A correction card that shows the whole sentence fixed, and the changes that matter.
 *
 * <p>A tester at B2 said "This is complicating more. Why don't you explain what is steamed
 * milk and latte more simpler and more specific like how is it prepared in a broader term"
 * -- five mistakes -- and the card showed one: "more simpler" -> "simpler". He read it,
 * fairly, as the other four being fine. The prompt asked for "one clear mistake" and "one
 * line at most, ever", and the parser took the last marker it found.
 *
 * <p>The card now leads with the learner's whole message corrected and lists up to as many
 * changes as their level holds. These pin the parsing of both kinds of line, the one rule
 * that matters most -- neither may ever be read aloud -- and what the prompt asks for.
 */
class ChatbotWholeSentenceTest {

    private static String fixInstructions(String level) throws Exception {
        Method method =
                ChatbotService.class.getDeclaredMethod("fixInstructions", LearningLanguageProfile.class);
        method.setAccessible(true);
        return (String) method.invoke(null,
                LearningLanguageProfile.of("Turkish", "English", "Turkish", level, "Speaking"));
    }

    private static final String CARD = "Sure!\n"
            + "[[FIX]] This is complicating more -> This is getting more complicated || n1\n"
            + "[[FIX]] more simpler -> more simply || n2\n"
            + "[[SENTENCE]] This is getting more complicated. Explain it more simply.";

    @Test
    @DisplayName("every correction is read, the most important first")
    void everyLineInOrder() {
        List<ChatbotService.Correction> found = ChatbotService.extractCorrections(CARD);

        assertEquals(2, found.size());
        assertEquals("This is getting more complicated", found.get(0).better());
        assertEquals("n1", found.get(0).note());
        assertEquals("more simply", found.get(1).better());
        assertEquals(found.get(0), ChatbotService.extractCorrection(CARD),
                "the single correction the API has always sent is the first");
    }

    @Test
    @DisplayName("a broken line costs only itself")
    void aBadLineIsSkipped() {
        // Two arrows cannot be split without guessing. That line goes; the good one stays.
        List<ChatbotService.Correction> found =
                ChatbotService.extractCorrections("Sure!\n[[FIX]] a -> b -> c\n[[FIX]] I go -> I went");

        assertEquals(1, found.size());
        assertEquals("I went", found.get(0).better());
    }

    @Test
    @DisplayName("the whole sentence is read off its own line")
    void theSentenceIsRead() {
        assertEquals("This is getting more complicated. Explain it more simply.",
                ChatbotService.extractCorrectedSentence(CARD));
        assertEquals("I went home.",
                ChatbotService.extractCorrectedSentence("Sure!\n[[SENTENCE]] \"I went home.\""),
                "quotation marks around it are the model's, not the learner's");
        assertEquals("I went home.",
                ChatbotService.extractCorrectedSentence("[[SENTENCE]] I go home.\n[[SENTENCE]] I went home."),
                "a revised sentence replaces the first, as a revised correction does");
        assertNull(ChatbotService.extractCorrectedSentence("Sure!\n[[FIX]] I go -> I went"));
        assertNull(ChatbotService.extractCorrectedSentence("[[SENTENCE]] " + "x".repeat(401)),
                "a paragraph has left the format");
    }

    @Test
    @DisplayName("neither kind of line is ever read aloud")
    void nothingReachesTheVoice() {
        // The sentence line matters most here: it is fluent English, so left behind it would
        // not look like debris -- the tutor would simply say it, as if it were her own.
        assertEquals("Sure!", ChatbotService.stripCorrection(CARD));
        assertEquals("Nice.", ChatbotService.stripCorrection("Nice. [[SENTENCE]] I went home."));
    }

    @Test
    @DisplayName("a sentence on the same line as a correction is kept out of its note")
    void sameLineSplits() {
        String content = "Sure!\n[[FIX]] I go -> I went || n1 [[SENTENCE]] I went home.";

        assertEquals("n1", ChatbotService.extractCorrection(content).note());
        assertEquals("I went home.", ChatbotService.extractCorrectedSentence(content));
        assertEquals("Sure!", ChatbotService.stripCorrection(content));
    }

    @Test
    @DisplayName("the same words are the same, whatever the punctuation")
    void sameWords() {
        assertTrue(ChatbotService.sameWords("I go home.", "i go  home"));
        assertFalse(ChatbotService.sameWords("I go home", "I went home"));
        assertFalse(ChatbotService.sameWords(null, "I go home"));
    }

    @Test
    @DisplayName("a card holds one correction below B1, two at B1, three above")
    void theCapFollowsTheLevel() {
        assertEquals(1, ChatbotService.maxChanges("A1"));
        assertEquals(1, ChatbotService.maxChanges("A2"));
        assertEquals(2, ChatbotService.maxChanges("B1"));
        assertEquals(3, ChatbotService.maxChanges("B2"));
        assertEquals(3, ChatbotService.maxChanges("C1"));
        assertEquals(3, ChatbotService.maxChanges("C2"));
    }

    @Test
    @DisplayName("the prompt asks for as many lines as the card holds")
    void thePromptStatesTheCap() throws Exception {
        assertTrue(fixInstructions("A1").contains("never more than 1"));
        assertTrue(fixInstructions("B1").contains("never more than 2"));
        assertTrue(fixInstructions("B2").contains("never more than 3"));
        assertFalse(fixInstructions("B2").contains("One line at most"),
                "the old ceiling is gone");
    }

    @Test
    @DisplayName("and for the whole sentence, as theirs fixed rather than a better one")
    void thePromptAsksForTheirSentence() throws Exception {
        String text = fixInstructions("B2");

        assertTrue(text.contains("[[SENTENCE]] the whole message, corrected"));
        // Not a rewrite: a learner shown a more elegant sentence than the one they tried
        // to say cannot see which of the differences were mistakes.
        assertTrue(text.contains("their sentence fixed, not a better sentence"));
        assertTrue(text.contains("including any you had no room to list"));
    }

    @Test
    @DisplayName("the worked example shows as many lines as the learner's card will have")
    void theExampleFollowsTheCap() throws Exception {
        String a1 = fixInstructions("A1");
        assertTrue(a1.contains("[[FIX]] I am boring -> I'm bored || "));
        assertFalse(a1.contains("[[FIX]] I am agree -> I agree || "),
                "an A1 card has room for one line, and the example must not show two");
        assertTrue(a1.contains("[[SENTENCE]] I'm bored. I agree with you."));

        String b2 = fixInstructions("B2");
        assertTrue(b2.contains("[[FIX]] I am boring -> I'm bored || "));
        assertTrue(b2.contains("[[FIX]] I am agree -> I agree || "));
        assertTrue(b2.contains("[[SENTENCE]] I'm bored. I agree with you."));
    }

    @Test
    @DisplayName("a hesitation is how people talk, not a mistake")
    void hesitationsAreNotMistakes() throws Exception {
        // On a device, "no cheese, cheese, thank you, you, but a little truffle, truffle, oil"
        // became two correction lines about the repeated words.
        String text = fixInstructions("B2");

        assertTrue(text.contains("Speech is not writing."));
        assertTrue(text.contains("never make a correction line of one"));
    }

    @Test
    @DisplayName("several sentences are all of them, start to end")
    void thePromptAsksForEveryPart() throws Exception {
        // The first device run dropped the learner's whole first clause. The example is two
        // sentences now because a model copies the example before it follows the rule.
        String text = fixInstructions("B2");

        assertTrue(text.contains("it starts where the learner started and ends where"));
        assertTrue(text.contains("never leaves a part out"));
        assertTrue(text.contains("\"I am boring. I am agree with you.\""));
    }

    private static final String SAID =
            "This is complicating more, why don't you explain what's the steamed milk and latte more simpler?";

    @Test
    @DisplayName("a sentence that cut part of the message is not the whole sentence")
    void theDeviceCaseIsDropped() {
        // Exactly what the first device run produced: the first clause gone.
        List<ChatbotService.Correction> listed = List.of(
                new ChatbotService.Correction("more simpler", "simpler"),
                new ChatbotService.Correction("what's the steamed milk and latte", "what steamed milk and latte are"));

        assertFalse(ChatbotService.keepsTheRestOf(
                "Why don't you explain what steamed milk and latte are simpler?", SAID, listed));
    }

    @Test
    @DisplayName("the whole message, fixed, is kept -- listed or not")
    void aFullSentenceIsKept() {
        List<ChatbotService.Correction> listed = List.of(
                new ChatbotService.Correction("more simpler", "more simply"),
                new ChatbotService.Correction("what's the steamed milk and latte", "what steamed milk and a latte are"));
        String whole = "This is getting more complicated. Why don't you explain what steamed milk "
                + "and a latte are, more simply?";

        // "This is complicating more" was fixed in the sentence without a line of its own --
        // exactly what the sentence is for -- and most of the untouched words survive.
        assertTrue(ChatbotService.keepsTheRestOf(whole, SAID, listed));
        assertTrue(ChatbotService.keepsTheRestOf(whole.replace('\'', '\u2019'), SAID, listed),
                "the model's curly apostrophe is the learner's straight one");
    }

    @Test
    @DisplayName("a short message has too little outside its corrections to judge")
    void shortMessagesStand() {
        assertTrue(ChatbotService.keepsTheRestOf("I went home.", "I go home",
                List.of(new ChatbotService.Correction("I go", "I went"))));
    }

    @Test
    @DisplayName("a line strikes through the mistake, not the clause around it")
    void linesAreNarrow() throws Exception {
        // The second device run struck through the learner's whole second clause -- "why
        // don't you explain what is steamed milk and latte more simpler?" -- and wrote "could
        // you explain steamed milk and latte more simply?". Two mistakes hidden in one line,
        // one of them dropped rather than fixed, and a correct "why don't you" traded for a
        // phrase the model liked better, shown to the learner as their mistake.
        String text = fixInstructions("B2");

        assertTrue(text.contains("never a whole clause or question"));
        assertTrue(text.contains("Two mistakes in one\n  clause are two lines"));
        assertTrue(text.contains("\"where is the station -> where the station is\""));
        assertTrue(text.contains("\"why don't you\"\n  is never swapped for \"could you\""));
    }

    @Test
    @DisplayName("the lines are copied from the sentence, so the two never disagree")
    void thePromptAsksForAgreement() throws Exception {
        String text = fixInstructions("B2");

        assertTrue(text.contains("Work out the whole corrected message before you write any line"));
        assertTrue(text.contains("The lines and the last line never disagree"));
    }

    @Test
    @DisplayName("a line's corrected words are found in the sentence, word for word")
    void containsPhrase() {
        String sentence =
                "This is more complicated, why don't you explain what milk and latte are more simply.";

        assertTrue(ChatbotService.containsPhrase(sentence, "what milk and latte are"));
        assertTrue(ChatbotService.containsPhrase(sentence, "More complicated"));
        assertTrue(ChatbotService.containsPhrase(sentence, "why don\u2019t you"));
        assertFalse(ChatbotService.containsPhrase(sentence, "simpler"),
                "the third device run: the line said simpler, the sentence more simply");
        assertFalse(ChatbotService.containsPhrase(sentence, "latte are more simple"));
        assertFalse(ChatbotService.containsPhrase(sentence, "mor"), "whole words, not letters");
        assertFalse(ChatbotService.containsPhrase(sentence, ""));
    }
}
