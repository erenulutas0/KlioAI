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
