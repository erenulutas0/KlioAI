package com.ingilizce.calismaapp.service;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Turns a public-domain book into the units the reader shows: chapters, and
 * inside them, sentences.
 *
 * <p>This is the foundation of the whole feature. A learner taps a word inside
 * a sentence and it goes into their deck with that sentence as its context, so
 * a sentence that was cut in the wrong place becomes a permanent piece of wrong
 * material in someone's review schedule. It is worth doing properly rather than
 * splitting on every period.
 *
 * <p>What real prose does that a naive splitter gets wrong:
 * <ul>
 *   <li>"Mr. Holmes rose." — three sentences by the naive rule, one in fact.</li>
 *   <li>Project Gutenberg wraps its text at about seventy columns, so almost
 *       every sentence spans lines and a line is not a unit of anything.</li>
 *   <li>Closing punctuation sits <em>inside</em> the quotation mark in English
 *       dialogue: {@code "Go away." He left.} ends its first sentence after the
 *       quote, not before it.</li>
 *   <li>An ellipsis is three sentence-ending characters in a row and none of
 *       them ends a sentence.</li>
 * </ul>
 *
 * <p>Everything here is pure text handling: no database, no network, no AI. It
 * can therefore be tested exhaustively, which is the point.
 */
public final class BookTextSegmenter {

    private BookTextSegmenter() {
    }

    /**
     * Words that end in a period without ending a sentence.
     *
     * <p>Deliberately short. Every entry is a title or abbreviation that occurs
     * in nineteenth-century English prose often enough to matter; a long list
     * of rare cases would trade real errors for imagined ones.
     */
    private static final Set<String> NON_TERMINAL_ABBREVIATIONS = new HashSet<>(Arrays.asList(
            "mr", "mrs", "ms", "dr", "st", "prof", "rev", "hon", "capt", "col",
            "gen", "lt", "sgt", "maj", "sr", "jr", "vs", "etc", "e.g", "i.e",
            "no", "vol", "fig", "inc", "ltd", "co"));

    /** Where a Project Gutenberg file stops being boilerplate and starts being the book. */
    private static final Pattern GUTENBERG_START = Pattern.compile(
            "(?im)^\\s*\\*\\*\\*\\s*START OF (?:THE|THIS) PROJECT GUTENBERG EBOOK.*?\\*\\*\\*\\s*$");

    /** Where it stops being the book again. */
    private static final Pattern GUTENBERG_END = Pattern.compile(
            "(?im)^\\s*\\*\\*\\*\\s*END OF (?:THE|THIS) PROJECT GUTENBERG EBOOK.*?\\*\\*\\*\\s*$");

    /**
     * A chapter heading on its own line: "CHAPTER I", "Chapter 12.", "II.".
     *
     * <p>Requires the line to be the whole heading, so a sentence that happens
     * to mention a chapter does not split the book in half.
     */
    private static final Pattern CHAPTER_HEADING = Pattern.compile(
            "(?i)^\\s*(?:chapter|part|book)\\s+([IVXLCDM]+|\\d+)\\b.*$|^\\s*([IVXLCDM]+)\\.?\\s*$");

    /**
     * A numbered title: {@code III. A CASE OF IDENTITY}.
     *
     * <p>How a Victorian story collection separates its stories, and the reason
     * the twelve Sherlock Holmes adventures arrived as five chapters before this
     * existed.
     */
    private static final Pattern NUMBERED_TITLE = Pattern.compile(
            "^[IVXLCDM]+\\.\\s+\\S.{1,58}$");

    /**
     * A title in capitals on a line of its own: {@code THE CAREW MURDER CASE}.
     *
     * <p>Jekyll and Hyde names its chapters this way and nothing else, so
     * without this the whole novella was one unbroken run of twelve hundred
     * sentences.
     *
     * <p>Books that centre a title in ordinary case are deliberately not matched.
     * That shape is indistinguishable from a short line of prose, and a wrongly
     * split book reads worse than one with no chapter list at all.
     */
    private static final Pattern CAPITALISED_TITLE = Pattern.compile(
            "^[A-Z][A-Z0-9 .,'’—-]{3,59}$");

    /**
     * A line that stands in for a picture the book had and this one does not:
     * {@code [Illustration]}, {@code [Picture: Book cover]}.
     *
     * <p>Twenty-nine of Peter Rabbit's ninety-one sentences are these. Left in,
     * a beginner meets one every third tap, taps it to see its meaning, and is
     * shown a translation of the word "Illustration".
     */
    private static final Pattern IMAGE_MARKER = Pattern.compile("^\\[[^\\]]*\\]$");

    /**
     * A row of asterisks used as a section break.
     *
     * <p>Carries no meaning to translate and nothing to read aloud.
     */
    private static final Pattern ORNAMENTAL_BREAK = Pattern.compile("^[*\\s]{3,}$");

