package com.ingilizce.calismaapp.eval;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ingilizce.calismaapp.service.AiCompletionProvider;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * Asks a second model whether generated content is worth a learner's time.
 *
 * <p>{@link GeneratorChecks} answers a different question. It can prove a quiz question is
 * answerable — the correct answer is among the options, the sentence contains its word, the
 * quoted evidence is really in the passage. It cannot tell you the sentence reads like
 * English, that the distractors are mistakes a learner would actually make, or that a
 * comprehension question needs the passage to be understood rather than scanned. Those need
 * a reader.
 *
 * <p>The obvious failure mode of a model judge is that it agrees with everything, and an
 * eval that cannot fail is the exact thing this harness was built to stop — the provider
 * metric that counted an empty completion as a success is the same shape. Three things push
 * against it:
 *
 * <ul>
 *   <li>Every failing verdict must quote the span it is about, copied from the content. A
 *       judge that cannot point at the problem does not have one.</li>
 *   <li>The criteria are narrow and concrete. "Is this good?" invites agreement; "would a
 *       learner who did not read the passage answer this correctly?" does not.</li>
 *   <li>{@code GeneratorJudgeCalibrationTest} runs it over content that is known bad and
 *       known good. A judge that passes the bad set is broken and says so.</li>
 * </ul>
 *
 * <p>The judge is advisory by design. It runs at eval time, never in the request path: it
 * doubles the cost and latency of a generation, and its own output is a generation and can
 * be wrong.
 */
public final class GeneratorJudge {

    private static final ObjectMapper MAPPER = new ObjectMapper();

    /** Low, because the job is assessment rather than writing. */
    private static final double TEMPERATURE = 0.0;
    private static final int MAX_TOKENS = 1200;

    private final AiCompletionProvider provider;
    private final String model;

    public GeneratorJudge(AiCompletionProvider provider, String model) {
        this.provider = provider;
        this.model = model;
    }

    /**
     * One criterion's verdict.
     *
     * @param criterion which question was asked
     * @param passed    whether the content satisfies it
     * @param evidence  a span copied from the content; required when {@code passed} is false
     */
    public record Verdict(String criterion, boolean passed, String evidence, String reason) {}

    private static final String SYSTEM = """
            You are reviewing generated study content for an English-learning app before it
            reaches learners. You are not writing content and not improving it. You are
            deciding, criterion by criterion, whether it is fit to serve.

            Judge only what you are asked about. Do not comment on formatting, JSON shape, or
            anything a program could check on its own - those are already checked.

            When a criterion fails you must quote the exact span from the content that fails
            it, copied character for character. If you cannot quote it, the criterion passes:
            a problem you cannot point at is not a finding.

            Be willing to pass. Content that is ordinary and correct should pass every
            criterion; only flag what would genuinely mislead or waste a learner.

            Return ONLY JSON:
            {"verdicts":[{"criterion":"<the id you were given>","passed":true|false,
              "evidence":"<exact quote from the content, empty when passed>",
              "reason":"<one sentence>"}]}
            """;

    public List<Verdict> judgeSentences(String targetWord, String level, String contentJson) {
        return judge("""
                CONTENT — practice sentences generated for the word "%s" at CEFR level %s:
                %s

                Criteria:
                - natural: each English sentence is something a native speaker would actually
                  write. Translationese, textbook stiffness and padding fail.
                - teaches-the-word: the sentence gives enough context that a learner meeting
                  "%s" here could infer roughly what it means. A sentence that merely contains
                  the word teaches nothing.
                - level-appropriate: the vocabulary and structure outside the target word suit
                  %s. A sentence that is harder than its level tests the wrong thing.
                """.formatted(targetWord, level, contentJson, targetWord, level));
    }

