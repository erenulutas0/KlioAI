package com.ingilizce.calismaapp.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.ingilizce.calismaapp.service.BookLibrary.ShelvedBook;
import com.ingilizce.calismaapp.service.BookTextSegmenter.BookChapter;
import java.io.StringReader;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.MethodSource;

/**
 * Hand-checked translations, and the one way they fail.
 *
 * <p>A correction whose English no longer matches any sentence in the book is
 * not an error anywhere: the import runs, the book loads, and the machine's
 * version stays on screen. The work is gone and nothing says so. Most of this
 * file exists to make that impossible.
 */
class VerifiedTranslationsTest {

    static List<ShelvedBook> books() {
        return BookLibrary.BOOKS;
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("books")
    @DisplayName("every correction matches a sentence the book actually has")
    void correctionsMatchTheBook(ShelvedBook book) throws Exception {
        Map<String, String> verified = VerifiedTranslations.forSlug(book.slug());
        if (verified.isEmpty()) {
            return; // Most of the shelf has not been checked by anyone yet.
        }

        Set<String> sentences = new HashSet<>();
        for (BookChapter chapter : BookTextSegmenter.segment(BookLibrary.readText(book))) {
            for (BookTextSegmenter.BookSentence sentence : chapter.sentences()) {
                sentences.add(VerifiedTranslations.normalise(sentence.text()));
            }
        }

        List<String> orphans = new ArrayList<>();
        for (String english : verified.keySet()) {
            if (!sentences.contains(english)) {
                orphans.add(english);
            }
        }

        assertTrue(orphans.isEmpty(),
                book.slug() + " has corrections that match nothing in the book — "
                        + "they would be silently ignored:\n  " + String.join("\n  ", orphans));
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("books")
    @DisplayName("a correction is written in Turkish, with its own letters")
    void correctionsAreTurkish(ShelvedBook book) {
        Map<String, String> verified = VerifiedTranslations.forSlug(book.slug());

        for (Map.Entry<String, String> entry : verified.entrySet()) {
            String turkish = entry.getValue();
            assertFalse(turkish.isBlank(), "empty correction for: " + entry.getKey());
            // The point of a correction is that it is better than the machine's
            // answer. One that is still the English, or a stripped-down Turkish,
            // is not.
            assertFalse(turkish.equals(entry.getKey()),
                    "correction is the English again: " + entry.getKey());
        }
    }

    @Test
    @DisplayName("a line without a tab is skipped, not read as a translation")
    void refusesMalformedLines() throws Exception {
        // The separator is invisible. A line where it was lost to an editor
        // would otherwise become a key with no value, or a translation
        // attributed to the wrong sentence.
        Map<String, String> parsed = VerifiedTranslations.parse(new StringReader(
                "# a comment\n"
                        + "\n"
                        + "no tab on this line\n"
                        + "Good sentence.\tİyi cümle.\n"
                        + "Trailing tab.\t\n"), "test");

        assertEquals(Map.of("Good sentence.", "İyi cümle."), parsed);
    }

    @Test
    @DisplayName("a hand-wrapped line still matches the segmenter's one-line output")
    void whitespaceIsForgiven() {
        // The file is edited by a person; the segmenter joins its sentences onto
        // one line. Matching on exact whitespace would fail on the difference
        // and, being a silent failure, would look like the correction was never
        // written.
        assertEquals(
                VerifiedTranslations.normalise("They lived\n  underneath a   fir-tree."),
                VerifiedTranslations.normalise("They lived underneath a fir-tree."));
    }
}
