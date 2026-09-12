package com.ingilizce.calismaapp.service;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.lang.reflect.Method;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The paragraph that asks the model for the correction card.
 *
 * <p>Found in use: a B2 learner said "Can you open the light?" and got a cheerful reply and
 * no card. The card line had been tied to the same "one error every few messages" policy
 * that keeps Amy's spoken reply from lecturing, and the model obeyed it. These pin the two
 * things that fix that -- the line is declared independent of that policy, and a Turkish
 * calque is named as a mistake -- and the one thing that must not change with it.
 *
 * <p>Found the same way, later: an A1 learner never saw a card at all, because the same
 * paragraph told the model to omit the line entirely below B1. So the policy the card obeys
 * is pinned here at every level, along with the note that makes a card readable to someone
 * who cannot yet read the correction.
 *
 * <p>Read by reflection for the same reason the recall test is: the instructions are
 * private, and widening the service for a test is the worse trade. They take the profile
 * now because the note is written in the learner's own language and nothing else in the
 * chat prompt ever knew what that was.
 */
class ChatbotFixInstructionsTest {

    private String fixInstructions(LearningLanguageProfile profile) throws Exception {
        Method method =
                ChatbotService.class.getDeclaredMethod("fixInstructions", LearningLanguageProfile.class);
        method.setAccessible(true);
        return (String) method.invoke(null, profile);
    }

    /** The default learner: Turkish, B1. */
    private String fixInstructions() throws Exception {
        return fixInstructions(LearningLanguageProfile.defaultProfile());
    }

    private LearningLanguageProfile learner(String sourceLanguage, String level) {
        return LearningLanguageProfile.of(sourceLanguage, "English", sourceLanguage, level, "Speaking");
    }

    @Test
    @DisplayName("the card is not subject to the reply's correction frequency")
    void cardIsIndependentOfReplyFrequency() throws Exception {
        String text = fixInstructions();

        assertThat(text).contains("does not govern this line");
        assertThat(text).contains("every clear mistake at every level");
        // The old wording that bound them, gone.
        assertThat(text).doesNotContain("Follow the correction frequency above");
        assertThat(text).doesNotContain("worth showing");
    }

    @Test
    @DisplayName("word choice a native speaker would not use counts as a mistake")
    void calquesAreMistakes() throws Exception {
        String text = fixInstructions();

        // The exact sentence that slipped through, and the reason it slipped.
        assertThat(text).contains("open the light");
        assertThat(text).contains("meaning being clear does not");
    }

    @Test
    @DisplayName("beginners get the card too")
    void beginnersAreCorrectedOnTheCard() throws Exception {
        // The reverse of what stood here. "Confidence before accuracy" is a real product
        // decision and it is about what Amy SAYS; the card is silent and costs the
        // conversation nothing, so withholding it from A1 and A2 only meant that the
        // learners who most needed to see their mistake were the only ones who never did.
        for (String level : new String[] {"A1", "A2"}) {
            String text = fixInstructions(learner("Turkish", level));

            assertThat(text).contains("A1 and A2 included");
            assertThat(text).doesNotContain("At A1 and A2 omit the line entirely");
            assertThat(text).doesNotContain("those learners are not corrected at all");
        }
    }

    @Test
    @DisplayName("at A1 and A2 the note is not optional")
    void beginnersAlwaysGetTheNote() throws Exception {
        // "I am boring" struck through above "I'm bored" is a joke to someone who knows
        // the difference. At these levels the note is the only part of the card the
        // learner can read, so a card without one is a card that teaches nothing.
        assertThat(fixInstructions(learner("Turkish", "A1"))).contains("REQUIRED on every line");
        assertThat(fixInstructions(learner("Turkish", "A2"))).contains("REQUIRED on every line");
    }

    @Test
    @DisplayName("above A2 the note is wanted, not forced")
    void higherLevelsMayLeaveTheNoteOff() throws Exception {
        // Padding out an explanation of an obvious slip is worse than not explaining it.
        for (String level : new String[] {"B1", "B2", "C1", "C2"}) {
            String text = fixInstructions(learner("Turkish", level));

            assertThat(text).contains("Add the note whenever you can say why");
            assertThat(text).doesNotContain("REQUIRED on every line");
        }
    }

