package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.entity.Book;
import com.ingilizce.calismaapp.entity.BookProgress;
import com.ingilizce.calismaapp.entity.BookSentence;
import com.ingilizce.calismaapp.repository.BookProgressRepository;
import com.ingilizce.calismaapp.repository.BookRepository;
import com.ingilizce.calismaapp.repository.BookSentenceRepository;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * What the reader screen asks for: a shelf, a window of a book, and a
 * bookmark.
 *
 * <p>Reading is served entirely from the database. Nothing here calls a model,
 * which is the whole reason the feature is affordable: a chapter costs the same
 * whether one person reads it or ten thousand do.
 *
 * <p>Sentences come back in windows rather than whole books. Sherlock is six
 * thousand sentences; a reader who opens at their bookmark should not wait for
 * the five thousand they have already read.
 */
@Service
public class BookReaderService {

    /**
     * How many sentences one request may return.
     *
     * <p>A ceiling rather than a page size: the client asks for what it needs
     * to fill a screen and a little more, and this stops a crafted request from
     * asking for a novel.
     */
    static final int MAX_WINDOW = 200;

    private final BookRepository bookRepository;
    private final BookSentenceRepository sentenceRepository;
    private final BookProgressRepository progressRepository;

    public BookReaderService(BookRepository bookRepository,
            BookSentenceRepository sentenceRepository,
            BookProgressRepository progressRepository) {
        this.bookRepository = bookRepository;
        this.sentenceRepository = sentenceRepository;
        this.progressRepository = progressRepository;
    }

    /** One shelf entry, with where this reader left off in it. */
    public record ShelfEntry(String slug, String title, String author, String level,
            int sentenceCount, int lastSentenceIndex, boolean started) {
    }

    /** One sentence as the reader shows it. */
    public record ReaderSentence(int index, int chapterIndex, String chapterTitle,
            String text, String translation) {
    }

    /** A window of a book, and enough context to page around it. */
    public record ReaderWindow(String slug, String title, int from, int size,
            int sentenceCount, List<ReaderSentence> sentences) {
    }

    /**
     * The shelf, easiest first, with this reader's bookmarks folded in.
     *
     * <p>One query for progress rather than one per book: six books today, but
     * a shelf is the kind of thing that grows and an N+1 here would grow with
     * it silently.
     */
    public List<ShelfEntry> shelf(Long userId) {
        Map<Long, BookProgress> progressByBook = new HashMap<>();
        if (userId != null) {
            for (BookProgress progress : progressRepository.findByUserId(userId)) {
                if (progress.getBook() != null) {
                    progressByBook.put(progress.getBook().getId(), progress);
                }
            }
        }

        List<Book> books = new ArrayList<>(bookRepository.findAll());
        // The shelf's order is a teaching decision, not a database one: a
        // beginner should meet Peter Rabbit before Conrad. Null levels sort
        // last rather than crashing the comparison.
        books.sort((a, b) -> {
            String left = a.getLevel() == null ? "ZZ" : a.getLevel();
            String right = b.getLevel() == null ? "ZZ" : b.getLevel();
            int byLevel = left.compareTo(right);
            return byLevel != 0 ? byLevel : a.getSlug().compareTo(b.getSlug());
        });

        List<ShelfEntry> shelf = new ArrayList<>();
        for (Book book : books) {
            BookProgress progress = progressByBook.get(book.getId());
            shelf.add(new ShelfEntry(
                    book.getSlug(),
                    book.getTitle(),
                    book.getAuthor(),
                    book.getLevel(),
                    book.getSentenceCount() == null ? 0 : book.getSentenceCount(),
                    progress == null ? 0 : progress.getLastSentenceIndex(),
                    // "Never opened" and "opened, read nothing" are different
                    // states and the shelf shows them differently.
                    progress != null));
        }
        return shelf;
    }

    /**
     * A window of a book.
     *
     * @param from the first sentence index to return; negative is treated as
     *             the start rather than refused, because a client that has lost
     *             its place should land at the beginning of the book
     */
    public Optional<ReaderWindow> window(String slug, int from, int size) {
        Book book = bookRepository.findBySlug(slug).orElse(null);
        if (book == null) {
            return Optional.empty();
        }

        int start = Math.max(0, from);
        int count = size <= 0 ? 50 : Math.min(size, MAX_WINDOW);

        List<ReaderSentence> sentences = new ArrayList<>();
        for (BookSentence sentence : sentenceRepository.findWindow(book.getId(), start, start + count)) {
            sentences.add(new ReaderSentence(
                    sentence.getSentenceIndex(),
                    sentence.getChapterIndex(),
                    sentence.getChapterTitle(),
                    sentence.getText(),
                    // Null rather than empty, so the client shows "no
                    // translation" instead of a blank line that looks like one
                    // failed to load. Most of the shelf is untranslated on
                    // purpose: a wrong translation teaches worse than none.
                    sentence.getTranslation()));
        }

        return Optional.of(new ReaderWindow(
                book.getSlug(),
                book.getTitle(),
                start,
                sentences.size(),
                book.getSentenceCount() == null ? 0 : book.getSentenceCount(),
                sentences));
    }

    /**
     * Moves a reader's bookmark.
     *
     * <p>Only ever forwards. Progress is written as the reader scrolls, and
     * scrolling back to re-read a paragraph must not undo an afternoon: the
     * bookmark answers "how far have I got", not "where am I looking". A reader
     * who genuinely wants to start over is served by a reset, not by a scroll.
     */
    @Transactional
    public int saveProgress(Long userId, String slug, int sentenceIndex) {
        Book book = bookRepository.findBySlug(slug).orElseThrow(
                () -> new IllegalArgumentException("no such book: " + slug));

        BookProgress progress = progressRepository.findByUserIdAndBookId(userId, book.getId())
                .orElseGet(() -> new BookProgress(userId, book));

        int capped = Math.max(0, Math.min(sentenceIndex,
                book.getSentenceCount() == null ? sentenceIndex : book.getSentenceCount()));
        if (capped > progress.getLastSentenceIndex()) {
            progress.setLastSentenceIndex(capped);
        }
        progress.setUpdatedAt(java.time.LocalDateTime.now());
        progressRepository.save(progress);
        return progress.getLastSentenceIndex();
    }
}
