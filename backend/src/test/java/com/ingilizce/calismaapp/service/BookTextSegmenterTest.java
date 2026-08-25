package com.ingilizce.calismaapp.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.ingilizce.calismaapp.service.BookTextSegmenter.BookChapter;
import java.util.List;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

/**
 * A sentence cut in the wrong place does not stay on the page. The reader lets
 * a learner tap a word inside a sentence and save it with that sentence as its
 * context, so a bad split becomes a permanent piece of wrong material in
 * someone's review schedule — reviewed for months.
 *
 * <p>Every case here is something real nineteenth-century prose does.
 */
class BookTextSegmenterTest {

    @Nested
    @DisplayName("sentence splitting")
    class Sentences {

        @Test
        @DisplayName("a title's period does not end a sentence")
        void abbreviations() {
            assertEquals(
                    List.of("Mr. Holmes rose from his chair."),
                    BookTextSegmenter.splitIntoSentences("Mr. Holmes rose from his chair."));

            assertEquals(
                    List.of("Dr. Watson and Mrs. Hudson waited."),
                    BookTextSegmenter.splitIntoSentences("Dr. Watson and Mrs. Hudson waited."));
        }

        @Test
        @DisplayName("initials are not sentence ends")
        void initials() {
            assertEquals(
                    List.of("It was written by J. M. Barrie."),
                    BookTextSegmenter.splitIntoSentences("It was written by J. M. Barrie."));
        }

        @Test
        @DisplayName("an ellipsis is a pause, not an ending")
        void ellipsis() {
            assertEquals(
                    List.of("I wondered... and then I knew."),
                    BookTextSegmenter.splitIntoSentences("I wondered... and then I knew."));
        }

        @Test
        @DisplayName("closing punctuation stays with the sentence it closes")
        void dialogue() {
            // English puts the full stop inside the quotation mark, so the
            // sentence ends after the quote and not before it. Getting this
            // wrong leaves a stray quotation mark opening the next sentence.
            assertEquals(
                    List.of("\"Go away.\"", "He left without a word."),
                    BookTextSegmenter.splitIntoSentences("\"Go away.\" He left without a word."));
        }

        @Test
        @DisplayName("a dialogue tag in lower case still starts a new sentence")
        void dialogueTag() {
            assertEquals(
                    List.of("\"I cannot.\"", "he muttered."),
                    BookTextSegmenter.splitIntoSentences("\"I cannot.\" he muttered."));
        }

        @Test
        @DisplayName("question and exclamation marks end sentences")
        void questionsAndExclamations() {
            assertEquals(
                    List.of("Who is there?", "Come in!", "The door opened."),
                    BookTextSegmenter.splitIntoSentences("Who is there? Come in! The door opened."));
        }

        @Test
        @DisplayName("a run of terminators is one ending")
        void terminatorRun() {
            assertEquals(
                    List.of("What?!", "I never said that."),
                    BookTextSegmenter.splitIntoSentences("What?! I never said that."));
        }

        @Test
        @DisplayName("a decimal point is not a full stop")
        void decimals() {
            assertEquals(
                    List.of("The rate was 3.5 per cent that year."),
                    BookTextSegmenter.splitIntoSentences("The rate was 3.5 per cent that year."));
        }

        @Test
        @DisplayName("wrapped lines are one sentence, blank lines are a break")
        void wrapping() {
            // Gutenberg wraps at about seventy columns, so nearly every
            // sentence in a real file spans lines. Treating a line as a unit
            // would shred the entire book.
            String wrapped = "It was the best of times, it was the worst of\n"
                    + "times, it was the age of wisdom.\n"
                    + "\n"
                    + "It was the age of foolishness.";

            assertEquals(
                    List.of(
                            "It was the best of times, it was the worst of times, it was the age of wisdom.",
                            "It was the age of foolishness."),
                    BookTextSegmenter.splitIntoSentences(wrapped));
        }

        @Test
        @DisplayName("a paragraph that ends without punctuation still ends")
        void unterminatedParagraph() {
            assertEquals(
                    List.of("A fragment with no full stop"),
                    BookTextSegmenter.splitIntoSentences("A fragment with no full stop"));
        }

        @Test
        @DisplayName("nothing in, nothing out")
        void empty() {
            assertTrue(BookTextSegmenter.splitIntoSentences(null).isEmpty());
            assertTrue(BookTextSegmenter.splitIntoSentences("   \n\n  ").isEmpty());
        }
    }

    @Nested
    @DisplayName("Gutenberg boilerplate")
    class Boilerplate {

        @Test
        @DisplayName("the wrapper is removed and the book is kept")
        void strips() {
            String file = "The Project Gutenberg eBook of Something\n"
                    + "This header carries its own licence terms.\n"
                    + "*** START OF THE PROJECT GUTENBERG EBOOK SOMETHING ***\n"
                    + "\n"
                    + "Call me Ishmael.\n"
                    + "\n"
                    + "*** END OF THE PROJECT GUTENBERG EBOOK SOMETHING ***\n"
                    + "This footer does too.\n";

            String stripped = BookTextSegmenter.stripGutenbergBoilerplate(file);

            assertEquals("Call me Ishmael.", stripped);
            assertFalse(stripped.contains("licence"));
        }

