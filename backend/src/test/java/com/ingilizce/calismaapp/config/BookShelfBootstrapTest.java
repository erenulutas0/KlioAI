package com.ingilizce.calismaapp.config;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.atLeastOnce;
import static org.mockito.Mockito.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.ingilizce.calismaapp.entity.Book;
import com.ingilizce.calismaapp.repository.BookRepository;
import com.ingilizce.calismaapp.repository.BookSentenceRepository;
import com.ingilizce.calismaapp.service.BookImportService;
import com.ingilizce.calismaapp.service.BookLibrary;
import com.ingilizce.calismaapp.service.BookTranslationService;
import java.util.Optional;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

/**
 * The boot-time shelf loader.
 *
 * <p>This class exists because it is convenient, and convenient things that
 * spend money are how bills happen. Almost every test here is about it doing
 * nothing.
 */
class BookShelfBootstrapTest {

    private final BookImportService importService = mock(BookImportService.class);
    private final BookTranslationService translationService = mock(BookTranslationService.class);
    private final BookRepository bookRepository = mock(BookRepository.class);
    private final BookSentenceRepository sentenceRepository = mock(BookSentenceRepository.class);

    private BookShelfBootstrap bootstrap(boolean doImport, int translateMax, String slug) {
        BookShelfBootstrap bootstrap = new BookShelfBootstrap(
                importService, translationService, bookRepository, sentenceRepository);
        ReflectionTestUtils.setField(bootstrap, "importOnStartup", doImport);
        ReflectionTestUtils.setField(bootstrap, "translateOnStartup", translateMax);
        ReflectionTestUtils.setField(bootstrap, "translateSlug", slug);
        ReflectionTestUtils.setField(bootstrap, "translateInto", "Turkish");
        ReflectionTestUtils.setField(bootstrap, "translateModel", "");
        return bootstrap;
    }

    private Book bookNamed(String slug, long id) {
        Book book = new Book();
        book.setId(id);
        book.setSlug(slug);
        return book;
    }

    @Test
    @DisplayName("an ordinary deployment imports nothing and spends nothing")
    void doesNothingByDefault() {
        // The defaults in the annotations are false and 0. Every restart of
        // every production container runs this class, so the quiet path is the
        // one that has to be right.
        bootstrap(false, 0, "").run(null);

        verifyNoInteractions(importService);
        verifyNoInteractions(translationService);
    }

    @Test
    @DisplayName("importing the shelf does not also translate it")
    void importDoesNotSpendMoney() {
        when(importService.importBook(anyString(), anyString(), anyString(), anyString(),
                anyString(), anyString(), anyString()))
                .thenReturn(new BookImportService.ImportResult(1L, "slug", 3, 90, false, 0, 0));

        bootstrap(true, 0, "").run(null);

        verify(importService, atLeastOnce()).importBook(anyString(), anyString(), anyString(),
                anyString(), anyString(), anyString(), anyString());
        // The two switches are separate on purpose: importing is free and
        // repeatable, translating is neither.
        verify(translationService, never()).translateBook(anyLong(), anyString(), anyInt(), anyString());
    }

    @Test
    @DisplayName("the sentence ceiling is passed through, not ignored")
    void honoursTheCeiling() {
        when(bookRepository.findBySlug("peter-rabbit")).thenReturn(Optional.of(bookNamed("peter-rabbit", 7L)));
        when(translationService.translateBook(anyLong(), anyString(), anyInt(), anyString()))
                .thenReturn(new BookTranslationService.TranslationResult(100, 0, 0, 5000, 4000));

        bootstrap(false, 100, "peter-rabbit").run(null);

        // A ceiling that quietly became "the whole novel" would be found by the
        // invoice, not by anything else.
        verify(translationService).translateBook(eq(7L), eq("Turkish"), eq(100), anyString());
    }

    @Test
    @DisplayName("with no slug named, it works down the shelf past finished books")
    void skipsBooksThatAreAlreadyDone() {
        BookLibrary.ShelvedBook first = BookLibrary.BOOKS.get(0);
        BookLibrary.ShelvedBook second = BookLibrary.BOOKS.get(1);
        when(bookRepository.findBySlug(first.slug())).thenReturn(Optional.of(bookNamed(first.slug(), 1L)));
        when(bookRepository.findBySlug(second.slug())).thenReturn(Optional.of(bookNamed(second.slug(), 2L)));
        when(sentenceRepository.countUntranslated(1L)).thenReturn(0L);
        when(sentenceRepository.countUntranslated(2L)).thenReturn(500L);
        when(translationService.translateBook(anyLong(), anyString(), anyInt(), anyString()))
                .thenReturn(new BookTranslationService.TranslationResult(20, 480, 0, 1000, 800));

        bootstrap(false, 20, "").run(null);

        // Otherwise every deploy would re-pick the finished first book and the
        // rest of the shelf would never be translated at all.
        verify(translationService).translateBook(eq(2L), anyString(), anyInt(), anyString());
    }

    @Test
    @DisplayName("a book that was never imported is reported, not translated")
    void refusesAnUnimportedSlug() {
        when(bookRepository.findBySlug("peter-rabbit")).thenReturn(Optional.empty());

        bootstrap(false, 50, "peter-rabbit").run(null);

        verify(translationService, never()).translateBook(anyLong(), anyString(), anyInt(), anyString());
    }

    @Test
    @DisplayName("a failure here does not stop the backend from starting")
    void neverFailsTheDeployment() {
        when(bookRepository.findBySlug(anyString())).thenThrow(new RuntimeException("database is having a day"));

        // A missing book is a missing feature. A backend that will not boot is
        // an outage for the whole app.
        assertDoesNotThrow(() -> bootstrap(false, 10, "peter-rabbit").run(null));
    }
}
