package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.entity.Book;
import com.ingilizce.calismaapp.entity.BookSentence;
import com.ingilizce.calismaapp.repository.BookRepository;
import com.ingilizce.calismaapp.repository.BookSentenceRepository;
import com.ingilizce.calismaapp.service.BookTextSegmenter.BookChapter;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Puts a public-domain book on the shelf: segments the text and stores every
 * sentence as its own row.
 *
 * <p>Import is a one-off per book, run by an operator rather than by a learner,
 * so it favours being obviously correct over being fast. Translation is a
 * separate step: segmenting is free and deterministic, translating costs money
 * and can fail halfway, and tangling the two would mean a network error losing
 * a correctly-segmented book.
 */
@Service
public class BookImportService {

    private static final Logger log = LoggerFactory.getLogger(BookImportService.class);

    /**
     * Sentences shorter than this are page furniture — a stray "II", a printer's
     * mark, a footnote number — not something to put in front of a learner or
     * to pay to translate.
     */
    private static final int MIN_SENTENCE_LENGTH = 12;

    private final BookRepository bookRepository;
    private final BookSentenceRepository sentenceRepository;

    public BookImportService(BookRepository bookRepository,
            BookSentenceRepository sentenceRepository) {
        this.bookRepository = bookRepository;
        this.sentenceRepository = sentenceRepository;
    }

    /** What an import did, for the operator running it. */
    public record ImportResult(Long bookId, String slug, int chapters, int sentences, boolean replaced) {
    }

    /**
     * Imports or re-imports a book.
     *
     * <p>Keyed on the slug, so running it twice does not shelve two copies. A
     * re-import replaces the sentences wholesale — the text is the authority,
     * and a partial merge would leave a book that is half one edition and half
     * another.
     *
     * <p>Reading progress survives, because it points at a sentence index and
     * the same text segments to the same indexes. Re-importing a <em>different</em>
     * edition under the same slug would move every reader, which is exactly why
     * the slug identifies an edition and not a work.
     */
    @Transactional
    public ImportResult importBook(String slug, String title, String author, String language,
            String level, String source, String rawText) {

        if (slug == null || slug.isBlank()) {
            throw new IllegalArgumentException("slug is required");
        }
        if (rawText == null || rawText.isBlank()) {
            throw new IllegalArgumentException("book text is empty");
        }

        List<BookChapter> chapters = BookTextSegmenter.segment(rawText);
        if (chapters.isEmpty()) {
            throw new IllegalArgumentException("no readable sentences in " + slug);
        }

        // Everything that can refuse the book happens before anything is
        // written. Saving the Book row first and discovering only afterwards
        // that nothing readable survived left an empty volume on the shelf that
        // a learner could open — and re-running the import found it and called
        // itself a replacement.
        List<PendingSentence> pending = new ArrayList<>();
        for (BookChapter chapter : chapters) {
            for (BookTextSegmenter.BookSentence sentence : chapter.sentences()) {
                String text = sentence.text().strip();
                if (text.length() < MIN_SENTENCE_LENGTH) {
                    continue;
                }
                pending.add(new PendingSentence(chapter.index(), blankToNull(chapter.title()), text));
            }
        }
        if (pending.isEmpty()) {
            throw new IllegalArgumentException("every sentence in " + slug + " was too short to keep");
        }

        Book book = bookRepository.findBySlug(slug).orElse(null);
        boolean replaced = book != null;
        if (book == null) {
            book = new Book(slug, title, author, language, level, source);
        } else {
            book.setTitle(title);
            book.setAuthor(author);
            if (language != null && !language.isBlank()) {
                book.setLanguage(language);
            }
            book.setLevel(level);
            book.setSource(source);
            sentenceRepository.deleteByBookId(book.getId());
            sentenceRepository.flush();
        }
        book = bookRepository.save(book);

        // Corrections a person has read, applied here so that re-importing a
        // book does not throw away the checking. A sentence that already has a
        // verified translation is also one the translation run will skip, so
        // nobody pays a model to produce a worse answer than the one on file.
        Map<String, String> verified = VerifiedTranslations.forSlug(slug);
        int verifiedApplied = 0;

        List<BookSentence> rows = new ArrayList<>(pending.size());
        for (int position = 0; position < pending.size(); position++) {
            PendingSentence p = pending.get(position);
            BookSentence row = new BookSentence(book, position, p.chapterIndex(),
                    p.chapterTitle(), p.text());
            String checked = verified.get(VerifiedTranslations.normalise(p.text()));
            if (checked != null) {
                row.setTranslation(checked);
                verifiedApplied++;
            }
            rows.add(row);
        }

        sentenceRepository.saveAll(rows);
        book.setSentenceCount(rows.size());
        book = bookRepository.save(book);

        // The count is logged because a mismatch is the failure to fear: an
        // edition whose sentences no longer match the file leaves every
        // correction unapplied, and silently.
        log.info("Imported book slug={} chapters={} sentences={} replaced={} verified={}/{}",
                slug, chapters.size(), rows.size(), replaced, verifiedApplied, verified.size());

        return new ImportResult(book.getId(), slug, chapters.size(), rows.size(), replaced);
    }

    private static String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value;
    }

    /** A sentence that has passed every check but has not been given a position yet. */
    private record PendingSentence(int chapterIndex, String chapterTitle, String text) {
    }
}
