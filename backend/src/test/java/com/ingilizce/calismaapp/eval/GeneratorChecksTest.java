package com.ingilizce.calismaapp.eval;

import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * The checks, run against the payloads that actually reached production.
 *
 * <p>An eval that has never caught anything is a claim, not a safety net. Every failing case
 * below is a real one: the template sentences that shipped for three months, the empty C1
 * passage, a grammar question whose correct answer was not among its options. If a check
 * cannot catch the thing it was written for, this file fails and says so — and none of it
 * costs a token, so it runs in the ordinary suite alongside everything else.
 *
 * <p>The passing cases matter as much. A check that fires on good output gets ignored within
 * a week, and an ignored eval is worse than none because it looks like coverage.
 */
class GeneratorChecksTest {

    // ---------------------------------------------------------------- sentences

    @Test
    void theTemplateSentencesThatShippedForThreeMonthsAreCaught() {
        // Served to learners as model output while the metrics read 100% healthy.
        Map<String, Object> payload = Map.of("sentences", List.of(
                Map.of("englishSentence", "Maya noticed evaluate during the trip.",
                        "turkishTranslation", "değerlendirmek",
                        "turkishFullTranslation", "Maya gezide değerlendirmeyi fark etti.")));

        List<String> failures = GeneratorChecks.sentenceFailures(payload, "evaluate", "B1");

        assertFalse(failures.isEmpty());
        assertTrue(failures.toString().contains("known fallback template"), failures.toString());
    }

    @Test
    void aSentenceMissingItsOwnWordIsCaught() {
        // The one thing a per-word generator must not get wrong.
        Map<String, Object> payload = Map.of("sentences", List.of(
                Map.of("englishSentence", "She finished the report before lunch.",
                        "turkishTranslation", "bitirmek",
                        "turkishFullTranslation", "Raporu öğle yemeğinden önce bitirdi.")));

        List<String> failures = GeneratorChecks.sentenceFailures(payload, "mitigate", "B1");

        assertTrue(failures.toString().contains("does not contain the target word"), failures.toString());
    }

    @Test
    void anEmptyGenerationIsCaught() {
        assertFalse(GeneratorChecks.sentenceFailures(Map.of("sentences", List.of()), "insight", "B1").isEmpty());
        assertFalse(GeneratorChecks.sentenceFailures(null, "insight", "B1").isEmpty());
    }

    @Test
    void ordinaryInflectionIsNotAFailure() {
        // "evaluate" has to match "evaluated". A check that fails correct output is worse
        // than no check, because people stop reading it.
        Map<String, Object> payload = Map.of("sentences", List.of(
                Map.of("englishSentence", "The team evaluated three suppliers last week.",
                        "turkishTranslation", "değerlendirmek",
                        "turkishFullTranslation", "Ekip geçen hafta üç tedarikçiyi değerlendirdi.")));

        assertEquals(List.of(), GeneratorChecks.sentenceFailures(payload, "evaluate", "B1"));
    }

    @Test
    void aWordIsNotFoundInsideAnUnrelatedWord() {
        // "all" must not match "usually", or the check passes on nonsense.
        assertFalse(GeneratorChecks.containsWordStem("She usually walks to work.", "all"));
        assertTrue(GeneratorChecks.containsWordStem("All of them arrived.", "all"));
    }

    // ---------------------------------------------------------------- grammar quiz

    @Test
    void aQuestionWhoseAnswerIsNotOfferedIsCaught() {
        // Unanswerable by construction: the learner cannot pick what is not there.
        Map<String, Object> payload = Map.of("questions", List.of(Map.of(
                "question", "By the time we arrived, they ___ dinner.",
                "options", List.of("finish", "finishes", "are finishing"),
                "correctAnswer", "had finished")));

        List<String> failures = GeneratorChecks.grammarQuizFailures(payload, List.of(), "B2");

        assertTrue(failures.toString().contains("not among the options"), failures.toString());
    }

