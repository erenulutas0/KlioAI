package com.ingilizce.calismaapp.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.ingilizce.calismaapp.entity.Book;
import com.ingilizce.calismaapp.entity.BookSentence;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

/**
 * Translation is the one part of the reading feature that costs money and can
 * fail halfway, so what matters is not the happy path but what survives a
 * model having an off day.
 *
 * <p>The failure to fear is silent misalignment: a translation attached to the
 * wrong sentence looks perfectly fine and teaches a learner something false.
 */
class BookTranslationServiceTest {

    private final BookTranslationService service =
            new BookTranslationService(null, null);

    private static List<BookSentence> batchOf(String... texts) {
        Book book = new Book("b", "T", "A", "English", "B1", "test");
        List<BookSentence> rows = new java.util.ArrayList<>();
        for (int i = 0; i < texts.length; i++) {
            rows.add(new BookSentence(book, i, 0, null, texts[i]));
        }
        return rows;
    }

    @Nested
    @DisplayName("choosing the model")
    class ModelChoice {

        /** Records what the provider was actually asked for. */
        private final java.util.List<String> modelsAsked = new java.util.ArrayList<>();

        private BookTranslationService serviceRecordingModel() {
            AiCompletionProvider provider = (messages, json, maxTokens, temperature, model) -> {
                modelsAsked.add(model);
                return new AiCompletionProvider.CompletionResult(
                        "{\"translations\":[{\"n\":1,\"t\":\"bir\"}]}", 10, 10, 20);
            };
            return new BookTranslationService(
                    org.mockito.Mockito.mock(
                            com.ingilizce.calismaapp.repository.BookSentenceRepository.class),
                    provider);
        }

        @Test
        @DisplayName("a chosen model reaches the provider")
        void modelIsPassedThrough() throws Exception {
            BookTranslationService svc = serviceRecordingModel();

            svc.translateBatch(batchOf("One."), "Turkish", "openai/gpt-oss-120b");

            // The whole point of the switch is comparing two models on the same
            // sentences. An override that never arrives would leave both runs
            // identical and the comparison would quietly measure nothing.
            assertEquals(List.of("openai/gpt-oss-120b"), modelsAsked);
        }

        @Test
        @DisplayName("blank means the configured default, not a model named \"\"")
        void blankMeansDefault() throws Exception {
            BookTranslationService svc = serviceRecordingModel();

            svc.translateBatch(batchOf("One."), "Turkish", "   ");

            assertNull(modelsAsked.get(0));
        }
    }

    @Nested
    @DisplayName("reading the model's answer")
    class Parsing {

        @Test
        @DisplayName("the shape we asked for")
        void expectedShape() throws Exception {
            Map<Integer, String> parsed = service.parseTranslations(
                    "{\"translations\":[{\"n\":1,\"t\":\"Bir\"},{\"n\":2,\"t\":\"İki\"}]}");

            assertEquals("Bir", parsed.get(1));
            assertEquals("İki", parsed.get(2));
        }

        @Test
        @DisplayName("a bare array, which models return when not concentrating")
        void bareArray() throws Exception {
            Map<Integer, String> parsed = service.parseTranslations(
                    "[{\"n\":1,\"t\":\"Bir\"},{\"n\":2,\"t\":\"İki\"}]");

            assertEquals("Bir", parsed.get(1));
        }

        @Test
        @DisplayName("the array under some other key")
        void arrayUnderAnotherName() throws Exception {
            Map<Integer, String> parsed = service.parseTranslations(
                    "{\"result\":[{\"n\":1,\"t\":\"Bir\"}]}");

            assertEquals("Bir", parsed.get(1));
        }

