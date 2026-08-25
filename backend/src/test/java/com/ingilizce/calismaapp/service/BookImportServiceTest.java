package com.ingilizce.calismaapp.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.ingilizce.calismaapp.entity.Book;
import com.ingilizce.calismaapp.entity.BookSentence;
import com.ingilizce.calismaapp.repository.BookRepository;
import com.ingilizce.calismaapp.repository.BookSentenceRepository;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.transaction.annotation.Transactional;

/**
 * Importing a book is a one-off an operator runs, which is exactly why it needs
 * pinning: nobody watches it, and a book that shelved itself wrongly stays
 * wrong in front of every learner who opens it.
 */
@SpringBootTest
@Transactional
class BookImportServiceTest {

    @Autowired
    private BookImportService importService;

    @Autowired
    private BookRepository bookRepository;

    @Autowired
    private BookSentenceRepository sentenceRepository;

    private static final String BOOK = "CHAPTER I\n"
            + "\n"
            + "To Sherlock Holmes she is always the woman. I have seldom heard\n"
            + "him mention her under any other name.\n"
            + "\n"
            + "CHAPTER II\n"
            + "\n"
            + "It was not that he felt any emotion akin to love for Irene Adler.\n";

    @BeforeEach
    void clean() {
        sentenceRepository.deleteAll();
        bookRepository.deleteAll();
    }

    private BookImportService.ImportResult importBook(String text) {
        return importService.importBook("scandal-in-bohemia", "A Scandal in Bohemia",
                "Arthur Conan Doyle", "English", "B1", "gutenberg:1661", text);
    }

    @Test
    @DisplayName("a book arrives with its sentences numbered across chapters")
    void importsAndNumbersAcrossTheWholeBook() {
        BookImportService.ImportResult result = importBook(BOOK);

        assertEquals(3, result.sentences());
        assertEquals(2, result.chapters());
        assertFalse(result.replaced());

        List<BookSentence> all = sentenceRepository.findWindow(result.bookId(), 0, 100);
        // Numbering runs through the book, not restarting per chapter: progress
        // points at one of these, so it has to be a position in the book.
        assertEquals(List.of(0, 1, 2), all.stream().map(BookSentence::getSentenceIndex).toList());
        assertEquals("CHAPTER II", all.get(2).getChapterTitle());
        assertEquals(1, all.get(2).getChapterIndex());
    }

    @Test
    @DisplayName("the shelf knows a book's length without counting rows")
    void keepsTheDenormalisedCount() {
        BookImportService.ImportResult result = importBook(BOOK);

        Book book = bookRepository.findById(result.bookId()).orElseThrow();
        assertEquals(3, book.getSentenceCount());
        assertEquals(3, sentenceRepository.countByBookId(book.getId()));
    }

    @Test
    @DisplayName("re-importing replaces the text instead of shelving a second copy")
    void reimportIsIdempotent() {
        importBook(BOOK);
        BookImportService.ImportResult again = importBook(BOOK);

        assertTrue(again.replaced());
        assertEquals(1, bookRepository.findAll().size());
        assertEquals(3, sentenceRepository.countByBookId(again.bookId()));
    }

    @Test
    @DisplayName("a corrected edition replaces the old sentences, none left behind")
    void reimportDropsTheOldText() {
        importBook(BOOK);
        BookImportService.ImportResult shorter = importBook(
                "CHAPTER I\n\nOnly one sentence survives this edition.\n");

        assertEquals(1, shorter.sentences());
        assertEquals(1, sentenceRepository.countByBookId(shorter.bookId()));
    }

    @Test
    @DisplayName("page furniture is not shelved as reading material")
    void dropsFragments() {
        // "II." and a printer's mark are not sentences a learner should tap
        // words in, and not text worth paying to translate.
        BookImportService.ImportResult result = importBook(
                "CHAPTER I\n\nII.\n\nA real sentence with something to read.\n\n[5]\n");

        assertEquals(1, result.sentences());
    }

    @Test
    @DisplayName("nothing readable is refused, not shelved empty")
    void refusesEmptyBooks() {
        assertThrows(IllegalArgumentException.class,
                () -> importBook("   \n\n   "));
        assertThrows(IllegalArgumentException.class,
                () -> importBook("CHAPTER I\n\nII.\n\n[5]\n"));
        assertTrue(bookRepository.findAll().isEmpty());
    }

    @Test
    @DisplayName("Gutenberg's wrapper never reaches a reader")
    void stripsBoilerplateOnTheWayIn() {
        BookImportService.ImportResult result = importBook(
                "The Project Gutenberg eBook, with its own licence terms attached.\n"
                        + "*** START OF THE PROJECT GUTENBERG EBOOK SCANDAL ***\n"
                        + "\n"
                        + "The story itself begins here and reads normally.\n"
                        + "\n"
                        + "*** END OF THE PROJECT GUTENBERG EBOOK SCANDAL ***\n"
                        + "More licence terms follow.\n");

        List<BookSentence> all = sentenceRepository.findWindow(result.bookId(), 0, 100);
        assertEquals(1, all.size());
        assertEquals("The story itself begins here and reads normally.", all.get(0).getText());
    }

    @Test
    @DisplayName("a freshly imported book has no translations yet")
    void translationIsASeparateStep() {
        // Segmenting is free and deterministic; translating costs money and can
        // fail halfway. Keeping them apart means a network error cannot lose a
        // correctly segmented book.
        BookImportService.ImportResult result = importBook(BOOK);

        assertEquals(3, sentenceRepository.findUntranslated(result.bookId()).size());
    }
}
