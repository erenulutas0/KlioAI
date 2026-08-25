package com.ingilizce.calismaapp.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.ingilizce.calismaapp.service.BookLibrary.ShelvedBook;
import com.ingilizce.calismaapp.service.BookTextSegmenter.BookChapter;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.MethodSource;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * The segmenter, run over the actual books that ship — not over a paragraph
 * someone wrote to make it pass.
 *
 * <p>Six real novels and story collections are a harsher test than any fixture:
 * a century of typesetting habits, dialogue, footnote marks, chapter headings in
 * four different styles. If the splitter has a bad assumption in it, it is in
 * here somewhere.
 */
class BookLibraryTest {

    private static final Logger log = LoggerFactory.getLogger(BookLibraryTest.class);

    static List<ShelvedBook> books() {
        return BookLibrary.BOOKS;
    }

    @Test
    @DisplayName("the shelf is coherent: unique slugs, a level and a licence reason each")
    void shelfIsCoherent() {
        Set<String> slugs = new HashSet<>();
        for (ShelvedBook book : BookLibrary.BOOKS) {
            assertTrue(slugs.add(book.slug()), "duplicate slug: " + book.slug());
            assertFalse(book.title().isBlank());
            assertFalse(book.author().isBlank());
            assertTrue(List.of("A1", "A2", "B1", "B2", "C1", "C2").contains(book.level()),
                    book.slug() + " has no usable level");
            // Every title carries the reason it is free to use, next to the book
            // itself. This is the question that matters most about a library of
            // other people's writing, so it does not live in a note elsewhere.
            assertFalse(book.publicDomainBasis().isBlank(),
                    book.slug() + " does not say why it is public domain");
            assertTrue(book.source().startsWith("gutenberg:"));
        }
    }

    @Test
    @DisplayName("the shelf is ordered easiest first")
    void shelfIsGraded() {
        List<String> levels = BookLibrary.BOOKS.stream().map(ShelvedBook::level).toList();
        List<String> sorted = new ArrayList<>(levels);
        sorted.sort(String::compareTo);
        assertEquals(sorted, levels, "the shelf should read A1 -> C1");
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("books")
    @DisplayName("a real book segments into sentences that look like sentences")
    void segmentsRealBooks(ShelvedBook book) throws Exception {
        String raw = BookLibrary.readText(book);
        assertFalse(raw.isBlank(), book.slug() + " is empty in the build");

        List<BookChapter> chapters = BookTextSegmenter.segment(raw);
        assertFalse(chapters.isEmpty(), book.slug() + " produced no chapters");

        List<String> sentences = new ArrayList<>();
        for (BookChapter chapter : chapters) {
            chapter.sentences().forEach(s -> sentences.add(s.text()));
        }

        log.info("{}: {} chapters, {} sentences", book.slug(), chapters.size(), sentences.size());

        assertTrue(sentences.size() > 50,
                book.slug() + " produced only " + sentences.size() + " sentences");

        // Nothing of Project Gutenberg's own wrapper survives into the text a
        // learner reads. Its licence terms are not part of the book.
        for (String sentence : sentences) {
            assertFalse(sentence.contains("PROJECT GUTENBERG"),
                    book.slug() + " leaked boilerplate: " + sentence);
            assertFalse(sentence.contains("www.gutenberg.org"),
                    book.slug() + " leaked a Gutenberg link: " + sentence);
        }

        // A sentence a learner taps a word in has to be a sentence. A splitter
        // that fell apart would show up here as an average of a few characters
        // or as one enormous run.
        double average = sentences.stream().mapToInt(String::length).average().orElse(0);
        assertTrue(average > 30 && average < 400,
                book.slug() + " has an implausible average sentence length: " + average);

        long absurdlyLong = sentences.stream().filter(s -> s.length() > 1500).count();
        assertTrue(absurdlyLong <= sentences.size() * 0.01,
                book.slug() + " left " + absurdlyLong + " unsplit runs");
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("books")
    @DisplayName("both boundary markers are found in the file they belong to")
    void boundaryMarkersActuallyMatch(ShelvedBook book) throws Exception {
        String raw = BookLibrary.readRaw(book);

        // The dangerous failure here is silence. A marker with a typo in it, or
        // one written from a different edition of the same book, trims nothing
        // at all: the import succeeds, the front matter comes back, and nobody
        // finds out until a learner reads a printer's colophon as sentence four.
        assertTrue(raw.contains(book.startsAt()),
                book.slug() + " never contains its startsAt: " + book.startsAt());
        if (!book.endsAt().isBlank()) {
            assertTrue(raw.contains(book.endsAt()),
                    book.slug() + " never contains its endsAt: " + book.endsAt());
        }

        String trimmed = BookLibrary.readText(book);
        assertTrue(trimmed.startsWith(book.startsAt()),
                book.slug() + " does not begin at its own first line");
        // Trimming to a fraction of the file would mean a marker matched
        // somewhere absurd — in the table of contents, say, which names every
        // chapter the book has.
        assertTrue(trimmed.length() > raw.length() * 0.5,
                book.slug() + " lost more than half its text to trimming");
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("books")
    @DisplayName("a book begins with its own first sentence, not its title page")
    void frontMatterIsGone(ShelvedBook book) throws Exception {
        List<BookChapter> chapters = BookTextSegmenter.segment(BookLibrary.readText(book));
        String first = chapters.get(0).sentences().get(0).text();

        assertTrue(book.startsAt().startsWith(first) || first.startsWith(book.startsAt()),
                book.slug() + " opens on something other than its first line: " + first);
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("books")
    @DisplayName("nothing a learner taps is typography rather than text")
    void noPresentationalSentences(ShelvedBook book) throws Exception {
        for (BookChapter chapter : BookTextSegmenter.segment(BookLibrary.readText(book))) {
            for (BookTextSegmenter.BookSentence sentence : chapter.sentences()) {
                String text = sentence.text();

                // Spelled out here rather than delegated to
                // BookTextSegmenter.isPresentational on purpose. Asking the
                // filter whether its own output got filtered is not a test:
                // break the predicate and the production path and the assertion
                // fail together, so the suite stays green while twenty-nine
                // "[Illustration]" sentences walk back into the A1 book. That
                // is not hypothetical — this test was written that way first,
                // and it passed against exactly that mutation.
                assertFalse(text.startsWith("[") && text.endsWith("]"),
                        book.slug() + " kept an image marker: " + text);
                assertFalse(text.replace(" ", "").matches("[*]{2,}"),
                        book.slug() + " kept an ornamental break: " + text);

                // Gutenberg's plain-text italics. A learner tapping _the_ is
                // looking up a word that does not exist.
                assertFalse(text.matches(".*_[^_]{1,200}_.*"),
                        book.slug() + " kept italics markup: " + text);
            }
        }
    }

    @Test
    @DisplayName("the whole shelf is a sane amount of text to translate")
    void wholeShelfIsAffordable() throws Exception {
        int total = 0;
        for (ShelvedBook book : BookLibrary.BOOKS) {
            for (BookChapter chapter : BookTextSegmenter.segment(BookLibrary.readText(book))) {
                total += chapter.sentences().size();
            }
        }
        log.info("Whole shelf: {} sentences", total);

        // Translation happens once per sentence, ever. This is the number the
        // whole feature's cost is a multiple of, so it is worth failing loudly
        // if someone shelves a library instead of a shelf.
        assertTrue(total > 1000, "the shelf is suspiciously small: " + total);
        assertTrue(total < 60000, "the shelf grew past what one import should translate: " + total);
    }
}
