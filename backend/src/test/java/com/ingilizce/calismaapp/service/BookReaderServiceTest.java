package com.ingilizce.calismaapp.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.ingilizce.calismaapp.entity.Book;
import com.ingilizce.calismaapp.entity.BookProgress;
import com.ingilizce.calismaapp.entity.BookSentence;
import com.ingilizce.calismaapp.repository.BookProgressRepository;
import com.ingilizce.calismaapp.repository.BookRepository;
import com.ingilizce.calismaapp.repository.BookSentenceRepository;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

/**
 * The reader's side of the shelf.
 *
 * <p>Two things here can lose a learner's afternoon rather than merely look
 * wrong: a bookmark that moves backwards, and a window that tries to return a
 * whole novel. Most of this file is about those.
 */
class BookReaderServiceTest {

    private final BookRepository bookRepository = mock(BookRepository.class);
    private final BookSentenceRepository sentenceRepository = mock(BookSentenceRepository.class);
    private final BookProgressRepository progressRepository = mock(BookProgressRepository.class);

    private final BookReaderService service =
            new BookReaderService(bookRepository, sentenceRepository, progressRepository);

    private Book book(String slug, long id, int sentences, String level) {
        Book book = new Book();
        book.setId(id);
        book.setSlug(slug);
        book.setTitle("T " + slug);
        book.setAuthor("A");
        book.setLevel(level);
        book.setSentenceCount(sentences);
        return book;
    }

    @Test
    @DisplayName("scrolling back to re-read does not undo an afternoon")
    void progressOnlyMovesForward() {
        Book peter = book("peter-rabbit", 1L, 58, "A1");
        BookProgress existing = new BookProgress(7L, peter);
        existing.setLastSentenceIndex(40);
        when(bookRepository.findBySlug("peter-rabbit")).thenReturn(Optional.of(peter));
        when(progressRepository.findByUserIdAndBookId(7L, 1L)).thenReturn(Optional.of(existing));

        int saved = service.saveProgress(7L, "peter-rabbit", 12);

        // Progress is written as the reader scrolls. Re-reading a paragraph is
        // the most ordinary thing a reader does, and it must not reset them to
        // where they were an hour ago.
        assertEquals(40, saved);
    }

    @Test
    @DisplayName("reading on moves the bookmark")
    void progressMovesForward() {
        Book peter = book("peter-rabbit", 1L, 58, "A1");
        BookProgress existing = new BookProgress(7L, peter);
        existing.setLastSentenceIndex(40);
        when(bookRepository.findBySlug("peter-rabbit")).thenReturn(Optional.of(peter));
        when(progressRepository.findByUserIdAndBookId(7L, 1L)).thenReturn(Optional.of(existing));

        assertEquals(50, service.saveProgress(7L, "peter-rabbit", 50));
    }

    @Test
    @DisplayName("a bookmark past the end of the book is capped, not stored")
    void progressCannotRunPastTheEnd() {
        Book peter = book("peter-rabbit", 1L, 58, "A1");
        when(bookRepository.findBySlug("peter-rabbit")).thenReturn(Optional.of(peter));
        when(progressRepository.findByUserIdAndBookId(7L, 1L)).thenReturn(Optional.empty());

        // Otherwise a bad client pins a reader past the last sentence and the
        // book can never be opened at their place again.
        assertEquals(58, service.saveProgress(7L, "peter-rabbit", 99999));
    }

    @Test
    @DisplayName("a window cannot be asked to return a whole novel")
    void windowIsCapped() {
        Book sherlock = book("sherlock-adventures", 2L, 6418, "B1");
        when(bookRepository.findBySlug("sherlock-adventures")).thenReturn(Optional.of(sherlock));
        when(sentenceRepository.findWindow(anyLong(), anyInt(), anyInt()))
                .thenReturn(List.of());

        service.window("sherlock-adventures", 0, 100000);

        ArgumentCaptor<Integer> to = ArgumentCaptor.forClass(Integer.class);
        org.mockito.Mockito.verify(sentenceRepository)
                .findWindow(eq(2L), eq(0), to.capture());
        assertTrue(to.getValue() <= BookReaderService.MAX_WINDOW,
                "asked the database for " + to.getValue() + " sentences");
    }

    @Test
    @DisplayName("a negative start lands at the beginning rather than failing")
    void negativeStartIsForgiven() {
        Book peter = book("peter-rabbit", 1L, 58, "A1");
        when(bookRepository.findBySlug("peter-rabbit")).thenReturn(Optional.of(peter));
        when(sentenceRepository.findWindow(anyLong(), anyInt(), anyInt())).thenReturn(List.of());

        assertEquals(0, service.window("peter-rabbit", -20, 10).orElseThrow().from());
    }

    @Test
    @DisplayName("an untranslated sentence comes back as null, not as an empty string")
    void missingTranslationStaysMissing() {
        Book peter = book("peter-rabbit", 1L, 58, "A1");
        BookSentence sentence = new BookSentence(peter, 0, 0, null, "Once upon a time.");
        when(bookRepository.findBySlug("peter-rabbit")).thenReturn(Optional.of(peter));
        when(sentenceRepository.findWindow(anyLong(), anyInt(), anyInt()))
                .thenReturn(List.of(sentence));

        BookReaderService.ReaderWindow window = service.window("peter-rabbit", 0, 10).orElseThrow();

        // Most of the shelf is deliberately untranslated: a wrong translation
        // teaches worse than none. The client has to be able to tell "we have
        // no translation" from "the translation failed to load", and an empty
        // string looks like the second.
        assertNull(window.sentences().get(0).translation());
    }

    @Test
    @DisplayName("the shelf reads easiest first, and says which books were opened")
    void shelfIsOrderedAndMarksStartedBooks() {
        Book conrad = book("heart-of-darkness", 3L, 2291, "C1");
        Book peter = book("peter-rabbit", 1L, 58, "A1");
        when(bookRepository.findAll()).thenReturn(new ArrayList<>(List.of(conrad, peter)));
        BookProgress progress = new BookProgress(7L, peter);
        progress.setLastSentenceIndex(0);
        when(progressRepository.findByUserId(7L)).thenReturn(List.of(progress));

        List<BookReaderService.ShelfEntry> shelf = service.shelf(7L);

        assertEquals("peter-rabbit", shelf.get(0).slug());
        assertEquals("heart-of-darkness", shelf.get(1).slug());
        // "Opened and read nothing" is not "never opened", and both are index
        // zero. Only the flag tells them apart.
        assertTrue(shelf.get(0).started());
        assertEquals(0, shelf.get(0).lastSentenceIndex());
        assertTrue(!shelf.get(1).started());
    }

    @Test
    @DisplayName("a signed-out reader still gets the shelf, without bookmarks")
    void shelfWorksWithoutAUser() {
        when(bookRepository.findAll()).thenReturn(new ArrayList<>(List.of(book("x", 1L, 5, "A1"))));

        List<BookReaderService.ShelfEntry> shelf = service.shelf(null);

        assertEquals(1, shelf.size());
        assertTrue(!shelf.get(0).started());
        org.mockito.Mockito.verify(progressRepository, org.mockito.Mockito.never())
                .findByUserId(anyLong());
    }
}