    @Test
    void aClaimedTargetWordThatIsNotInTheQuestionIsCaught() {
        // targetWord is what lets the answer reach the review scheduler. If it is a lie,
        // the learner gets credit for a word the question never asked about.
        Map<String, Object> payload = Map.of("questions", List.of(Map.of(
                "question", "She ___ to the office every morning.",
                "options", List.of("walk", "walks"),
                "correctAnswer", "walks",
                "targetWord", "mitigate")));

        List<String> failures = GeneratorChecks.grammarQuizFailures(payload, List.of("mitigate"), "B1");

        assertTrue(failures.toString().contains("neither the question nor the answer uses it"),
                failures.toString());
    }

    @Test
    void aFillInTheBlankWhoseAnswerIsTheTargetWordPasses() {
        // Found by the second live eval run. The prompt allows the target word to be the
        // answer when the word itself is what the question tests, and then the stem shows
        // a gap instead of the word. The first version of this check demanded the word in
        // the stem, so it failed every correctly built question of this shape.
        Map<String, Object> payload = Map.of("questions", List.of(Map.of(
                "question", "I have ---- the report before the meeting.",
                "options", List.of("delayed", "delay", "delaying", "delays"),
                "correctAnswer", "delayed",
                "explanation", "Present perfect takes the past participle.",
                "targetWord", "delay")));

        assertEquals(List.of(), GeneratorChecks.grammarQuizFailures(payload, List.of("delay"), "B1"));
    }

    @Test
    void fourIdenticalOptionsAreCaught() {
        // Shipped to learners as four identical buttons. The client only checks that the
        // correct answer is among the options, which duplicates satisfy, so nothing
        // downstream rejected it.
        Map<String, Object> payload = Map.of("questions", List.of(Map.of(
                "question", "I have ---- the report before the meeting.",
                "options", List.of("delayed", "delayed", "delayed", "delayed"),
                "correctAnswer", "delayed",
                "targetWord", "delay")));

        assertTrue(GeneratorChecks.grammarQuizFailures(payload, List.of("delay"), "B1")
                .toString().contains("duplicate options"));
    }

    @Test
    void aWellFormedQuizPasses() {
        // Well formed means what the prompt asks for: a gap, four options, and an
        // explanation. This fixture had none of the three, which is how the checks
        // for them stayed missing.
        Map<String, Object> payload = Map.of("questions", List.of(Map.of(
                "question", "The new policy will ---- most of the risk.",
                "options", List.of("mitigate", "mitigates", "mitigating", "mitigated"),
                "correctAnswer", "mitigate",
                "explanation", "After will the verb stays in its base form.",
                "targetWord", "mitigate")));

        assertEquals(List.of(), GeneratorChecks.grammarQuizFailures(payload, List.of("mitigate"), "B1"));
    }

    // ---------------------------------------------------------------- daily words

    @Test
    void anExampleSentenceWithoutItsWordIsCaught() {
        List<Map<String, Object>> words = List.of(Map.of(
                "word", "resilient",
                "translation", "dayanıklı",
                "definition", "Able to recover quickly.",
                "exampleSentence", "The bridge withstood the storm."));

        List<String> failures = GeneratorChecks.dailyWordsFailures(words);

        assertTrue(failures.toString().contains("does not contain the word"), failures.toString());
    }

    @Test
    void aDuplicateInTheSameDaysSetIsCaught() {
        Map<String, Object> entry = Map.of(
                "word", "insight", "translation", "içgörü",
                "definition", "A deep understanding.",
                "exampleSentence", "Her insight changed the plan.");

        List<String> failures = GeneratorChecks.dailyWordsFailures(List.of(entry, entry));

        assertTrue(failures.toString().contains("duplicate"), failures.toString());
    }

    @Test
    void aCompleteDailyWordPasses() {
        List<Map<String, Object>> words = List.of(Map.of(
                "word", "insight",
                "translation", "içgörü",
                "definition", "A deep and accurate understanding of something.",
                "exampleSentence", "Her insight into the problem saved us a week."));

        assertEquals(List.of(), GeneratorChecks.dailyWordsFailures(words));
    }

    // ---------------------------------------------------------------- reading

    @Test
    void theEmptyC1PassageIsCaught() {
        // C1 reading returned nothing in production more than once.
        Map<String, Object> payload = Map.of("title", "Urban Design", "text", "", "questions", List.of());

        List<String> failures = GeneratorChecks.readingFailures(payload, "C1");

        assertTrue(failures.toString().contains("empty passage"), failures.toString());
    }

