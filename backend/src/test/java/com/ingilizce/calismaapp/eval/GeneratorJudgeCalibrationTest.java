package com.ingilizce.calismaapp.eval;

import com.ingilizce.calismaapp.service.AiCompletionProvider;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.TestPropertySource;

import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.fail;

/**
 * Proves the judge can fail, and can stop failing.
 *
 * <p>A model asked "is this good?" will mostly say yes, and a judge that says yes to
 * everything is worse than no judge: it looks like coverage. It is the same defect as the
 * provider metric that counted an empty completion as a success, and the same defect as a
 * grep for "error •" against output that says "error -". This test is the thing that stops
 * it shipping.
 *
 * <p>Both directions are checked, and the second matters as much as the first. A judge that
 * flags ordinary correct content gets switched off within a week, and then the eval is
 * decoration.
 *
 * <p>The bad cases are real. "Maya noticed evaluate during the trip." was served to learners
 * for three months. The quiz distractors were produced by this app's own generator and found
 * on a live eval run. Nothing here is invented to be easy.
 *
 * <pre>
 *   cd backend
 *   GROQ_API_KEY=... mvn test -Dtest=GeneratorJudgeCalibrationTest -Dexcluded.test.groups=
 * </pre>
 */
@SpringBootTest
@Tag("eval")
@EnabledIfEnvironmentVariable(named = "GROQ_API_KEY", matches = "^(?!dummy).+")
@TestPropertySource(properties = {
        "groq.api.key=${GROQ_API_KEY}",
        "groq.api.url=https://api.groq.com/openai/v1/chat/completions",
        "groq.api.model=openai/gpt-oss-120b",
        "groq.resilience.failure-threshold=1000"
})
class GeneratorJudgeCalibrationTest {

    private static final Logger log = LoggerFactory.getLogger(GeneratorJudgeCalibrationTest.class);

    @Autowired private AiCompletionProvider provider;
    @Value("${groq.api.model}") private String model;

    private GeneratorJudge judge() {
        return new GeneratorJudge(provider, model);
    }

    // ------------------------------------------------------------------ content it must fail

    /** Five months of production output. The word is present and the sentence is nonsense. */
    private static final String TEMPLATE_SENTENCES = """
            {"sentences":[
              {"englishSentence":"Maya noticed evaluate during the trip.",
               "turkishTranslation":"degerlendirmek",
               "turkishFullTranslation":"Maya gezide degerlendirmeyi fark etti."},
              {"englishSentence":"The team evaluated the plan carefully.",
               "turkishTranslation":"degerlendirmek",
               "turkishFullTranslation":"Ekip plani dikkatle degerlendirdi."}
            ]}
            """;

    /** Distractors this app's own generator produced. "insighted" is not a word. */
    private static final String INVENTED_DISTRACTORS = """
            {"topic":"past simple","questions":[
              {"question":"Yesterday the team ---- the problem clearly.",
               "options":["insighted","insightfully","insights","insightment"],
               "correctAnswer":"insighted",
               "explanation":"Past simple takes -ed.","targetWord":"insight"}
            ]}
            """;

    /** Answerable without reading a word of the passage. */
    private static final String GENERAL_KNOWLEDGE_QUESTION = """
            {"title":"The Sun","text":"The sun is a star at the centre of our solar system. \
            It gives light and heat to the planets around it. People have watched the sun for \
            thousands of years and used it to measure time. Farmers plan their work around \
            sunrise and sunset. Modern panels turn its light into electricity for homes and \
            schools across many countries today.",
             "questions":[
              {"question":"What colour is the sky on a clear day?",
               "options":["Blue","Green","Purple","Orange"],"correctAnswer":"A"},
              {"question":"How many days are in a week?",
               "options":["Five","Six","Seven","Eight"],"correctAnswer":"C"},
              {"question":"What is 2 + 2?",
               "options":["Three","Four","Five","Six"],"correctAnswer":"B"}
            ]}
            """;

    /** Examples that show nothing about how the word is used. */
    private static final String VACUOUS_EXAMPLES = """
            {"words":[
              {"word":"stadium","translation":"stadyum","definition":"A sports ground.",
               "exampleSentence":"The stadium was good.",
               "meanings":[{"translation":"stadyum","sense":"noun",
                 "exampleSentence":"The stadium was good.","exampleTranslation":"Stadyum iyiydi."}]},
              {"word":"resilient","translation":"dayanikli","definition":"Able to recover.",
               "exampleSentence":"It was resilient.",
               "meanings":[{"translation":"dayanikli","sense":"adjective",
                 "exampleSentence":"It was resilient.","exampleTranslation":"Dayanikliydi."}]}
            ]}
            """;

    // ------------------------------------------------------------------ content it must pass

    private static final String GOOD_SENTENCES = """
            {"sentences":[
              {"englishSentence":"The flight was delayed by three hours because of heavy snow.",
               "turkishTranslation":"gecikme",
               "turkishFullTranslation":"Ucus yogun kar yuzunden uc saat gecikti."},
              {"englishSentence":"Why did they delay the announcement until Monday?",
               "turkishTranslation":"ertelemek",
               "turkishFullTranslation":"Duyuruyu neden pazartesiye ertelediler?"}
            ]}
            """;

