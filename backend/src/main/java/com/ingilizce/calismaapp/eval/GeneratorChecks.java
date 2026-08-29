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

    /**
     * A ceiling for runaway output, not a CEFR band.
     *
     * <p>The first version graded sentences against per-level word bands of my own
     * invention, and then failed a perfectly good sentence for being 21 words at B1. The
     * app asks for three length buckets in the same request and defines the longest as
     * "16+ words" with no upper bound, so any level can legitimately produce a long
     * sentence. A check that contradicts the prompt it is checking is just noise.
     *
     * <p>What is still worth catching is a paragraph returned where a sentence was asked
     * for, which is why this is not simply removed.
     */
    private static final int RUNAWAY_SENTENCE_WORDS = 35;

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
            if (words > RUNAWAY_SENTENCE_WORDS) {
                failures.add("sentence " + index + ": " + words
                        + " words is a paragraph, not a practice sentence — \"" + english + "\"");
            }
            // The generator's own schema, not a guess: englishSentence plus a short
            // meaning and a full-sentence translation, in the learner's source language
            // or Turkish depending on the profile. Checking invented field names is how
            // an eval reports twenty healthy sentences as broken.
            if (text(sentence, "turkishTranslation", "sourceTranslation").isBlank()) {
                failures.add("sentence " + index + ": missing the target word's translation");
            }
            if (text(sentence, "turkishFullTranslation", "sourceFullTranslation").isBlank()) {
                failures.add("sentence " + index + ": missing the full-sentence translation");
            }
        }
        return failures;
    }

    /** The gap marker the quiz prompt asks for. */
    public static final String GAP = "----";

    /** How many options the quiz prompt asks for. */
    public static final int EXPECTED_OPTIONS = 4;

    /**
     * Whether this level may answer with an error-spotting question, which has no gap.
     *
     * <p>Only B2 and above. The prompt tells A1 and A2 to use single-gap questions only
     * and B1 to make one clear grammar decision per question, so a missing gap there is
     * the model dropping the format rather than using the other one.
     */
    public static boolean allowsErrorSpotting(String level) {
        String normalized = level == null ? "" : level.trim().toUpperCase();
        return normalized.equals("B2") || normalized.equals("C1") || normalized.equals("C2");
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
            // The gap is the question. A stem with no ---- is a sentence the learner
            // is asked to complete with nothing to complete, and both this check and
            // the client's own filter used to pass it straight through: a
            // multiple-choice card with no blank in it, which is what "nonsense quiz"
            // looks like from the outside.
            //
            // B2 and above may ask the learner to spot an error instead, and those
            // legitimately carry no gap. Below that the prompt asks for single-gap
            // questions only, so a missing gap there is the model losing the format.
            if (!allowsErrorSpotting(level) && !prompt.contains(GAP)) {
                failures.add("question " + index + ": no ---- gap in \"" + prompt + "\"");
            }
            List<String> options = asStringList(question.get("options"));
            // Four, which is what the prompt asks for. The old floor of two accepted a
            // coin flip as a multiple-choice question.
            if (options.size() != EXPECTED_OPTIONS) {
                failures.add("question " + index + ": " + options.size()
                        + " option(s); the prompt asks for exactly " + EXPECTED_OPTIONS);
            }
            // Without it a wrong answer teaches nothing: the learner is told they were
            // wrong and not why, which is the moment the quiz was for.
            if (text(question, "explanation").isBlank()) {
                failures.add("question " + index + ": no explanation");
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
            // the model claims one, the question has to actually use it — but "use it" has
            // two legal shapes, and the first version of this check only allowed one. The
            // prompt says the word belongs in the sentence "unless the word itself is what
            // the question tests", and in that case the stem shows a ---- gap and the word
            // is the answer. Demanding it in the stem failed every correctly built
            // fill-in-the-blank on the learner's own vocabulary.
            // The prompt says to send "" when no vocabulary word fits, and the model
            // sometimes sends those two characters as the value rather than an empty
            // string. Same meaning, so treat it the same rather than reporting a question
            // that claims a target word made of quote marks.
            String target = stripQuotes(text(question, "targetWord"));
            if (!target.isBlank()
                    && !containsWordStem(prompt, target)
                    && !containsWordStem(correct, target)) {
                failures.add("question " + index + ": claims targetWord \"" + target
                        + "\" but neither the question nor the answer uses it — \"" + prompt
                        + "\" / \"" + correct + "\"");
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
            // Reading and the grammar quiz answer differently, and the difference is not
            // cosmetic. The reading screen labels options by position - A, B, C, D - and
            // marks the one whose letter equals correctAnswer. A correctAnswer holding the
            // option's text instead matches no letter, so no option is ever shown as
            // correct and every answer is graded wrong. That failure passed the first
            // version of this check, which looked for the text: it was inverted.
            List<String> options = asStringList(question.get("options"));
            String correct = text(question, "correctAnswer");
            if (correct.isBlank()) {
                failures.add("question " + index + ": no correctAnswer");
            } else if (!isOptionLabelInRange(correct, options.size())) {
                failures.add("question " + index + ": correctAnswer must be an option letter"
                        + " (A-" + (char) ('A' + Math.max(options.size(), 1) - 1) + ") but was \""
                        + correct + "\"; the reading screen grades by position, so this marks"
                        + " every answer wrong");
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
        // Delegates so the eval and the server-side repair cannot disagree about whether a
        // question uses a word. See WordForms for why the match is shaped as it is.
        return com.ingilizce.calismaapp.service.WordForms.contains(haystack, word);
    }

    static String stripQuotes(String value) {
        return value == null ? "" : value.replace("\"", "").replace("'", "").trim();
    }

    /** A single letter that names one of the options by position: A for the first, B the second. */
    static boolean isOptionLabelInRange(String answer, int optionCount) {
        String value = answer.trim().toUpperCase(Locale.ROOT);
        if (value.length() != 1 || optionCount <= 0) {
            return false;
        }
        int position = value.charAt(0) - 'A';
        return position >= 0 && position < optionCount;
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