    /**
     * Gutenberg's plain-text italics: {@code always _the_ woman}.
     *
     * <p>A hundred and sixteen of them across the shelf. The underscores are
     * typesetting the reader should never see, and a learner tapping {@code _the_}
     * is looking up a word that does not exist.
     */
    private static final Pattern PLAIN_TEXT_ITALICS = Pattern.compile("_([^_\\n]{1,200})_");

    /** One sentence of a book, with the position it holds in its chapter. */
    public record BookSentence(int index, String text) {
    }

    /** One chapter, in the order it appears, with its sentences. */
    public record BookChapter(int index, String title, List<BookSentence> sentences) {
    }

    /**
     * Removes Project Gutenberg's own header and footer.
     *
     * <p>The book inside is public domain; the wrapper around it is not the
     * book, carries its own licence terms, and has no business being read aloud
     * to a learner. When the markers are absent the text is returned unchanged,
     * because a file from somewhere else is not broken for lacking them.
     */
    public static String stripGutenbergBoilerplate(String raw) {
        if (raw == null || raw.isBlank()) {
            return "";
        }
        String text = raw.replace("\r\n", "\n").replace('\r', '\n');

        Matcher start = GUTENBERG_START.matcher(text);
        if (start.find()) {
            text = text.substring(start.end());
        }
        Matcher end = GUTENBERG_END.matcher(text);
        if (end.find()) {
            text = text.substring(0, end.start());
        }
        return text.strip();
    }

    /**
     * Splits a book into chapters.
     *
     * <p>A book with no recognisable headings comes back as a single chapter
     * rather than as nothing: an unusual layout should cost the reader its
     * chapter list, not the whole book.
     */
    public static List<BookChapter> segment(String bookText) {
        String text = stripGutenbergBoilerplate(bookText);
        if (text.isEmpty()) {
            return List.of();
        }

        List<String> titles = new ArrayList<>();
        List<StringBuilder> bodies = new ArrayList<>();

        for (String line : text.split("\n")) {
            if (isChapterHeading(line)) {
                titles.add(line.strip());
                bodies.add(new StringBuilder());
                continue;
            }
            if (bodies.isEmpty()) {
                // Front matter before the first heading — a dedication, a
                // preface — is the book's opening, not a discard.
                titles.add("");
                bodies.add(new StringBuilder());
            }
            bodies.get(bodies.size() - 1).append(line).append('\n');
        }

        List<BookChapter> chapters = new ArrayList<>();
        for (int i = 0; i < bodies.size(); i++) {
            List<String> raw = splitIntoSentences(bodies.get(i).toString());
            if (raw.isEmpty()) {
                // A heading with nothing under it is a table-of-contents entry,
                // not a chapter.
                continue;
            }
            List<BookSentence> sentences = new ArrayList<>(raw.size());
            for (int s = 0; s < raw.size(); s++) {
                sentences.add(new BookSentence(s, raw.get(s)));
            }
            chapters.add(new BookChapter(chapters.size(), titles.get(i), sentences));
        }
        return chapters;
    }

    static boolean isChapterHeading(String line) {
        String trimmed = line.strip();
        if (trimmed.isEmpty() || trimmed.length() > 60) {
            return false;
        }
        if (CHAPTER_HEADING.matcher(trimmed).matches()) {
            return true;
        }
        // A heading is a label, not a sentence. Requiring no closing punctuation
        // keeps a short line of dialogue or a one-line paragraph from being read
        // as the start of a chapter.
        char last = trimmed.charAt(trimmed.length() - 1);
        if (last == '.' || last == '!' || last == '?' || last == ',' || last == ';' || last == ':') {
            return false;
        }
        if (NUMBERED_TITLE.matcher(trimmed).matches()) {
            return true;
        }
        // At least two letters, so a row of asterisks or a page number does not
        // qualify as a chapter.
        long letters = trimmed.chars().filter(Character::isLetter).count();
        return letters >= 4 && CAPITALISED_TITLE.matcher(trimmed).matches();
    }

