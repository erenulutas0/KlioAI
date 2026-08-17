package com.ingilizce.calismaapp.eval;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

/**
 * Mechanical checks on what the generators produce.
 *
 * <p>These exist because of a specific, expensive failure. For three months this app served
 * five hardcoded template sentences — "Maya noticed evaluate during the trip." — to learners
 * as if a model had written them, and every one of those requests was recorded as a success.
 * The dashboard was right that the call returned HTTP 200. Nothing anywhere asked the only
 * question that mattered: is the thing that came back usable.
 *
 * <p>Nothing here judges quality; that needs a person or a second model. Everything here is
 * decidable from the payload alone — is the JSON the shape we asked for, does the sentence
 * actually contain the word it was built around, is the correct answer among the options,
 * is the quoted evidence really in the passage. Each one is cheap, and each one would have
 * caught a failure that reached production.
 *
 * <p>Pure and static on purpose: {@link GeneratorChecksTest} runs them against payloads
 * captured from the real failures, so the checks themselves are tested without spending a
 * token, and the eval runner is the only part that needs a live provider.
 *
 * <p>Every method returns the reasons it failed. An empty list is a pass.
 */
public final class GeneratorChecks {

    private GeneratorChecks() {}

    /**
     * The exact fallback sentences that shipped for three months.
     *
     * <p>Matched literally. A generator that returns one of these has not generated
     * anything, and the point of the eval is that this is never again indistinguishable
     * from working.
     */
    private static final List<String> KNOWN_FALLBACK_MARKERS = List.of(
            "maya noticed",
            "during the trip",
            "the team evaluated the plan carefully");

    /** Rough word-count bands per CEFR level, used only to catch gross mismatches. */
    private static int maxSentenceWords(String level) {
        return switch (normalizeLevel(level)) {
            case "A1", "A2" -> 14;
            case "B1" -> 20;
            case "B2" -> 28;
            default -> 40;
        };
    }

    public static List<String> sentenceFailures(Map<String, Object> json, String targetWord, String level) {
        List<String> failures = new ArrayList<>();
        List<Map<String, Object>> sentences = asMapList(json == null ? null : json.get("sentences"));
        if (sentences.isEmpty()) {
            failures.add("no sentences returned");
            return failures;
        }

        int index = 0;
        for (Map<String, Object> sentence : sentences) {
            index++;
            String english = text(sentence, "englishSentence", "sentence", "english");
            if (english.isBlank()) {
                failures.add("sentence " + index + ": empty englishSentence");
                continue;
            }
            String lower = english.toLowerCase(Locale.ROOT);
            for (String marker : KNOWN_FALLBACK_MARKERS) {
                if (lower.contains(marker)) {
                    failures.add("sentence " + index + ": is a known fallback template — \"" + english + "\"");
                }
            }
            // The whole point of generating per word: a sentence that does not contain the
            // word teaches nothing about it.
            if (!targetWord.isBlank() && !containsWordStem(english, targetWord)) {
                failures.add("sentence " + index + ": does not contain the target word \""
                        + targetWord + "\" — \"" + english + "\"");
            }
            int words = wordCount(english);
            if (words > maxSentenceWords(level)) {
                failures.add("sentence " + index + ": " + words + " words exceeds the "
                        + normalizeLevel(level) + " band of " + maxSentenceWords(level));
            }
            if (text(sentence, "turkishSentence", "translation", "turkish").isBlank()) {
                failures.add("sentence " + index + ": missing translation");
            }
        }
        return failures;
    }

    public static List<String> grammarQuizFailures(
            Map<String, Object> json, List<String> requestedVocabulary, String level) {
        List<String> failures = new ArrayList<>();
        List<Map<String, Object>> questions = asMapList(json == null ? null : json.get("questions"));
        if (questions.isEmpty()) {
            failures.add("no questions returned");
            return failures;
        }

        int index = 0;
        for (Map<String, Object> question : questions) {
            index++;
            String prompt = text(question, "question");
            if (prompt.isBlank()) {
                failures.add("question " + index + ": empty question text");
                continue;
            }
            List<String> options = asStringList(question.get("options"));
            if (options.size() < 2) {
                failures.add("question " + index + ": " + options.size() + " option(s); needs at least 2");
            }
            String correct = text(question, "correctAnswer");
            if (correct.isBlank()) {
                failures.add("question " + index + ": no correctAnswer");
            } else if (!options.isEmpty() && options.stream().noneMatch(o -> o.equalsIgnoreCase(correct))) {
                // Unanswerable: the learner cannot pick something that is not offered.
                failures.add("question " + index + ": correctAnswer \"" + correct
                        + "\" is not among the options " + options);
            }
            if (new LinkedHashSet<>(options).size() != options.size()) {
                failures.add("question " + index + ": duplicate options " + options);
            }
            // targetWord is what lets a right or wrong answer reach the review scheduler. If
            // the model claims one, the question has to actually use it.
            String target = text(question, "targetWord");
            if (!target.isBlank() && !containsWordStem(prompt, target)) {
                failures.add("question " + index + ": claims targetWord \"" + target
                        + "\" but the question does not contain it — \"" + prompt + "\"");
            }
            if (!target.isBlank() && !requestedVocabulary.isEmpty()
                    && requestedVocabulary.stream().noneMatch(v -> v.equalsIgnoreCase(target))) {
                failures.add("question " + index + ": targetWord \"" + target
                        + "\" was not in the requested vocabulary " + requestedVocabulary);
            }
        }
        return failures;
    }

