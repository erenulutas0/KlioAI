package com.ingilizce.calismaapp.controller;

import com.ingilizce.calismaapp.security.CurrentUserContext;
import com.ingilizce.calismaapp.entity.Book;
import com.ingilizce.calismaapp.repository.BookRepository;
import com.ingilizce.calismaapp.service.BookImportService;
import com.ingilizce.calismaapp.service.BookLibrary;
import com.ingilizce.calismaapp.service.BookTranslationService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Operator controls for the reading shelf: put the shipped books in the
 * database, and pay to translate them.
 *
 * <p>Admin-only, and not because the data is secret — the books are public
 * domain and the translations are shown to everyone. Translation spends money
 * per call, so an endpoint anyone could hit is an endpoint anyone could run up
 * a bill with. Importing is free but rewrites what every reader sees, which is
 * not something a learner should be able to trigger either.
 *
 * <p>These run once per book, by hand, and then never again.
 */
@RestController
@RequestMapping("/api/admin/books")
public class BookAdminController {

    private static final Logger log = LoggerFactory.getLogger(BookAdminController.class);

    private final BookImportService importService;
    private final BookTranslationService translationService;
    private final BookRepository bookRepository;
    private final CurrentUserContext currentUserContext;

    public BookAdminController(BookImportService importService,
            BookTranslationService translationService,
            BookRepository bookRepository,
            CurrentUserContext currentUserContext) {
        this.importService = importService;
        this.translationService = translationService;
        this.bookRepository = bookRepository;
        this.currentUserContext = currentUserContext;
    }

    private boolean forbidden() {
        return currentUserContext.shouldEnforceAuthz() && !currentUserContext.hasRole("ADMIN");
    }

    /**
     * Imports the shipped shelf, or one book of it.
     *
     * <p>Free and repeatable: it re-segments the text that is already in the
     * build, so running it after a segmenter fix corrects every book in place.
     * Translations already stored are lost with the old rows, which is correct —
     * a sentence that has been re-cut is not the sentence that was translated.
     */
    @PostMapping("/import")
    public ResponseEntity<Map<String, Object>> importShelf(@RequestParam(required = false) String slug) {
        if (forbidden()) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN)
                    .body(Map.of("error", "Admin role required"));
        }

        List<BookLibrary.ShelvedBook> shelf = BookLibrary.BOOKS.stream()
                .filter(b -> slug == null || slug.isBlank() || b.slug().equals(slug))
                .toList();
        if (shelf.isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("error", "no shelved book named " + slug));
        }

        List<Map<String, Object>> imported = new ArrayList<>();
        int totalSentences = 0;
        for (BookLibrary.ShelvedBook book : shelf) {
            try {
                BookImportService.ImportResult result = importService.importBook(
                        book.slug(), book.title(), book.author(), "English",
                        book.level(), book.source(), BookLibrary.readText(book));
                totalSentences += result.sentences();
                imported.add(Map.of(
                        "slug", result.slug(),
                        "bookId", result.bookId(),
                        "chapters", result.chapters(),
                        "sentences", result.sentences(),
                        "replaced", result.replaced(),
                        "verifiedApplied", result.verifiedApplied(),
                        "verifiedOnFile", result.verifiedOnFile()));
            } catch (Exception e) {
                // One unreadable book must not stop the shelf: the others are
                // fine and the operator needs to know which failed.
                log.warn("Import failed for {}: {}", book.slug(), e.toString());
                imported.add(Map.of("slug", book.slug(), "error", String.valueOf(e.getMessage())));
            }
        }

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("books", imported);
        body.put("totalSentences", totalSentences);
        return ResponseEntity.ok(body);
    }

    /**
     * Translates a book, or part of one.
     *
     * <p>{@code max} exists so the first run on a new shelf can be a small one:
     * translate a short book, read the measured token counts below, and only
     * then decide to spend the rest.
     */
    @PostMapping("/{slug}/translate")
    public ResponseEntity<Map<String, Object>> translate(@PathVariable String slug,
            @RequestParam(defaultValue = "0") int max,
            @RequestParam(defaultValue = "Turkish") String into,
            @RequestParam(defaultValue = "") String model) {
        if (forbidden()) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN)
                    .body(Map.of("error", "Admin role required"));
        }

        Book book = bookRepository.findBySlug(slug).orElse(null);
        if (book == null) {
            return ResponseEntity.badRequest().body(Map.of("error", "not imported: " + slug));
        }

        BookTranslationService.TranslationResult result =
                translationService.translateBook(book.getId(), into, max, model);

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("slug", slug);
        body.put("translated", result.translated());
        body.put("remaining", result.remaining());
        body.put("failedBatches", result.failedBatches());
        body.put("promptTokens", result.promptTokens());
        body.put("completionTokens", result.completionTokens());
        body.put("totalTokens", result.totalTokens());
        // The number the decision actually turns on. Measured, not assumed:
        // multiply by the sentences left in the library and the whole bill is
        // known before any of it is spent.
        body.put("tokensPerSentence", result.translated() == 0
                ? 0
                : Math.round((double) result.totalTokens() / result.translated()));
        return ResponseEntity.ok(body);
    }

    /** What is on the shelf right now, and how much of it is translated. */
    @GetMapping("/status")
    public ResponseEntity<List<Map<String, Object>>> status() {
        if (forbidden()) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }
        List<Map<String, Object>> rows = new ArrayList<>();
        for (Book book : bookRepository.findAll()) {
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("slug", book.getSlug());
            row.put("title", book.getTitle());
            row.put("level", book.getLevel());
            row.put("sentences", book.getSentenceCount());
            rows.add(row);
        }
        return ResponseEntity.ok(rows);
    }
}