    @Test
    void aQuoteThatIsNotInThePassageIsCaught() {
        // The model is asked to quote the sentence its answer comes from. A quote that is
        // not there means the answer was not read out of the passage.
        String passage = "Cities grew around rivers because water carried both trade and waste. "
                + "For centuries the banks were the cheapest place to unload a boat, so "
                + "warehouses, workshops and housing crowded together within a few streets of "
                + "the water. Planners later moved industry away from the banks, which changed "
                + "how neighbourhoods formed and where people chose to live over the following "
                + "century, and many of those older quarters were rebuilt for something else "
                + "entirely once the factories had gone.";
        Map<String, Object> payload = Map.of(
                "title", "Rivers and Cities",
                "text", passage,
                "questions", List.of(
                        Map.of("question", "Why did cities grow around rivers?",
                                "options", List.of("Trade", "Weather", "Defence"),
                                "correctAnswer", "A",
                                "correctAnswerQuote", "rivers were chosen for their beauty"),
                        Map.of("question", "What did planners do later?",
                                "options", List.of("Moved industry", "Built dams", "Nothing"),
                                "correctAnswer", "A",
                                "correctAnswerQuote", "Planners later moved industry away from the banks"),
                        Map.of("question", "What changed as a result?",
                                "options", List.of("Neighbourhoods", "Rainfall", "Borders"),
                                "correctAnswer", "A",
                                "correctAnswerQuote", "changed how neighbourhoods formed")));

        List<String> failures = GeneratorChecks.readingFailures(payload, "B2");

        assertEquals(1, failures.size(), failures.toString());
        assertTrue(failures.get(0).contains("correctAnswerQuote is not in the passage"), failures.toString());
    }

    @Test
    void aReadingAnswerGivenAsOptionTextIsCaught() {
        // Found by the first live eval run, which reported this shape as PASSING.
        // The reading screen labels options by position and marks the one whose letter
        // equals correctAnswer, so an answer holding the option's text matches no letter:
        // no option is ever shown as correct and every answer is graded wrong. The
        // original check looked for the text among the options, which is exactly
        // backwards - it passed the broken payloads and failed the working ones.
        Map<String, Object> payload = Map.of(
                "title", "Rivers and Cities",
                "text", "word ".repeat(60),
                "questions", List.of(
                        Map.of("question", "Why did cities grow around rivers?",
                                "options", List.of("Trade", "Weather", "Defence", "Farming"),
                                "correctAnswer", "Trade")));

        List<String> failures = GeneratorChecks.readingFailures(payload, "B1");

        assertTrue(failures.toString().contains("must be an option letter"), failures.toString());
    }

    @Test
    void aReadingAnswerLetterBeyondTheOptionsIsCaught() {
        // "D" with three options points at nothing.
        Map<String, Object> payload = Map.of(
                "title", "A Title",
                "text", "word ".repeat(60),
                "questions", List.of(
                        Map.of("question", "Why?", "options", List.of("a", "b", "c"),
                                "correctAnswer", "D")));

        assertTrue(GeneratorChecks.readingFailures(payload, "B1").toString()
                .contains("must be an option letter"));
    }

    @Test
    void aSentenceMissingEitherTranslationIsCaught() {
        // The payload carries two: the target word's meaning and the whole sentence.
        // The first version of this check looked for "turkishSentence", a field the
        // generator has never produced, and so reported every healthy sentence as broken.
        Map<String, Object> onlyWordMeaning = Map.of("sentences", List.of(
                Map.of("englishSentence", "The flight was delayed by heavy rain.",
                        "turkishTranslation", "gecikme")));

        assertTrue(GeneratorChecks.sentenceFailures(onlyWordMeaning, "delay", "B1").toString()
                .contains("missing the full-sentence translation"));

        Map<String, Object> onlyFullSentence = Map.of("sentences", List.of(
                Map.of("englishSentence", "The flight was delayed by heavy rain.",
                        "turkishFullTranslation", "Uçuş şiddetli yağmur yüzünden gecikti.")));

        assertTrue(GeneratorChecks.sentenceFailures(onlyFullSentence, "delay", "B1").toString()
                .contains("missing the target word's translation"));
    }

