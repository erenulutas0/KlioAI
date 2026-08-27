package com.ingilizce.calismaapp.config;

import com.ingilizce.calismaapp.entity.Book;
import com.ingilizce.calismaapp.repository.BookRepository;
import com.ingilizce.calismaapp.repository.BookSentenceRepository;
import com.ingilizce.calismaapp.service.BookImportService;
import com.ingilizce.calismaapp.service.BookLibrary;
import com.ingilizce.calismaapp.service.BookTranslationService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;

/**
 * Puts the reading shelf into the database at boot, when an operator asks for it.
 *
 * <p>The admin endpoints in {@code BookAdminController} are the long-term way to
 * do this. They are unreachable today: {@code User.role} starts at {@code USER}
 * and nothing in the codebase promotes anyone, so no account can satisfy the
 * {@code ROLE_ADMIN} check. Minting an admin account to run a one-off content
 * job would hand a real user permanent access to every other admin power, which
 * is a large and lasting change to make for a job that runs twice.
 *
 * <p>So this exists instead: a switch on the deployment rather than a role on a
 * person. Set the variables, deploy, read the log, unset them.
 *
 * <p>Both steps are safe to leave on by accident, which is deliberate — a flag
 * that is dangerous when forgotten will eventually be forgotten. Import is
 * idempotent by slug. Translation only ever looks at sentences that have no
 * translation yet, so the second boot after a finished book asks the model for
 * nothing and spends nothing.
 */
@Component
public class BookShelfBootstrap implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(BookShelfBootstrap.class);

    private final BookImportService importService;
    private final BookTranslationService translationService;
    private final BookRepository bookRepository;
    private final BookSentenceRepository sentenceRepository;

    @Value("${app.books.import-on-startup:false}")
    private boolean importOnStartup;

    /**
     * Sentences to translate at boot; 0 disables translation entirely.
     *
     * <p>A ceiling rather than a switch because this is the step that costs
     * money. The first run on a new shelf should be a small one: translate a
     * hundred sentences, read the measured cost below, then decide.
     */
    @Value("${app.books.translate-on-startup:0}")
    private int translateOnStartup;

    /** Which book to translate. Blank means the first one with work left. */
    @Value("${app.books.translate-slug:}")
    private String translateSlug;

    @Value("${app.books.translate-into:Turkish}")
    private String translateInto;

    /**
     * Which model translates. Blank uses the configured default.
     *
     * <p>Worth a switch of its own: the shelf is translated once and read for
     * years, so a better model is a one-off cost against a permanent gain, and
     * the only way to choose honestly is to run the same sentences through two
     * models and read both.
     */
    @Value("${app.books.translate-model:}")
    private String translateModel;

    public BookShelfBootstrap(BookImportService importService,
            BookTranslationService translationService,
            BookRepository bookRepository,
            BookSentenceRepository sentenceRepository) {
        this.importService = importService;
        this.translationService = translationService;
        this.bookRepository = bookRepository;
        this.sentenceRepository = sentenceRepository;
    }

    @Override
    public void run(ApplicationArguments args) {
        // Nothing here is worth failing a deployment over. A book that did not
        // import is a missing feature; a backend that will not start is an
        // outage for everything else the app does.
        try {
            if (importOnStartup) {
                runImport();
            }
            if (translateOnStartup > 0) {
                runTranslation();
            }
        } catch (Exception e) {
            log.error("Book shelf bootstrap failed; the app is otherwise fine: {}", e.toString(), e);
        }
    }

    private void runImport() {
        int books = 0;
        int sentences = 0;
        for (BookLibrary.ShelvedBook book : BookLibrary.BOOKS) {
            try {
                BookImportService.ImportResult result = importService.importBook(
                        book.slug(), book.title(), book.author(), "English",
                        book.level(), book.source(), BookLibrary.readText(book));
                books++;
                sentences += result.sentences();
                // The verified counts are on the operator's own line, not
                // buried in the service's: an edition that stopped matching its
                // corrections looks exactly like one that has none.
                log.info("BOOKS import {} level={} chapters={} sentences={} replaced={} verified={}/{}",
                        result.slug(), book.level(), result.chapters(), result.sentences(),
                        result.replaced(), result.verifiedApplied(), result.verifiedOnFile());
            } catch (Exception e) {
                // One unreadable book must not cost the operator the other five.
                log.warn("BOOKS import failed for {}: {}", book.slug(), e.toString());
            }
        }
        log.info("BOOKS import complete: {} books, {} sentences", books, sentences);
    }

    private void runTranslation() {
        Book book = pickBook();
        if (book == null) {
            log.warn("BOOKS translate: nothing to translate (slug={}). Import first.", translateSlug);
            return;
        }

        log.warn("BOOKS translate starting for {} (max {} sentences into {}, model {}). "
                + "This spends money on every boot until APP_BOOKS_TRANSLATE_ON_STARTUP is unset.",
                book.getSlug(), translateOnStartup, translateInto,
                translateModel.isBlank() ? "default" : translateModel);

        BookTranslationService.TranslationResult result =
                translationService.translateBook(book.getId(), translateInto, translateOnStartup,
                        translateModel);

        long perSentence = result.translated() == 0
                ? 0
                : Math.round((double) result.totalTokens() / result.translated());

        // One line, tagged, carrying the number the whole decision turns on.
        // An operator reading `docker logs | grep BOOKS` should not have to do
        // arithmetic to find out what the rest of the shelf will cost.
        log.info("BOOKS translate {} model={} translated={} remaining={} failedBatches={} "
                + "promptTokens={} completionTokens={} totalTokens={} tokensPerSentence={}",
                book.getSlug(), translateModel.isBlank() ? "default" : translateModel,
                result.translated(), result.remaining(), result.failedBatches(),
                result.promptTokens(), result.completionTokens(), result.totalTokens(), perSentence);
    }

    /**
     * The named book, or the first shelved one that still has untranslated
     * sentences — so an operator can leave the slug blank and work down the
     * shelf one deploy at a time.
     */
    private Book pickBook() {
        if (translateSlug != null && !translateSlug.isBlank()) {
            return bookRepository.findBySlug(translateSlug.strip()).orElse(null);
        }
        for (BookLibrary.ShelvedBook shelved : BookLibrary.BOOKS) {
            Book book = bookRepository.findBySlug(shelved.slug()).orElse(null);
            if (book != null && sentenceRepository.countUntranslated(book.getId()) > 0) {
                return book;
            }
        }
        return null;
    }
}
