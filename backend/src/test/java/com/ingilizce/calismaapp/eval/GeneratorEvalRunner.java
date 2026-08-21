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
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.TestPropertySource;

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
// src/test/resources/application.properties pins groq.api.url to http://mock-url and the
// key to mock-key, and being on the test classpath it wins over the main configuration.
// Without these three lines the eval would boot with a real key in the environment, send
// every request to a URL that does not exist, and report all four generators as broken.
// The same shape as the bugs this harness is for: one fact in two places, read path stale.
// The circuit breaker is right for the app and wrong here. It opens after five failures,
// which in production protects learners from a provider outage, but in an eval it means the
// sixth case onward is never tested and reports "circuit is open" instead. One sick
// generator would be indistinguishable from seven. Each case has to be judged on its own,
// so the breaker is raised out of the way for this run only.
@TestPropertySource(properties = {
        "groq.api.key=${GROQ_API_KEY}",
        "groq.api.url=https://api.groq.com/openai/v1/chat/completions",
        "groq.api.model=openai/gpt-oss-120b",
        "groq.resilience.failure-threshold=1000"
})
class GeneratorEvalRunner {

    private static final Logger log = LoggerFactory.getLogger(GeneratorEvalRunner.class);
    private static final ObjectMapper MAPPER = new ObjectMapper();

    /** Words a Turkish learner would plausibly be studying, across difficulty. */
    private static final List<String> GOLDEN_WORDS = List.of("mitigate", "insight", "resilient", "delay");
    private static final List<String> GOLDEN_TOPICS = List.of("present perfect", "past simple", "conditionals");
    private static final List<String> GOLDEN_LEVELS = List.of("A2", "B1", "C1");

    /** Read back rather than assumed: see the note on the property override above. */
    @Value("${groq.api.url}") private String resolvedApiUrl;

    @Autowired private ChatbotService chatbotService;
    @Autowired private AiProxyService aiProxyService;
    @Autowired private DailyWordsService dailyWordsService;

    private final List<String> report = new ArrayList<>();
    private int cases;
    private int failedCases;

    @Test
    void everyGeneratorProducesSomethingUsable() throws Exception {
        // Fail loudly rather than spend a run discovering it: an eval aimed at a mock proves
        // nothing, and the answer would look like "every generator is broken".
        if (resolvedApiUrl == null || resolvedApiUrl.contains("mock")) {
            fail("The eval is pointed at " + resolvedApiUrl + ", not the real provider. "
                    + "Check the @TestPropertySource overrides against src/test/resources/application.properties.");
        }

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
                Map<String, Object> json = parse(result.content());
                return new Outcome(GeneratorChecks.sentenceFailures(json, word, "B1"), json);
            });
        }

        for (String topic : GOLDEN_TOPICS) {
            record("grammar[" + topic + "]", () -> {
                var result = aiProxyService.generateGrammarQuiz(
                        topic, "B1", profile, 0, GOLDEN_WORDS);
                return new Outcome(
                        GeneratorChecks.grammarQuizFailures(result.json(), GOLDEN_WORDS, "B1"),
                        result.json());
            });
        }

        for (String level : GOLDEN_LEVELS) {
            // Fixed dayOfYear: the passage theme rotates daily, so leaving it to the clock
            // would mean every run tested a different prompt branch and a failure could not
            // be reproduced. C1 is the level that came back empty in production.
            record("reading[" + level + "]", () -> {
                Map<String, Object> json = aiProxyService.generateReadingPassage(level, profile, 200, 0).json();
                return new Outcome(GeneratorChecks.readingFailures(json, level), json);
            });
        }

        // variantSeed != 0 is the "give me another passage" branch, a different prompt from
        // the daily one and the one a learner hits when they reject what they were given.
        record("reading[B1 regenerated]", () -> {
            Map<String, Object> json = aiProxyService.generateReadingPassage("B1", profile, 200, 7).json();
            return new Outcome(GeneratorChecks.readingFailures(json, "B1"), json);
        });

        record("dailyWords", () -> {
            // Kept as a raw string first: when the payload will not parse, the parse error
            // alone says nothing about what the generator actually sent, and the run has
            // already been paid for. The text itself is the evidence.
            String raw = dailyWordsService.generateDailyWordsPayload(LocalDate.now());
            List<Map<String, Object>> words;
            try {
                words = parseWordList(raw);
            } catch (Exception e) {
                return new Outcome(
                        List.of("payload is not valid JSON: " + e.getMessage()), raw);
            }
            return new Outcome(GeneratorChecks.dailyWordsFailures(words), words);
        });

        writeReport();

        if (failedCases > 0) {
            fail(failedCases + " of " + cases + " generator cases produced unusable output. "
                    + "See target/eval-report.md\n" + String.join("\n", report));
        }
    }

    private interface Case {
        Outcome run() throws Exception;
    }

    /** A verdict and the payload it was reached on. */
    private record Outcome(List<String> failures, Object payload) {}

    /**
     * A case that throws counts as a failure rather than aborting the run.
     *
     * <p>The interesting result is the whole picture — "reading C1 is broken, everything else
     * is fine" is a diagnosis; a stack trace from the first bad case is not.
     */
    private void record(String name, Case testCase) {
        cases++;
        List<String> failures;
        Object payload = null;
        try {
            Outcome outcome = testCase.run();
            failures = outcome.failures();
            payload = outcome.payload();
        } catch (Exception e) {
            failures = List.of("threw " + e.getClass().getSimpleName() + ": " + e.getMessage());
        }
        if (failures.isEmpty()) {
            report.add("- PASS  " + name);
            log.info("eval PASS {}", name);
            return;
        }
        failedCases++;
        report.add("- FAIL  " + name);
        failures.forEach(f -> report.add("    - " + f));
        // Without the payload a failure cannot be triaged from the report alone, and the
        // first question is always the same: is the generator wrong, or is the check? The
        // first live run cost a round of code reading to answer it twice.
        if (payload != null) {
            report.add("");
            report.add("    <details><summary>payload</summary>");
            report.add("");
            report.add("    ```json");
            excerpt(payload).lines().forEach(line -> report.add("    " + line));
            report.add("    ```");
            report.add("");
            report.add("    </details>");
        }
        log.warn("eval FAIL {}: {}", name, failures);
    }

    /** Enough of the payload to diagnose the failure, not so much it buries the report. */
    private static String excerpt(Object payload) {
        String json;
        try {
            json = MAPPER.writerWithDefaultPrettyPrinter().writeValueAsString(payload);
        } catch (Exception e) {
            json = String.valueOf(payload);
        }
        return json.length() <= 4000 ? json : json.substring(0, 4000) + "\n... truncated";
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