    @Test
    void aNonTurkishLearnerSTranslationFieldsAreAccepted() {
        // Same payload, source-language keys: a Spanish learner's sentences are not broken.
        Map<String, Object> payload = Map.of("sentences", List.of(
                Map.of("englishSentence", "The flight was delayed by heavy rain.",
                        "sourceTranslation", "retraso",
                        "sourceFullTranslation", "El vuelo se retrasó por la lluvia intensa.")));

        assertEquals(List.of(), GeneratorChecks.sentenceFailures(payload, "delay", "B1"));
    }

    @Test
    void tooFewComprehensionQuestionsIsCaught() {
        Map<String, Object> payload = Map.of(
                "title", "A Title",
                "text", "word ".repeat(60),
                "questions", List.of(Map.of("question", "Why?", "options", List.of("a", "b"),
                        "correctAnswer", "a")));

        assertTrue(GeneratorChecks.readingFailures(payload, "B1").toString().contains("question(s)"));
    }
    // ------------------------------------------------- the shape of a question

    @Test
    void aStemWithNoGapIsCaught() {
        // What "the quiz makes no sense" looks like from the outside: a
        // multiple-choice card asking the learner to complete a sentence that has
        // nothing to complete. Both this check and the client's own filter passed
        // it through, so it reached the screen.
        Map<String, Object> payload = Map.of("questions", List.of(Map.of(
                "question", "She has finished the report already.",
                "options", List.of("finished", "finish", "finishing", "finishes"),
                "correctAnswer", "finished",
                "explanation", "Present perfect takes the past participle.",
                "targetWord", "")));

        assertTrue(GeneratorChecks.grammarQuizFailures(payload, List.of(), "B1")
                .stream().anyMatch(f -> f.contains("no ---- gap")));
    }

    @Test
    void anErrorSpottingQuestionIsAllowedFromB2() {
        // The prompt offers this shape at B2 and above, and it carries no gap by
        // design. A check that demanded one everywhere would fail every correctly
        // built one of them.
        Map<String, Object> payload = Map.of("questions", List.of(Map.of(
                "question", "Which part of this sentence is wrong? \"He have been waiting.\"",
                "options", List.of("He", "have", "been", "waiting"),
                "correctAnswer", "have",
                "explanation", "Third person singular takes has, not have.",
                "targetWord", "")));

        assertEquals(List.of(), GeneratorChecks.grammarQuizFailures(payload, List.of(), "B2"));
    }

    @Test
    void theSameQuestionIsStillCaughtBelowB2() {
        // Where the prompt asks for single-gap questions only, a missing gap is the
        // model dropping the format rather than choosing the other one.
        Map<String, Object> payload = Map.of("questions", List.of(Map.of(
                "question", "Which part of this sentence is wrong? \"He have been waiting.\"",
                "options", List.of("He", "have", "been", "waiting"),
                "correctAnswer", "have",
                "explanation", "Third person singular takes has.",
                "targetWord", "")));

        assertTrue(GeneratorChecks.grammarQuizFailures(payload, List.of(), "A2")
                .stream().anyMatch(f -> f.contains("no ---- gap")));
    }

    @Test
    void twoOptionsAreNotAMultipleChoiceQuestion() {
        Map<String, Object> payload = Map.of("questions", List.of(Map.of(
                "question", "She has ---- the report already.",
                "options", List.of("finished", "finish"),
                "correctAnswer", "finished",
                "explanation", "Present perfect takes the past participle.",
                "targetWord", "")));

        assertTrue(GeneratorChecks.grammarQuizFailures(payload, List.of(), "B1")
                .stream().anyMatch(f -> f.contains("exactly 4")));
    }

    @Test
    void aQuestionWithNoExplanationIsCaught() {
        // A wrong answer with no explanation tells the learner they were wrong and
        // not why, which is the moment the quiz existed for.
        Map<String, Object> payload = Map.of("questions", List.of(Map.of(
                "question", "She has ---- the report already.",
                "options", List.of("finished", "finish", "finishing", "finishes"),
                "correctAnswer", "finished",
                "explanation", "  ",
                "targetWord", "")));

        assertTrue(GeneratorChecks.grammarQuizFailures(payload, List.of(), "B1")
                .stream().anyMatch(f -> f.contains("no explanation")));
    }

}
