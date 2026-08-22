package com.ingilizce.calismaapp.service;

import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * Builds the user message for translation-practice sentence generation.
 *
 * <p>This lived inline in the controller as seventy lines of {@code StringBuilder.append}
 * between a cache lookup and an exception handler. It is the most heavily tuned prompt in
 * the app — target-word rules, level and length distribution, grammar-pattern slots, context
 * slots, banned meta-sentence frames, starter avoidance — and none of it could be read
 * without the surrounding request handling, or exercised without an HTTP call.
 *
 * <p>Pulling it out is what lets the offline eval send the <em>real</em> message rather than
 * an approximation of it. An eval that writes its own prompt tests the eval.
 *
 * <p>Pure and static: same inputs, same string, no request, no user, no clock.
 */
public final class PracticeSentencePrompt {

    private PracticeSentencePrompt() {}

    /**
     * Everything the prompt depends on, named.
     *
     * @param targetWords        the words the sentences must be built around
     * @param targetWordMeanings lower-cased word to the learner's own saved meaning
     * @param direction          normalized practice direction, e.g. {@code SOURCE_TO_TARGET}
     * @param levels             requested CEFR levels
     * @param lengths            requested length buckets
     * @param grammarPatterns    soft per-sentence grammar slots from {@link PromptCatalog}
     * @param recentStarters     opening words this learner has already been shown
     * @param profile            source/target languages
     * @param fresh              the learner asked for a new set rather than the cached one
     * @param variationSeed      appended only when {@code fresh}; the caller supplies it so
     *                           this stays a pure function and the eval stays reproducible
     */
    public record Inputs(
            List<String> targetWords,
            Map<String, String> targetWordMeanings,
            String direction,
            List<String> levels,
            List<String> lengths,
            List<String> grammarPatterns,
            List<String> recentStarters,
            LearningLanguageProfile profile,
            boolean fresh,
            long variationSeed
    ) {}

