package com.ingilizce.calismaapp.eval;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ingilizce.calismaapp.service.AiProxyService;
import com.ingilizce.calismaapp.service.ChatbotService;
import com.ingilizce.calismaapp.service.DailyWordsService;
import com.ingilizce.calismaapp.service.LearningLanguageProfile;
import com.ingilizce.calismaapp.service.PracticeSentencePrompt;
import com.ingilizce.calismaapp.service.PromptCatalog;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.fail;

/**
 * Runs the real generators against a fixed set of inputs and applies {@link GeneratorChecks}.
 *
 * <p>This is the part that costs money. It calls the live provider, it is non-deterministic,
 * and it is therefore excluded from {@code mvn test} by the {@code eval} tag and skipped
 * entirely unless a real {@code GROQ_API_KEY} is present. Run it on purpose:
 *
 * <pre>
 *   cd backend
 *   GROQ_API_KEY=... mvn test -Dtest=GeneratorEvalRunner -Dexcluded.test.groups=
 * </pre>
 *
 * <p>Or from the Actions tab, via the "Generator Eval" workflow, which uploads the report.</p>
 *
 * <p>It calls the same service methods the app calls. An eval that builds its own prompt
 * proves the eval works; this one can only pass if the thing learners actually use works.
 *
 * <p>The golden set is small on purpose — one run should be cheap enough that nobody
 * hesitates to run it after touching a prompt. The point is not coverage of every input, it
 * is that the four generators which have failed silently in production are exercised end to
 * end before a prompt change ships.
 */
@SpringBootTest
@Tag("eval")
@EnabledIfEnvironmentVariable(named = "GROQ_API_KEY", matches = "^(?!dummy).+")
class GeneratorEvalRunner {

    private static final Logger log = LoggerFactory.getLogger(GeneratorEvalRunner.class);
    private static final ObjectMapper MAPPER = new ObjectMapper();

    /** Words a Turkish learner would plausibly be studying, across difficulty. */
    private static final List<String> GOLDEN_WORDS = List.of("mitigate", "insight", "resilient", "delay");
    private static final List<String> GOLDEN_TOPICS = List.of("present perfect", "past simple", "conditionals");
    private static final List<String> GOLDEN_LEVELS = List.of("A2", "B1", "C1");

    @Autowired private ChatbotService chatbotService;
    @Autowired private AiProxyService aiProxyService;
    @Autowired private DailyWordsService dailyWordsService;

    private final List<String> report = new ArrayList<>();
    private int cases;
    private int failedCases;

    @Test
    void everyGeneratorProducesSomethingUsable() throws Exception {
        LearningLanguageProfile profile = LearningLanguageProfile.defaultProfile();

        for (String word : GOLDEN_WORDS) {
            record("sentences[" + word + "]", () -> {
                // The real message the practice screen sends, not an approximation of it.
                String message = PracticeSentencePrompt.build(new PracticeSentencePrompt.Inputs(
                        List.of(word), Map.of(), "SOURCE_TO_TARGET", List.of("B1"),
                        List.of("short", "medium", "long"),
                        PromptCatalog.grammarPatternSetFor(word + ":SOURCE_TO_TARGET", null, false),
                        List.of(), profile, false, 0L));
                var result = chatbotService.generateSentences(message, profile);
                return GeneratorChecks.sentenceFailures(parse(result.content()), word, "B1");
            });
        }

        for (String topic : GOLDEN_TOPICS) {
            record("grammar[" + topic + "]", () -> {
                var result = aiProxyService.generateGrammarQuiz(
                        topic, "B1", profile, 0, GOLDEN_WORDS);
                return GeneratorChecks.grammarQuizFailures(result.json(), GOLDEN_WORDS, "B1");
            });
        }

        for (String level : GOLDEN_LEVELS) {
            // Fixed dayOfYear: the passage theme rotates daily, so leaving it to the clock
            // would mean every run tested a different prompt branch and a failure could not
            // be reproduced. C1 is the level that came back empty in production.
            record("reading[" + level + "]", () ->
                    GeneratorChecks.readingFailures(
                            aiProxyService.generateReadingPassage(level, profile, 200, 0).json(), level));
        }

        // variantSeed != 0 is the "give me another passage" branch, a different prompt from
        // the daily one and the one a learner hits when they reject what they were given.
        record("reading[B1 regenerated]", () ->
                GeneratorChecks.readingFailures(
                        aiProxyService.generateReadingPassage("B1", profile, 200, 7).json(), "B1"));

        record("dailyWords", () -> {
            String payload = dailyWordsService.generateDailyWordsPayload(LocalDate.now());
            return GeneratorChecks.dailyWordsFailures(parseWordList(payload));
        });

        writeReport();

        if (failedCases > 0) {
            fail(failedCases + " of " + cases + " generator cases produced unusable output. "
                    + "See target/eval-report.md\n" + String.join("\n", report));
        }
    }

    private interface Case {
        List<String> run() throws Exception;
    }

    /**
     * A case that throws counts as a failure rather than aborting the run.
     *
     * <p>The interesting result is the whole picture — "reading C1 is broken, everything else
     * is fine" is a diagnosis; a stack trace from the first bad case is not.
     */
    private void record(String name, Case testCase) {
        cases++;
        List<String> failures;
        try {
            failures = testCase.run();
        } catch (Exception e) {
            failures = List.of("threw " + e.getClass().getSimpleName() + ": " + e.getMessage());
        }
        if (failures.isEmpty()) {
            report.add("- PASS  " + name);
            log.info("eval PASS {}", name);
        } else {
            failedCases++;
            report.add("- FAIL  " + name);
            failures.forEach(f -> report.add("    - " + f));
            log.warn("eval FAIL {}: {}", name, failures);
        }
    }

    private void writeReport() throws Exception {
        List<String> lines = new ArrayList<>();
        lines.add("# Generator eval");
        lines.add("");
        lines.add((cases - failedCases) + " of " + cases + " cases usable.");
        lines.add("");
        lines.addAll(report);
        Path out = Path.of("target", "eval-report.md");
        Files.createDirectories(out.getParent());
        Files.writeString(out, String.join("\n", lines) + "\n");
        log.info("eval report written to {}", out.toAbsolutePath());
    }

    /** Models wrap JSON in markdown fences often enough that this is not optional. */
    @SuppressWarnings("unchecked")
    private static Map<String, Object> parse(String content) throws Exception {
        if (content == null || content.isBlank()) {
            return Map.of();
        }
        String cleaned = content.trim()
                .replaceAll("^```(?:json)?\\s*", "")
                .replaceAll("\\s*```$", "")
                .trim();
        return MAPPER.readValue(cleaned, Map.class);
    }

    @SuppressWarnings("unchecked")
    private static List<Map<String, Object>> parseWordList(String payload) throws Exception {
        Map<String, Object> json = parse(payload);
        Object words = json.get("words");
        if (words instanceof List<?> list) {
            return (List<Map<String, Object>>) list;
        }
        return List.of();
    }
}