        @Test
        @DisplayName("numbers win over order, even when the model reorders them")
        void numbersAreAuthoritative() throws Exception {
            // A model that answers out of order is common and harmless. Reading
            // it positionally would attach every translation to the wrong line.
            Map<Integer, String> parsed = service.parseTranslations(
                    "{\"translations\":[{\"n\":2,\"t\":\"İki\"},{\"n\":1,\"t\":\"Bir\"}]}");

            assertEquals("Bir", parsed.get(1));
            assertEquals("İki", parsed.get(2));
        }

        @Test
        @DisplayName("position is used only when there are no numbers at all")
        void positionalFallback() throws Exception {
            Map<Integer, String> parsed = service.parseTranslations(
                    "{\"translations\":[\"Bir\",\"İki\"]}");

            assertEquals("Bir", parsed.get(1));
            assertEquals("İki", parsed.get(2));
        }

        @Test
        @DisplayName("a partly numbered answer never guesses at the rest")
        void neverMixesNumbersAndPositions() throws Exception {
            // The dangerous case. If some entries carry numbers and some do
            // not, the unnumbered ones are dropped rather than slotted in by
            // position, because a wrong translation is worse than a missing one
            // — the next run will pick up whatever was left behind.
            Map<Integer, String> parsed = service.parseTranslations(
                    "{\"translations\":[{\"n\":1,\"t\":\"Bir\"},{\"t\":\"belki iki\"}]}");

            assertEquals("Bir", parsed.get(1));
            assertEquals(1, parsed.size());
        }

        @Test
        @DisplayName("nonsense is refused, not half-read")
        void refusesNonsense() {
            assertThrows(Exception.class, () -> service.parseTranslations("{\"ok\":true}"));
            assertThrows(Exception.class, () -> service.parseTranslations("not json"));
        }
    }

    @Nested
    @DisplayName("the prompt")
    class Prompt {

        @Test
        @DisplayName("carries every sentence, numbered from one")
        void numbersEverySentence() {
            String prompt = BookTranslationService.buildPrompt(
                    batchOf("First one here.", "Second one here."), "Turkish");

            assertTrue(prompt.contains("1. First one here."));
            assertTrue(prompt.contains("2. Second one here."));
        }

        @Test
        @DisplayName("names the language and forbids merging or summarising")
        void statesTheRules() {
            String prompt = BookTranslationService.buildPrompt(batchOf("A sentence."), "Turkish");

            assertTrue(prompt.contains("Turkish"));
            // The learner reads both lines together; a retelling breaks that.
            assertTrue(prompt.contains("Do not merge, split, summarise or omit"));
        }

        @Test
        @DisplayName("defaults to Turkish rather than to nothing")
        void defaultsTheLanguage() {
            assertTrue(BookTranslationService.buildPrompt(batchOf("A sentence."), null)
                    .contains("Turkish"));
            assertTrue(BookTranslationService.buildPrompt(batchOf("A sentence."), "  ")
                    .contains("Turkish"));
        }
    }

    @Test
    @DisplayName("a batch is small enough that the model keeps the numbering straight")
    void batchSizeIsModest() {
        // Long lists are where models start losing the correspondence between
        // number and sentence, and where one refusal costs the most work.
        assertTrue(BookTranslationService.BATCH_SIZE <= 25);
        assertTrue(BookTranslationService.BATCH_SIZE >= 5);
    }

    @Test
    @DisplayName("a sentence the model skipped stays untranslated")
    void skippedSentencesAreLeftForNextTime() throws Exception {
        // Writing a blank would look translated and never be retried; leaving
        // null means the next run finds it.
        Map<Integer, String> parsed = service.parseTranslations(
                "{\"translations\":[{\"n\":1,\"t\":\"Bir\"},{\"n\":2,\"t\":\"\"}]}");

        assertEquals("Bir", parsed.get(1));
        assertTrue(parsed.get(2) == null || parsed.get(2).isBlank());
    }

    @Test
    @DisplayName("an untranslated sentence is null, never an empty string")
    void untranslatedIsNull() {
        BookSentence sentence = batchOf("Something.").get(0);
        assertNull(sentence.getTranslation());
    }
}