    private static final String GOOD_QUIZ = """
            {"topic":"present perfect","questions":[
              {"question":"I ---- the report, so you can read it now.",
               "options":["have finished","finished","am finishing","will finish"],
               "correctAnswer":"have finished",
               "explanation":"Present perfect links a finished action to the present result.",
               "targetWord":"finish"}
            ]}
            """;

    private static final String GOOD_READING = """
            {"title":"Buses That Drive Themselves","text":"Smart buses are new vehicles that \
            help people travel in cities. They use electric power and can drive themselves. \
            Last year one city started a test programme. The buses were safe and fast, and \
            they stopped at the right places automatically. People used a phone app to see \
            when a bus would arrive. Many travellers said they felt safer because the buses \
            did not need a driver.",
             "questions":[
              {"question":"How did travellers explain feeling safer?",
               "options":["The buses were cheaper","The buses had no driver",
                          "The buses were slower","The buses were newer"],
               "correctAnswer":"B",
               "correctAnswerQuote":"they felt safer because the buses did not need a driver"},
              {"question":"What did the phone app tell people?",
               "options":["The ticket price","The driver's name",
                          "When a bus would arrive","How fast the bus was going"],
               "correctAnswer":"C",
               "correctAnswerQuote":"used a phone app to see when a bus would arrive"},
              {"question":"When did the test programme begin?",
               "options":["Last week","Last month","Last year","Next year"],
               "correctAnswer":"C",
               "correctAnswerQuote":"Last year one city started a test programme"}
            ]}
            """;

    // ------------------------------------------------------------------ the calibration

    private record Case(String name, String content, boolean shouldFail, List<String> verdicts) {}

    @Test
    void theJudgeSeparatesContentThatShippedBrokenFromContentThatIsFine() {
        GeneratorJudge judge = judge();

        List<Case> cases = new ArrayList<>();
        cases.add(new Case("bad/template-sentences", TEMPLATE_SENTENCES, true,
                describe(judge.judgeSentences("evaluate", "B1", TEMPLATE_SENTENCES))));
        cases.add(new Case("bad/invented-distractors", INVENTED_DISTRACTORS, true,
                describe(judge.judgeGrammarQuiz("past simple", "B1", INVENTED_DISTRACTORS))));
        cases.add(new Case("bad/general-knowledge-questions", GENERAL_KNOWLEDGE_QUESTION, true,
                describe(judge.judgeReading("A2", GENERAL_KNOWLEDGE_QUESTION))));
        cases.add(new Case("bad/vacuous-examples", VACUOUS_EXAMPLES, true,
                describe(judge.judgeDailyWords(VACUOUS_EXAMPLES))));

        cases.add(new Case("good/sentences", GOOD_SENTENCES, false,
                describe(judge.judgeSentences("delay", "B1", GOOD_SENTENCES))));
        cases.add(new Case("good/quiz", GOOD_QUIZ, false,
                describe(judge.judgeGrammarQuiz("present perfect", "B1", GOOD_QUIZ))));
        cases.add(new Case("good/reading", GOOD_READING, false,
                describe(judge.judgeReading("A2", GOOD_READING))));

        List<String> wrong = new ArrayList<>();
        for (Case c : cases) {
            boolean failed = !c.verdicts().isEmpty();
            log.info("calibration {} -> {} {}", c.name(), failed ? "FLAGGED" : "clean", c.verdicts());
            if (c.shouldFail() && !failed) {
                wrong.add(c.name() + ": the judge passed content that shipped broken");
            }
            if (!c.shouldFail() && failed) {
                wrong.add(c.name() + ": the judge flagged ordinary correct content — " + c.verdicts());
            }
        }

        if (!wrong.isEmpty()) {
            fail("The judge is not calibrated and must not be trusted:\n" + String.join("\n", wrong));
        }
    }

    @Test
    void everyFailingVerdictQuotesTheContentItIsAbout() {
        // Enforced when parsing, so this is really asking whether the judge complies rather
        // than being silently filtered - a judge whose findings are all discarded looks
        // exactly like a judge that found nothing.
        List<GeneratorJudge.Verdict> verdicts =
                judge().judgeSentences("evaluate", "B1", TEMPLATE_SENTENCES);

        assertTrue(verdicts.stream().anyMatch(v -> !v.passed()),
                "expected the template sentences to be flagged, got: " + verdicts);
        for (GeneratorJudge.Verdict verdict : verdicts) {
            if (!verdict.passed()) {
                assertTrue(TEMPLATE_SENTENCES.contains(verdict.evidence()),
                        "evidence was not copied from the content: " + verdict.evidence());
            }
        }
    }

    private static List<String> describe(List<GeneratorJudge.Verdict> verdicts) {
        return GeneratorJudge.failures(verdicts);
    }
}