    /**
     * Splits prose into sentences.
     *
     * <p>Walks the text once and decides at each candidate terminator whether it
     * really ends a sentence. Paragraph breaks always end one: a paragraph that
     * ends without punctuation still ends.
     */
    public static List<String> splitIntoSentences(String prose) {
        List<String> sentences = new ArrayList<>();
        if (prose == null || prose.isBlank()) {
            return sentences;
        }

        // Blank lines are paragraph boundaries and must survive; every other
        // line break is Gutenberg's column wrapping and is not a boundary at all.
        String[] paragraphs = prose.split("\n\\s*\n");

        for (String paragraph : paragraphs) {
            String flat = paragraph.replaceAll("\\s*\n\\s*", " ").strip();
            flat = PLAIN_TEXT_ITALICS.matcher(flat).replaceAll("$1");
            if (flat.isEmpty() || isPresentational(flat)) {
                continue;
            }
            int start = 0;
            for (int i = 0; i < flat.length(); i++) {
                char c = flat.charAt(i);
                if (c != '.' && c != '!' && c != '?') {
                    continue;
                }
                int end = endOfTerminator(flat, i);
                if (end < 0) {
                    continue;
                }
                String candidate = flat.substring(start, end).strip();
                if (!candidate.isEmpty() && !isPresentational(candidate)) {
                    sentences.add(candidate);
                }
                start = end;
                i = end - 1;
            }
            String tail = flat.substring(start).strip();
            if (!tail.isEmpty() && !isPresentational(tail)) {
                sentences.add(tail);
            }
        }
        return sentences;
    }

    /**
     * True for a line that is typography rather than text.
     *
     * <p>These survive segmentation looking exactly like short sentences: they
     * are stored, counted, paid to translate, and shown to a learner as
     * something to read. None of that is true of them.
     */
    static boolean isPresentational(String sentence) {
        String trimmed = sentence.strip();
        return IMAGE_MARKER.matcher(trimmed).matches()
                || ORNAMENTAL_BREAK.matcher(trimmed).matches();
    }

    /**
     * Given a terminator at {@code i}, returns the index just past the end of
     * the sentence, or -1 when this terminator does not end one.
     */
    private static int endOfTerminator(String text, int i) {
        char c = text.charAt(i);

        // Run of terminators: "?!" ends a sentence, "..." does not.
        int runEnd = i;
        while (runEnd + 1 < text.length() && isTerminator(text.charAt(runEnd + 1))) {
            runEnd++;
        }
        if (c == '.' && runEnd > i) {
            // An ellipsis is a pause inside a sentence, not the end of one.
            return -1;
        }

        if (c == '.' && endsAbbreviation(text, i)) {
            return -1;
        }
        if (c == '.' && isDecimalPoint(text, i)) {
            return -1;
        }

        // Closing punctuation that belongs to this sentence: the quote in
        // `"Go away."` and the bracket in `(so he said.)`.
        int end = runEnd + 1;
        while (end < text.length() && isClosing(text.charAt(end))) {
            end++;
        }

        // A terminator at the very end of a paragraph always ends the sentence.
        if (end >= text.length()) {
            return end;
        }
        // Otherwise the next thing must be a space, or this is something like a
        // decimal or a URL rather than a sentence boundary.
        if (!Character.isWhitespace(text.charAt(end))) {
            return -1;
        }

        int next = end;
        while (next < text.length() && Character.isWhitespace(text.charAt(next))) {
            next++;
        }
        if (next >= text.length()) {
            return end;
        }
        // Lower-case after a period usually means the period was not a full
        // stop — an abbreviation the list above does not carry. Dialogue is the
        // exception: `"Go away." he muttered` is still two sentences by the
        // period, and treating it as one would swallow the line.
        char following = text.charAt(next);
        if (c == '.' && Character.isLowerCase(following) && !closedAQuote(text, runEnd + 1, end)) {
            return -1;
        }
        return end;
    }

    private static boolean isTerminator(char c) {
        return c == '.' || c == '!' || c == '?';
    }

    private static boolean isClosing(char c) {
        return c == '"' || c == '\'' || c == ')' || c == ']' || c == '\u201d' || c == '\u2019';
    }

    private static boolean closedAQuote(String text, int from, int to) {
        for (int i = from; i < to; i++) {
            char c = text.charAt(i);
            if (c == '"' || c == '\u201d' || c == '\'' || c == '\u2019') {
                return true;
            }
        }
        return false;
    }

    /** True when the period at {@code i} closes a known abbreviation. */
    private static boolean endsAbbreviation(String text, int i) {
        int wordStart = i;
        while (wordStart > 0 && !Character.isWhitespace(text.charAt(wordStart - 1))) {
            wordStart--;
        }
        String word = text.substring(wordStart, i).toLowerCase();
        // Leading punctuation from dialogue: `("Mr.` -> `mr`
        while (!word.isEmpty() && !Character.isLetterOrDigit(word.charAt(0))) {
            word = word.substring(1);
        }
        if (word.isEmpty()) {
            return false;
        }
        if (NON_TERMINAL_ABBREVIATIONS.contains(word)) {
            return true;
        }
        // A single initial: "J. M. Barrie".
        return word.length() == 1 && Character.isLetter(word.charAt(0));
    }

    private static boolean isDecimalPoint(String text, int i) {
        return i > 0 && i + 1 < text.length()
                && Character.isDigit(text.charAt(i - 1))
                && Character.isDigit(text.charAt(i + 1));
    }
}
