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
 *
 * <p>How short that first sentence may be is {@link #leadMinFor}, and it is deliberately
 * short: a clip takes about a fifth of its own playing time to synthesise, so the opening
 * covers a remainder several times its length.
 */
public final class SpokenReply {

    /** Below this, the whole reply is spoken in one piece: the seam would cost more than it saves. */
    private static final int SPLIT_ABOVE_CHARS = 70;

    /** A lead shorter than this is not worth a seam -- "Of course!" buys nothing. */
    private static final int LEAD_FLOOR_CHARS = 25;

    /** Nor is a remainder shorter than this. */
    private static final int REST_MIN_CHARS = 25;

    /**
     * An opening sentence longer than this is cut at a comma instead.
     *
     * <p>Measured on two real replies: their first sentences were 121 and 131 characters, and
     * speaking them cost 2.0 s where the shorter openings in the same conversation cost 0.86 s.
     * A full stop is the seam a listener never notices, but there was not one to use, and two
     * seconds of nothing is more noticeable than a pause at a comma -- which is a pause the
     * speaker was going to make anyway.
     */
    private static final int CLAUSE_FALLBACK_ABOVE_CHARS = 90;

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

    /** A comma, semicolon or colon with whitespace after it: where a speaker draws breath. */
    private static final Pattern CLAUSE = Pattern.compile("[,;:](?=\\s)");

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
        int leadMin = leadMinFor(text.length());
        int cut = sentenceCut(text, leadMin);
        if (cut < 0) {
            return new Split(text, "");
        }
        if (cut > CLAUSE_FALLBACK_ABOVE_CHARS) {
            int earlier = clauseCut(text, leadMin, cut);
            if (earlier > 0) {
                cut = earlier;
            }
        }
        return new Split(text.substring(0, cut).trim(), text.substring(cut).trim());
    }

    /** The first full stop worth cutting at, or -1 when the reply has none. */
    private static int sentenceCut(String text, int leadMin) {
        Matcher boundary = BOUNDARY.matcher(text);
        while (boundary.find()) {
            int cut = boundary.end();
            if (cut < leadMin || isAbbreviation(text, boundary.start())) {
                continue;
            }
            if (text.length() - cut < REST_MIN_CHARS) {
                // Everything after this point is shorter still, so there is no seam to find.
                return -1;
            }
            return cut;
        }
        return -1;
    }

    /**
     * The first comma inside an opening sentence that is too long to wait for, or -1.
     *
     * <p>Only ever earlier than the full stop, never later: this exists to shorten the wait,
     * and a seam that does not shorten it is a seam for nothing.
     */
    private static int clauseCut(String text, int leadMin, int sentenceEnd) {
        Matcher clause = CLAUSE.matcher(text.substring(0, sentenceEnd));
        while (clause.find()) {
            int cut = clause.end();
            if (cut >= leadMin) {
                return cut;
            }
        }
        return -1;
    }

    /**
     * The shortest first part that still covers making the second one.
     *
     * <p>Measured on the server: Kokoro synthesises at about 17 ms a character and what it
     * produces plays at about 15 characters a second. So a clip takes roughly a fifth of its
     * own playing time to make, and the first part only has to play for as long as the rest
     * takes to arrive -- itself plus the round trip. Working that through, the lead needs to be
     * about a fifth of the whole, plus a few characters for the network.
     *
     * <p>Which is why this is a proportion and not a constant. A fixed 40 characters is
     * generous for a 125-character reply and far too thin for a 400-character one, where the
     * remainder would still be synthesising when the opening ran out -- a second silence, in
     * the middle of a sentence this time.
     */
    private static int leadMinFor(int totalChars) {
        return Math.max(LEAD_FLOOR_CHARS, (int) Math.ceil(0.20 * totalChars) + 4);
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