    public static String build(Inputs in) {
        StringBuilder prompt = new StringBuilder();
        prompt.append("Return EXACTLY 5 natural translation-practice sentences inside a JSON object with key 'sentences'.\n");
        if (in.targetWords().size() == 1) {
            prompt.append("Target word: ").append(in.targetWords().get(0)).append("\n");
            appendMeaningHint(prompt, in.targetWords().get(0), in.targetWordMeanings());
            prompt.append("Every English sentence must use this target word naturally, without quotation marks.\n");
        } else {
            prompt.append("Target words: ").append(String.join(", ", in.targetWords())).append("\n");
            appendMeaningHints(prompt, in.targetWords(), in.targetWordMeanings());
            prompt.append(
                    "Multi-word mode: use exactly ONE target word per sentence, rotate through the target words, and NEVER treat the comma-separated list as one phrase.\n");
            prompt.append("Target words must appear naturally, without quotation marks.\n");
        }
        prompt.append("Practice direction: ").append(in.direction()).append("\n");
        if (isSourceToTargetDirection(in.direction()) || "MIXED".equals(in.direction())) {
            prompt.append(
                    "For source-to-English practice, think of the source-language sentence first, then provide the natural English equivalent. Avoid awkward literal translation.\n");
        }
        prompt.append("Requested level/length combinations:\n");
        for (String level : in.levels()) {
            for (String length : in.lengths()) {
                // Literal \n, not %n: the prompt must be byte-identical whatever OS builds it.
                prompt.append(String.format("- Level: %s, Length: %s\n", level, length));
            }
        }
        prompt.append("Distribute the 5 sentences across these combinations as evenly as possible.\n");
        prompt.append("Soft grammar pattern slots, use when natural:\n");
        for (int i = 0; i < in.grammarPatterns().size(); i++) {
            prompt.append(String.format("- Sentence %d: %s\n", i + 1, in.grammarPatterns().get(i)));
        }
        prompt.append("Use these real-life context slots exactly once:\n");
        prompt.append("- travel, transport, or appointment\n");
        prompt.append("- work, school, or planning\n");
        prompt.append("- family, friend, or daily life\n");
        prompt.append("- news, public service, or community\n");
        prompt.append("- personal decision, problem, or opinion\n");
        prompt.append("Avoid generic textbook frames and avoid paraphrasing the same idea with tiny wording changes.\n");
        prompt.append("If the word has multiple natural senses/collocations, cover more than one.\n");
        // These frames are how a "use the word" instruction gets satisfied without teaching
        // the word: a sentence about the word rather than one that uses it.
        prompt.append(
                "Do NOT write meta sentences about the target word itself. Forbidden frames: \"the word ...\", \"used ... to describe\", \"explained ...\", \"heard ...\", \"practice ...\", \"remember ...\".\n");
        prompt.append("Do not start more than one sentence with a personal pronoun. At least one sentence must be a question.\n");
        if (!in.recentStarters().isEmpty()) {
            prompt.append("This learner has recently seen sentences starting with: ")
                    .append(String.join(", ", in.recentStarters()))
                    .append(". Avoid starting any new sentence with these same words.\n");
        }
        prompt.append("Prefer natural, idiomatic ")
                .append(in.profile().sourceLanguage())
                .append(" phrasing that a native speaker would actually write; avoid literal, translated-sounding wording.\n");
        if (isTurkishSource(in.profile())) {
            prompt.append(
                    "Think in Turkish first for the full-sentence translation, not as a word-for-word translation of the English sentence.\n");
        } else {
            prompt.append("All source-language translations must be in ")
                    .append(in.profile().sourceLanguage())
                    .append(". Do not output Turkish translations for this request.\n");
        }
        prompt.append("Lengths must be meaningfully different: short=4-8 words, medium=9-15 words, long=16+ words.\n");
        prompt.append("Good example for target word 'delay': The flight was delayed by heavy rain.\n");
        prompt.append("Bad example for target word 'delay': A short news article used \"delay\" to describe the problem.\n");
        // Three consecutive eval runs flagged the same shape: "The train delays commuters",
        // "The train delays frequently". The word is present, the grammar parses, and no
        // native speaker would write it - a train is delayed, it does not delay people. A
        // mechanical check cannot see this, so the instruction has to.
        prompt.append(
                "Give the word the grammatical role and the subject and object a native speaker "
                        + "would give it. A train is delayed; it does not delay commuters. If the "
                        + "natural sentence needs the passive, the past, or a different subject, "
                        + "write it that way rather than forcing the word into the active voice.");
        if (in.fresh()) {
            prompt.append("\nGenerate a fresh new set. Avoid reusing common previous examples.");
            prompt.append("\nvariationSeed=").append(in.variationSeed());
        }
        return prompt.toString();
    }

    private static void appendMeaningHint(StringBuilder prompt, String targetWord, Map<String, String> meanings) {
        String meaning = meaningFor(targetWord, meanings);
        if (!meaning.isBlank()) {
            prompt.append("Known learner meaning: ").append(meaning).append("\n");
        }
    }

    private static void appendMeaningHints(StringBuilder prompt, List<String> targetWords, Map<String, String> meanings) {
        List<String> hints = targetWords.stream()
                .map(word -> {
                    String meaning = meaningFor(word, meanings);
                    return meaning.isBlank() ? "" : word + " = " + meaning;
                })
                .filter(value -> !value.isBlank())
                .toList();
        if (!hints.isEmpty()) {
            prompt.append("Known learner meanings: ").append(String.join("; ", hints)).append("\n");
        }
    }

    private static String meaningFor(String targetWord, Map<String, String> meanings) {
        if (targetWord == null || meanings == null || meanings.isEmpty()) {
            return "";
        }
        return meanings.getOrDefault(targetWord.trim().toLowerCase(Locale.ROOT), "");
    }

    static boolean isSourceToTargetDirection(String direction) {
        return "SOURCE_TO_TARGET".equals(direction) || "TR_TO_EN".equals(direction);
    }

    static boolean isTurkishSource(LearningLanguageProfile profile) {
        return profile != null && "Turkish".equalsIgnoreCase(profile.sourceLanguage());
    }
}