    @Test
    @DisplayName("the note is asked for in the learner's own language, not a fixed one")
    void noteIsInTheLearnersLanguage() throws Exception {
        // The whole point of the note. A Spanish speaker being explained to in Turkish is
        // the same card as no card, and the prompt is the only place the language can
        // come from -- the profile has carried it all along and the chat prompt dropped it.
        String spanish = fixInstructions(learner("Spanish", "B1"));

        assertThat(spanish).contains("written in Spanish");
        // "Write yours in Spanish" used to stand here, under an English example, as the
        // hedge that made an English demonstration excusable. The example is Spanish now,
        // so the hedge is gone and this asks the demonstration instead.
        assertThat(spanish).contains("significa que aburres a los demás");
        assertThat(spanish).doesNotContain("Turkish");

        assertThat(fixInstructions(learner("German", "B1"))).contains("short note in German");
    }

    @Test
    @DisplayName("the reply itself stays English")
    void onlyTheNoteSwitchesLanguage() throws Exception {
        // Naming a native language in a system prompt is an invitation to start speaking
        // it, and a tutor that answers in Turkish is not a speaking tutor.
        String text = fixInstructions();

        assertThat(text).contains("only Turkish you ever write");
        assertThat(text).contains("stays in English");
    }

    @Test
    @DisplayName("a note explains, and is not a translation of the fix")
    void noteExplainsRatherThanTranslates() throws Exception {
        String text = fixInstructions();

        assertThat(text).contains("says WHY the words were wrong");
        assertThat(text).contains("NEVER a translation of the corrected words");
        // One sentence. The client drops anything past 160 characters and so does the
        // server, and a dropped note is a note the learner never gets.
        assertThat(text).contains("ONE short sentence");
    }

    @Test
    @DisplayName("one worked example shows what a note looks like")
    void oneWorkedExample() throws Exception {
        // Told what a note is, models write a translation of the corrected sentence.
        // Shown one, they do not.
        String text = fixInstructions();

        assertThat(text).contains("[[FIX]] I am boring -> I'm bored || ");
    }

    @Test
    @DisplayName("the note's language is stated in that language, right before the examples")
    void theLanguageIsAnchoredInItself() throws Exception {
        // The rule about reasons is a paragraph of English, and on a device the model wrote
        // the reason half of a Turkish note in English. Three English sentences asking for
        // Turkish had already been walked past; the one line it reads in Turkish just
        // before writing Turkish is what a demonstration adds that an instruction cannot.
        assertThat(fixInstructions(learner("Turkish", "B2"))).contains("Notun tamamı Türkçe");
        assertThat(fixInstructions(learner("Spanish", "B1"))).contains("Toda la nota va en español");

        for (String language : new String[] {
                "Turkish", "German", "French", "Italian", "Portuguese", "Spanish"}) {
            assertThat(fixInstructions(learner(language, "B1")))
                    .as("anchor for %s", language)
                    .doesNotContain("The whole note is in English");
        }
        assertThat(fixInstructions(learner("English", "B1")))
                .contains("The whole note is in English");
    }

    @Test
    @DisplayName("words said in another language are taught, not let pass")
    void wordsInAnotherLanguageAreACorrection() throws Exception {
        // Measured on a device, in the restaurant scene: "Spaghetti Pomodoro sounds good and
        // also, merhaba, biraz su alabilir miyiz?" The waiter understood, brought the water,
        // and the card listed nothing -- corrections=0 -- on the one turn where the learner
        // had shown exactly which English they were missing. Staying in the scene is right;
        // the card is where the English goes.
        String text = fixInstructions();

        assertThat(text).contains("Anything they said in another language is a correction too");
        // And the first time it was used, it went wrong both ways at once: "birasso" -- a
        // mangled "biraz su" -- was guessed at and "corrected" into Turkish for "a beer".
        assertThat(text).contains("The corrected side is always English");
        // And on the next conversation: a correct order struck through for the dish the waiter
        // was about to suggest, and "police" guessed into "people" for somebody who said please.
        assertThat(text).contains("never about what they chose");
        assertThat(text).contains("Never guess a\n  different word into its place");
        assertThat(text).contains("Never\n  guess at one");
        assertThat(text).contains("even\n  when your reply understood them and carried on");
    }

    @Test
    @DisplayName("a note gives a reason, never a label")
    void aNoteIsNotALabel() throws Exception {
        // From a tester, about the card for "I had like": the note read "\"had like\" is
        // not idiomatic; use \"would like\" for polite requests", and they wrote back that
        // explanations like that are not going to help anyone. "Not idiomatic" says the
        // words are wrong, which the strikethrough already said, in a word the learner has
        // to look up. The prompt asked for WHY and the model answered with a verdict;
        // naming the verdict is what stops it.
        String text = fixInstructions();

        assertThat(text).contains("NEVER a label either");
        assertThat(text).contains("\"Not idiomatic\"");
        assertThat(text).contains("no grammar term the learner");
    }