    public static List<String> dailyWordsFailures(List<Map<String, Object>> words) {
        List<String> failures = new ArrayList<>();
        if (words == null || words.isEmpty()) {
            failures.add("no words returned");
            return failures;
        }

        Set<String> seen = new LinkedHashSet<>();
        int index = 0;
        for (Map<String, Object> entry : words) {
            index++;
            String word = text(entry, "word");
            if (word.isBlank()) {
                failures.add("word " + index + ": empty word");
                continue;
            }
            if (!seen.add(word.toLowerCase(Locale.ROOT))) {
                failures.add("word " + index + ": \"" + word + "\" is a duplicate in the same set");
            }
            for (String required : List.of("translation", "definition", "exampleSentence")) {
                if (text(entry, required).isBlank()) {
                    failures.add("word " + index + " (" + word + "): missing " + required);
                }
            }
            String example = text(entry, "exampleSentence");
            if (!example.isBlank() && !containsWordStem(example, word)) {
                failures.add("word " + index + " (" + word
                        + "): example sentence does not contain the word — \"" + example + "\"");
            }
        }
        return failures;
    }

    public static List<String> readingFailures(Map<String, Object> json, String level) {
        List<String> failures = new ArrayList<>();
        if (json == null) {
            failures.add("no payload returned");
            return failures;
        }
        String title = text(json, "title");
        String passage = text(json, "text", "passage");
        if (title.isBlank()) {
            failures.add("missing title");
        }
        if (passage.isBlank()) {
            // C1 reading came back empty in production more than once.
            failures.add("empty passage");
            return failures;
        }
        if (wordCount(passage) < 40) {
            failures.add("passage is only " + wordCount(passage) + " words");
        }

        List<Map<String, Object>> questions = asMapList(json.get("questions"));
        if (questions.size() < 3) {
            failures.add("only " + questions.size() + " comprehension question(s); needs at least 3");
        }
        String passageLower = passage.toLowerCase(Locale.ROOT);
        int index = 0;
        for (Map<String, Object> question : questions) {
            index++;
            if (text(question, "question").isBlank()) {
                failures.add("question " + index + ": empty question text");
            }
            List<String> options = asStringList(question.get("options"));
            String correct = text(question, "correctAnswer");
            if (!correct.isBlank() && !options.isEmpty()
                    && options.stream().noneMatch(o -> o.equalsIgnoreCase(correct))) {
                failures.add("question " + index + ": correctAnswer is not among the options");
            }
            // The model is asked to quote the sentence its answer comes from. If that quote
            // is not in the passage, the answer was not read out of the passage.
            String quote = text(question, "correctAnswerQuote");
            if (!quote.isBlank() && !passageLower.contains(quote.toLowerCase(Locale.ROOT))) {
                failures.add("question " + index + ": correctAnswerQuote is not in the passage — \""
                        + quote + "\"");
            }
        }
        return failures;
    }

    /**
     * Whether a sentence uses a word, allowing for ordinary inflection.
     *
     * <p>"evaluate" has to match "evaluated" and "evaluates" — insisting on the exact form
     * would fail correct sentences, and the cost of a false failure in an eval is that
     * people stop reading it. Matching a bare substring is too loose in the other direction
     * ("all" inside "usually"), so the match is anchored on word boundaries with a short
     * suffix allowance.
     */
    static boolean containsWordStem(String haystack, String word) {
        String stem = word.trim().toLowerCase(Locale.ROOT);
        if (stem.isEmpty()) {
            return true;
        }
        // Drop a trailing 'e' so "evaluate" also matches "evaluating".
        String root = stem.endsWith("e") && stem.length() > 3 ? stem.substring(0, stem.length() - 1) : stem;
        String pattern = "(?i)\\b" + java.util.regex.Pattern.quote(root) + "\\w{0,3}\\b";
        return java.util.regex.Pattern.compile(pattern).matcher(haystack).find();
    }

    static int wordCount(String text) {
        String trimmed = text == null ? "" : text.trim();
        return trimmed.isEmpty() ? 0 : trimmed.split("\\s+").length;
    }

    private static String normalizeLevel(String level) {
        String value = level == null ? "" : level.trim().toUpperCase(Locale.ROOT);
        return switch (value) {
            case "A1", "A2", "B1", "B2", "C1", "C2" -> value;
            default -> "B1";
        };
    }

    private static String text(Map<String, Object> map, String... keys) {
        if (map == null) {
            return "";
        }
        for (String key : keys) {
            Object value = map.get(key);
            if (value != null && !value.toString().isBlank()) {
                return value.toString().trim();
            }
        }
        return "";
    }

    @SuppressWarnings("unchecked")
    private static List<Map<String, Object>> asMapList(Object raw) {
        List<Map<String, Object>> result = new ArrayList<>();
        if (raw instanceof List<?> list) {
            for (Object item : list) {
                if (item instanceof Map<?, ?> map) {
                    result.add((Map<String, Object>) map);
                }
            }
        }
        return result;
    }

    private static List<String> asStringList(Object raw) {
        List<String> result = new ArrayList<>();
        if (raw instanceof List<?> list) {
            for (Object item : list) {
                if (item != null) {
                    result.add(item.toString().trim());
                }
            }
        }
        return result;
    }
}
