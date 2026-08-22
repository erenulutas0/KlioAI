package com.ingilizce.calismaapp.service;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Makes a reading question's answer say what the screen grades on.
 *
 * <p>The reading screen labels options by position — A, B, C, D — and marks the one whose
 * letter equals {@code correctAnswer}. When the model writes the answer out in full instead,
 * no option matches and every answer the learner gives is graded wrong, with the explanation
 * underneath confirming the choice they were just told was incorrect.
 *
 * <p>Applied in two places on purpose, which is why it lives here rather than in either of
 * them. Generation repairs new passages; the read path repairs the ones already sitting in
 * the daily-content cache, which outlive a deploy — a prompt fix that ships at noon does
 * nothing for a passage generated at midnight, and today's learners are the ones affected.
 *
 * <p>Nothing is guessed. The rewrite happens only when the answer is not already a valid
 * letter and does exactly equal one of the options; anything else is left alone for the eval
 * to report.
 */
public final class ReadingAnswers {

    private ReadingAnswers() {}

    @SuppressWarnings("unchecked")
    public static Map<String, Object> normalize(Map<String, Object> payload) {
        if (payload == null || !(payload.get("questions") instanceof List<?> questions)) {
            return payload;
        }
        boolean changed = false;
        List<Object> repaired = new ArrayList<>();
        for (Object question : questions) {
            Object rewritten = question;
            if (question instanceof Map<?, ?> map && map.get("options") instanceof List<?> options) {
                String answer = map.get("correctAnswer") == null
                        ? "" : map.get("correctAnswer").toString().trim();
                if (!answer.isEmpty() && !isLetterInRange(answer, options.size())) {
                    int position = indexOfOption(options, answer);
                    if (position >= 0) {
                        Map<String, Object> copy = new HashMap<>((Map<String, Object>) map);
                        copy.put("correctAnswer", String.valueOf((char) ('A' + position)));
                        rewritten = copy;
                        changed = true;
                    }
                }
            }
            repaired.add(rewritten);
        }
        if (!changed) {
            return payload;
        }
        Map<String, Object> result = new HashMap<>(payload);
        result.put("questions", repaired);
        return result;
    }

    /** True when the answer already names an option by position. */
    public static boolean isLetterInRange(String answer, int optionCount) {
        if (answer == null || answer.length() != 1 || optionCount <= 0) {
            return false;
        }
        int position = Character.toUpperCase(answer.charAt(0)) - 'A';
        return position >= 0 && position < optionCount;
    }

    private static int indexOfOption(List<?> options, String answer) {
        for (int i = 0; i < options.size(); i++) {
            Object option = options.get(i);
            if (option != null && option.toString().trim().equalsIgnoreCase(answer)) {
                return i;
            }
        }
        return -1;
    }
}
