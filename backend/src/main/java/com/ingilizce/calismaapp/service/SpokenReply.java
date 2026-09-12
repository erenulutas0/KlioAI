package com.ingilizce.calismaapp.service;

import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Where a spoken reply is cut in two, so the learner hears the first sentence while the rest
 * is still being made.
 *
 * <p>Kokoro costs about twenty milliseconds a character on this server -- measured, at full
 * use of all eight cores, so there is no configuration that makes it cheaper. A 289-character
 * reply took 6.0 s to synthesise, against 0.8 s for the model to write it: the voice, not the
 * thinking, is what the learner waits for. But that same reply is seventeen seconds of
 * speech, and the first sentence of it is three or four. Synthesising only that first sentence
 * costs a second or so, and the remainder finishes long before the first has finished playing.
 *
 * <p>So the wait becomes the first sentence's wait. The seam is at a full stop, where a
 * speaker pauses anyway, which is why the cut is never made mid-sentence even when that would
 * balance the halves better.
 */
public final class SpokenReply {

    /** Below this, the whole reply is spoken in one piece: the seam would cost more than it saves. */
    private static final int SPLIT_ABOVE_CHARS = 140;

    /** A lead shorter than this is not worth a seam -- "Of course!" buys nothing. */
    private static final int LEAD_MIN_CHARS = 40;

    /** Nor is a remainder shorter than this. */
    private static final int REST_MIN_CHARS = 25;

    /**
     * Words whose full stop does not end a sentence. Cutting after one of these would put the
     * seam inside a phrase -- "Mr. | Rossi will be right with you" -- which is exactly the
     * pause a listener notices.
     */
    private static final List<String> ABBREVIATIONS = List.of(
            "mr", "mrs", "ms", "dr", "prof", "st", "mt", "jr", "sr", "vs", "etc", "e.g", "i.e");

    /**
     * A full stop, question or exclamation mark that has whitespace after it. Written in
     * escapes rather than the characters themselves so the file stays ASCII: an ellipsis and
     * the curly quotes that can trail a sentence are exactly what a re-encoding mangles.
     */
    private static final Pattern BOUNDARY =
            Pattern.compile("[.!?\\u2026]+[\"'\\u201D\\u2019)\\]]*(?=\\s)");

    /** The word right before a boundary, without its punctuation. */
    private static final Pattern WORD_BEFORE =
            Pattern.compile("([A-Za-z.]+)[\"'\\u201D\\u2019)\\]]*$");

    private SpokenReply() {
    }

    /**
     * @param lead what is spoken first -- the whole reply when there is no useful seam
     * @param rest what follows, empty when the reply is spoken in one piece
     */
    public record Split(String lead, String rest) {
        public boolean isWhole() {
            return rest.isEmpty();
        }
    }

    public static Split of(String reply) {
        if (reply == null) {
            return new Split("", "");
        }
        String text = reply.trim();
        if (text.length() <= SPLIT_ABOVE_CHARS) {
            return new Split(text, "");
        }
        Matcher boundary = BOUNDARY.matcher(text);
        while (boundary.find()) {
            int cut = boundary.end();
            if (cut < LEAD_MIN_CHARS || isAbbreviation(text, boundary.start())) {
                continue;
            }
            String lead = text.substring(0, cut).trim();
            String rest = text.substring(cut).trim();
            if (rest.length() < REST_MIN_CHARS) {
                // Everything after this point is shorter still, so there is no seam to find.
                break;
            }
            return new Split(lead, rest);
        }
        return new Split(text, "");
    }

    private static boolean isAbbreviation(String text, int punctuationStart) {
        Matcher word = WORD_BEFORE.matcher(text.substring(0, punctuationStart + 1));
        if (!word.find()) {
            return false;
        }
        String candidate = word.group(1).toLowerCase();
        if (candidate.endsWith(".")) {
            candidate = candidate.substring(0, candidate.length() - 1);
        }
        return ABBREVIATIONS.contains(candidate);
    }
}