    @Test
    @DisplayName("and a translated label is still a label")
    void aLabelIsALabelInAnyLanguage() throws Exception {
        // The English list above went in and the same sentence came back, on a device,
        // with "\"had like\" doğru bir ifade değil, \"would like\" kullanılır" -- "not a
        // correct expression", in Turkish. The note is written in the learner's language
        // and the list was English, so the model translated the label and walked past.
        // A longer list loses the same way in the next language; a test the model can
        // run on its own note does not: "'X' is not correct, use 'Y'" is true for any X
        // and Y, so it says nothing about these two.
        String text = fixInstructions(learner("Turkish", "B2"));

        assertThat(text).contains("translating them into the note's language");
        assertThat(text).contains("any other two");
        assertThat(text).contains("what the words DO");
    }

    @Test
    @DisplayName("a mistake whose words mean nothing is demonstrated too")
    void aFormMistakeIsDemonstrated() throws Exception {
        // "I am boring" means something -- the wrong thing -- and its note says what. "I had
        // like" and "I am agree" mean nothing, and with only the first example to copy the
        // model had no shape for them and reached for a label.
        assertThat(fixInstructions()).contains("[[FIX]] I am agree -> I agree || ");

        assertThat(fixInstructions(learner("Spanish", "B1")))
                .contains("ya significa \"estar de acuerdo\"");
        assertThat(fixInstructions(learner("Turkish", "B1")))
                .contains("tek başına \"katılıyorum\" demek");

        // Same rule as the first example: a language with no note of its own would get the
        // English one, and an English demonstration is what produced English notes.
        for (String language : new String[] {
                "Turkish", "German", "French", "Italian", "Portuguese", "Spanish"}) {
            assertThat(fixInstructions(learner(language, "B1")))
                    .as("form example for %s", language)
                    .doesNotContain("already says the whole thing");
        }
        assertThat(fixInstructions(learner("English", "B1")))
                .contains("already says the whole thing");
    }

    @Test
    @DisplayName("and it is written in the language the note is asked for")
    void theExampleSpeaksTheLearnersLanguage() throws Exception {
        // Seen on a device: a Turkish B2 learner said "I very like this app" and the card
        // came back with an English note -- "\"very\" is not used before a verb" -- after a
        // prompt that had asked for Turkish three separate times. The one worked example
        // was English, with a line under it saying to write yours in Turkish. An
        // instruction argues and a demonstration shows, and the model followed the
        // demonstration.
        assertThat(fixInstructions(learner("Turkish", "B1")))
                .contains("karşındakini sıkıyorsun demek");
        assertThat(fixInstructions(learner("Spanish", "B1")))
                .contains("significa que aburres a los demás");
        assertThat(fixInstructions(learner("German", "B1")))
                .contains("dass du andere langweilst");

        // And the hedge that stood in for it is gone: it existed only to excuse an
        // example in the wrong language.
        assertThat(fixInstructions(learner("Turkish", "B1")))
                .doesNotContain("written in English only so you can see");
    }

    @Test
    @DisplayName("every shipped language has its own example, and the rest fall back")
    void everyShippedLanguageIsDemonstrated() throws Exception {
        // Seven interface languages. A language with no example of its own would get an
        // English one, which is the exact failure above -- so each is checked for a
        // sentence that could not be English.
        for (String language : new String[] {
                "Turkish", "German", "French", "Italian", "Portuguese", "Spanish"}) {
            String text = fixInstructions(learner(language, "B1"));

            assertThat(text)
                    .as("worked example for %s", language)
                    .doesNotContain("means you make other people bored");
        }

        // English, and anything the app does not ship, read the English one: it is what
        // the interface itself falls back to.
        assertThat(fixInstructions(learner("English", "B1")))
                .contains("means you make other people bored");
    }

    @Test
    @DisplayName("the line's shape is the marker, the words, the separator, the fix, the note")
    void shapeIsUnchanged() throws Exception {
        // extractCorrection parses exactly this; a reworded instruction that moved the
        // marker would cost every correction silently. The note is appended to the shape
        // rather than folded into it, so the arrow half is character-for-character what
        // it was before notes existed.
        assertThat(fixInstructions())
                .contains("[[FIX]] their exact words -> the corrected words || short note in Turkish");
    }
}
