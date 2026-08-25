package com.ingilizce.calismaapp.controller;

import com.ingilizce.calismaapp.security.CurrentUserContext;
import com.ingilizce.calismaapp.service.BookReaderService;
import java.util.List;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * The reading shelf as a learner sees it.
 *
 * <p>Everything here is served from the database and costs nothing per read,
 * which is what makes a library affordable at all.
 *
 * <p>These sit behind the app's ordinary sign-in, like everything else under
 * {@code /api}: SecurityConfig permits a short list of auth and billing
 * callbacks and authenticates the rest. The books themselves are public domain
 * and identical for every reader, so that is a consistency choice rather than a
 * secrecy one, and adding an exception here would widen the surface for nothing.
 *
 * <p>Progress genuinely is per-person, so the user is taken from the token and
 * never from a parameter a caller could change.
 */
@RestController
@RequestMapping("/api/books")
public class BookReaderController {

    private final BookReaderService readerService;
    private final CurrentUserContext currentUserContext;

    public BookReaderController(BookReaderService readerService,
            CurrentUserContext currentUserContext) {
        this.readerService = readerService;
        this.currentUserContext = currentUserContext;
    }

    /**
     * The shelf, easiest first.
     *
     * <p>Tolerates a missing user rather than assuming one: bookmarks simply
     * come back empty. That keeps the shelf working in the local stack, where
     * auth enforcement is off, instead of throwing on a null id.
     */
    @GetMapping
    public ResponseEntity<List<BookReaderService.ShelfEntry>> shelf() {
        Long userId = currentUserContext.getCurrentUserId().orElse(null);
        return ResponseEntity.ok(readerService.shelf(userId));
    }

    /**
     * A window of a book, starting at {@code from}.
     *
     * <p>The client asks for what fills a screen and a little more. Asking for
     * the whole of Sherlock is not refused, only trimmed.
     */
    @GetMapping("/{slug}/sentences")
    public ResponseEntity<?> sentences(@PathVariable String slug,
            @RequestParam(defaultValue = "0") int from,
            @RequestParam(defaultValue = "50") int size) {
        return readerService.window(slug, from, size)
                .<ResponseEntity<?>>map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .body(Map.of("error", "no such book: " + slug)));
    }

    /** Where this reader has got to. */
    @PutMapping("/{slug}/progress")
    public ResponseEntity<Map<String, Object>> saveProgress(@PathVariable String slug,
            @RequestBody Map<String, Object> body) {
        Long userId = currentUserContext.getCurrentUserId().orElse(null);
        if (userId == null) {
            // A bookmark belongs to somebody. Signing out does not make it
            // anonymous, it makes it nobody's.
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                    .body(Map.of("error", "Sign in to save your place"));
        }

        Object raw = body.get("sentenceIndex");
        if (!(raw instanceof Number index)) {
            return ResponseEntity.badRequest().body(Map.of("error", "sentenceIndex is required"));
        }

        try {
            int saved = readerService.saveProgress(userId, slug, index.intValue());
            return ResponseEntity.ok(Map.of("slug", slug, "lastSentenceIndex", saved));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND)
                    .body(Map.of("error", String.valueOf(e.getMessage())));
        }
    }
}