    public List<Verdict> judgeGrammarQuiz(String topic, String level, String contentJson) {
        return judge("""
                CONTENT — a grammar quiz on "%s" at CEFR level %s:
                %s

                Criteria:
                - tests-the-topic: each question actually turns on %s. A question answerable
                  from vocabulary or word order alone fails.
                - plausible-distractors: the wrong options are mistakes a learner really makes
                  on this topic. Options that are obviously wrong, or not even English words,
                  fail - they make the question free.
                - single-correct: exactly one option is defensible. If two could be argued, or
                  none is right, the question fails.
                """.formatted(topic, level, contentJson, topic));
    }

    public List<Verdict> judgeReading(String level, String contentJson) {
        return judge("""
                CONTENT — a reading passage and its comprehension questions at CEFR level %s:
                %s

                Criteria:
                - level-appropriate: sentence length and vocabulary suit %s. Note that
                  correctAnswer is a letter naming the option by position; that is intended.
                - requires-the-passage: answering needs the passage to be understood. A
                  question answerable from general knowledge, or by matching a word in the
                  question to a word in one option, fails.
                - coherent: the passage holds together and says something. Disconnected facts
                  padded to a word count fail.
                """.formatted(level, contentJson, level));
    }

    public List<Verdict> judgeDailyWords(String contentJson) {
        return judge("""
                CONTENT — a day's vocabulary set:
                %s

                Criteria:
                - useful: these are words a learner will meet again. Obscure or exam-only
                  vocabulary fails.
                - example-earns-its-place: each example sentence shows how the word is used,
                  not merely that it exists. "The X was good." fails.
                - accurate: each translation and definition is correct for the sense the
                  example uses.
                """.formatted(contentJson));
    }

    private List<Verdict> judge(String userPrompt) {
        AiCompletionProvider.CompletionResult result = provider.chatCompletionWithUsage(
                List.of(Map.of("role", "system", "content", SYSTEM),
                        Map.of("role", "user", "content", userPrompt)),
                true, MAX_TOKENS, TEMPERATURE, model);

        String content = result == null ? null : result.content();
        if (content == null || content.isBlank()) {
            // Silence is not approval. The whole reason this harness exists is that an empty
            // generation was once counted as a success.
            return List.of(new Verdict("judge", false, "", "the judge returned nothing"));
        }
        return parse(content);
    }

    static List<Verdict> parse(String content) {
        List<Verdict> verdicts = new ArrayList<>();
        try {
            String cleaned = content.trim()
                    .replaceAll("^```(?:json)?\\s*", "")
                    .replaceAll("\\s*```$", "")
                    .trim();
            JsonNode node = MAPPER.readTree(cleaned).path("verdicts");
            for (JsonNode entry : node) {
                boolean passed = entry.path("passed").asBoolean(true);
                String evidence = entry.path("evidence").asText("").trim();
                // A failure with nothing quoted is an opinion, and opinions are how a judge
                // drifts into flagging everything. The instruction says so; this enforces it.
                if (!passed && evidence.isEmpty()) {
                    continue;
                }
                verdicts.add(new Verdict(
                        entry.path("criterion").asText("unnamed").trim().toLowerCase(Locale.ROOT),
                        passed,
                        evidence,
                        entry.path("reason").asText("").trim()));
            }
        } catch (Exception e) {
            return List.of(new Verdict("judge", false, "", "unreadable verdict: " + e.getMessage()));
        }
        if (verdicts.isEmpty()) {
            return List.of(new Verdict("judge", false, "", "the judge returned no usable verdicts"));
        }
        return verdicts;
    }

    /** The criteria that failed, as report lines. Empty means the content is fit to serve. */
    public static List<String> failures(List<Verdict> verdicts) {
        List<String> lines = new ArrayList<>();
        for (Verdict verdict : verdicts) {
            if (!verdict.passed()) {
                lines.add(verdict.criterion() + ": " + verdict.reason()
                        + (verdict.evidence().isEmpty() ? "" : " — \"" + verdict.evidence() + "\""));
            }
        }
        return lines;
    }
}