        @Test
        @DisplayName("a file from somewhere else is left alone")
        void passesThroughWithoutMarkers() {
            assertEquals("Just a book.",
                    BookTextSegmenter.stripGutenbergBoilerplate("Just a book.\n"));
        }
    }

    @Nested
    @DisplayName("chapters")
    class Chapters {

        @Test
        @DisplayName("headings split the book and keep their own text")
        void splitsOnHeadings() {
            String book = "CHAPTER I\n"
                    + "\n"
                    + "The first sentence. The second one.\n"
                    + "\n"
                    + "CHAPTER II\n"
                    + "\n"
                    + "A later sentence.\n";

            List<BookChapter> chapters = BookTextSegmenter.segment(book);

            assertEquals(2, chapters.size());
            assertEquals("CHAPTER I", chapters.get(0).title());
            assertEquals(2, chapters.get(0).sentences().size());
            assertEquals("The second one.", chapters.get(0).sentences().get(1).text());
            assertEquals("CHAPTER II", chapters.get(1).title());
            assertEquals("A later sentence.", chapters.get(1).sentences().get(0).text());
        }

        @Test
        @DisplayName("sentences are numbered from the start of their chapter")
        void indexesWithinChapter() {
            List<BookChapter> chapters = BookTextSegmenter.segment(
                    "CHAPTER I\n\nOne. Two. Three.\n\nCHAPTER II\n\nFour. Five.\n");

            assertEquals(List.of(0, 1, 2),
                    chapters.get(0).sentences().stream().map(s -> s.index()).toList());
            assertEquals(List.of(0, 1),
                    chapters.get(1).sentences().stream().map(s -> s.index()).toList());
        }

        @Test
        @DisplayName("a table of contents does not become empty chapters")
        void dropsHeadingsWithNoBody() {
            List<BookChapter> chapters = BookTextSegmenter.segment(
                    "CHAPTER I\nCHAPTER II\nCHAPTER III\n\nCHAPTER I\n\nThe real text begins.\n");

            assertEquals(1, chapters.size());
            assertEquals("The real text begins.", chapters.get(0).sentences().get(0).text());
        }

        @Test
        @DisplayName("text before the first heading is kept, not discarded")
        void keepsFrontMatter() {
            List<BookChapter> chapters = BookTextSegmenter.segment(
                    "A dedication to someone.\n\nCHAPTER I\n\nThe story starts.\n");

            assertEquals(2, chapters.size());
            assertEquals("A dedication to someone.", chapters.get(0).sentences().get(0).text());
        }

        @Test
        @DisplayName("a book with no headings is one chapter, not none")
        void survivesAnUnusualLayout() {
            List<BookChapter> chapters = BookTextSegmenter.segment(
                    "A short story with no chapters at all. It still has sentences.\n");

            assertEquals(1, chapters.size());
            assertEquals(2, chapters.get(0).sentences().size());
        }

        @Test
        @DisplayName("a sentence mentioning a chapter does not split the book")
        void doesNotSplitOnProse() {
            List<BookChapter> chapters = BookTextSegmenter.segment(
                    "He opened the book at chapter 4 and began to read aloud to her.\n");

            assertEquals(1, chapters.size());
        }
    }

    @Test
    @DisplayName("a passage of real prose comes out whole")
    void realProse() {
        // Opening of "A Scandal in Bohemia", wrapped the way Gutenberg wraps it.
        String passage = "CHAPTER I\n"
                + "\n"
                + "To Sherlock Holmes she is always _the_ woman. I have seldom heard\n"
                + "him mention her under any other name. In his eyes she eclipses\n"
                + "and predominates the whole of her sex. It was not that he felt\n"
                + "any emotion akin to love for Irene Adler.\n"
                + "\n"
                + "\"You have been in Afghanistan, I perceive.\" He said it quietly.\n";

        List<BookChapter> chapters = BookTextSegmenter.segment(passage);

        assertEquals(1, chapters.size());
        List<String> sentences = chapters.get(0).sentences().stream()
                .map(s -> s.text())
                .toList();

        assertEquals(6, sentences.size());
        // The underscores are Gutenberg's plain-text italics, and they do not
        // survive: they are typesetting, and a learner tapping "_the_" to see
        // what it means is looking up a word that does not exist. The emphasis
        // is lost with them, which is the cheaper of the two losses.
        assertEquals("To Sherlock Holmes she is always the woman.", sentences.get(0));
        assertEquals("I have seldom heard him mention her under any other name.", sentences.get(1));
        assertEquals("\"You have been in Afghanistan, I perceive.\"", sentences.get(4));
        assertEquals("He said it quietly.", sentences.get(5));
    }
}
