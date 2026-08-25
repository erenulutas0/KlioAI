package com.ingilizce.calismaapp.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ingilizce.calismaapp.entity.BookSentence;
import com.ingilizce.calismaapp.repository.BookSentenceRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Translates an imported book, once, into the learner's own language.
 *
 * <p>The whole economic case for the reading feature rests here: a novel is a
 * few thousand sentences, and translating each one on demand for every reader
 * would be unaffordable. Translated once at import and stored, a chapter costs
 * nothing to read no matter how many people read it.
 *
 * <p>Written to be resumable rather than atomic. It only ever looks at
 * sentences that have no translation yet, so a run that dies halfway — a
 * timeout, a rate limit, a restart — is fixed by running it again. Each batch
 * commits on its own for the same reason: a failure in batch forty must not
 * throw away the thirty-nine that succeeded.
 */
@Service
public class BookTranslationService {

    private static final Logger log = LoggerFactory.getLogger(BookTranslationService.class);

    /**
     * Sentences per request.
     *
     * <p>Large enough that the per-request overhead is not the cost, small
     * enough that one refusal or truncation loses very little work — and small
     * enough that the model keeps the numbering straight, which it stops doing
     * over long lists.
     */
    static final int BATCH_SIZE = 20;

    private final BookSentenceRepository sentenceRepository;
    private final AiCompletionProvider completionProvider;
    private final ObjectMapper objectMapper = new ObjectMapper();

    public BookTranslationService(BookSentenceRepository sentenceRepository,
            AiCompletionProvider completionProvider) {
        this.sentenceRepository = sentenceRepository;
        this.completionProvider = completionProvider;
    }

    /**
     * What a translation run achieved, for the operator who started it.
     *
     * <p>Token counts are reported because this is the one part of the reading
     * feature that costs money, and a shelf is only affordable if the number is
     * measured rather than assumed. Multiply by the remaining sentence count and
     * the whole library's bill is known before it is spent.
     */
    public record TranslationResult(int translated, int remaining, int failedBatches,
            long promptTokens, long completionTokens) {

        public long totalTokens() {
            return promptTokens + completionTokens;
        }
    }

    /** One batch's outcome: how many landed, and what it cost to ask. */
    private record BatchOutcome(int applied, int promptTokens, int completionTokens) {
    }

    /**
     * Translates whatever is still untranslated in a book.
     *
     * @param maxSentences a ceiling for one run, so an operator can try a
     *                     chapter's worth before committing to a novel
     */
    public TranslationResult translateBook(Long bookId, String targetLanguage, int maxSentences) {
        List<BookSentence> pending = sentenceRepository.findUntranslated(bookId);
        if (pending.isEmpty()) {
            return new TranslationResult(0, 0, 0, 0, 0);
        }
        if (maxSentences > 0 && pending.size() > maxSentences) {
            pending = pending.subList(0, maxSentences);
        }

        int translated = 0;
        int failedBatches = 0;
        long promptTokens = 0;
        long completionTokens = 0;

        for (int start = 0; start < pending.size(); start += BATCH_SIZE) {
            List<BookSentence> batch = pending.subList(start,
                    Math.min(start + BATCH_SIZE, pending.size()));
            try {
                BatchOutcome outcome = translateBatch(batch, targetLanguage);
                translated += outcome.applied();
                promptTokens += outcome.promptTokens();
                completionTokens += outcome.completionTokens();
            } catch (Exception e) {
                // Keep going. One bad batch is a gap to fill on the next run,
                // not a reason to abandon the other ninety-five per cent.
                failedBatches++;
                log.warn("Book {} translation batch at {} failed: {}", bookId, start, e.toString());
            }
        }

        int remaining = sentenceRepository.findUntranslated(bookId).size();
        log.info("Book {} translated={} remaining={} failedBatches={} promptTokens={} completionTokens={}",
                bookId, translated, remaining, failedBatches, promptTokens, completionTokens);
        return new TranslationResult(translated, remaining, failedBatches, promptTokens, completionTokens);
    }

    /**
     * One batch, in its own transaction so it survives a later failure.
     *
     * @return how many sentences came back with a usable translation
     */
    @Transactional
    protected BatchOutcome translateBatch(List<BookSentence> batch, String targetLanguage) throws Exception {
        String prompt = buildPrompt(batch, targetLanguage);

        List<Map<String, String>> messages = List.of(
                Map.of("role", "system", "content",
                        "You are a literary translator. You return only JSON."),
                Map.of("role", "user", "content", prompt));

        AiCompletionProvider.CompletionResult completion =
                completionProvider.chatCompletionWithUsage(messages, true, null, 0.2, null);

        String content = completion == null ? null : completion.content();
        if (content == null || content.isBlank()) {
            throw new IllegalStateException("empty completion");
        }

        Map<Integer, String> byIndex = parseTranslations(content);
        int applied = 0;
        for (int i = 0; i < batch.size(); i++) {
            String translation = byIndex.get(i + 1);
            if (translation == null || translation.isBlank()) {
                // A sentence the model skipped stays untranslated, so the next
                // run picks it up. Writing a blank would look translated and be
                // invisible forever.
                continue;
            }
            batch.get(i).setTranslation(translation.strip());
            applied++;
        }
        sentenceRepository.saveAll(batch);
        return new BatchOutcome(applied, completion.promptTokens(), completion.completionTokens());
    }

    static String buildPrompt(List<BookSentence> batch, String targetLanguage) {
        String language = targetLanguage == null || targetLanguage.isBlank() ? "Turkish" : targetLanguage;

        StringBuilder prompt = new StringBuilder();
        prompt.append("Translate each numbered sentence from a novel into ").append(language)
                .append(".\n\n");
        // The learner reads the original and the translation side by side, so a
        // loose retelling is worse than useless: it stops the two lines from
        // teaching each other.
        prompt.append("Rules:\n");
        prompt.append("- Translate sentence by sentence. Do not merge, split, summarise or omit.\n");
        prompt.append("- Keep the register of the original. Nineteenth-century prose should not ")
                .append("come out as modern chat.\n");
        prompt.append("- A learner reads the two lines together, so keep the ")
                .append("correspondence close enough to follow, while still sounding natural in ")
                .append(language).append(".\n");
        prompt.append("- Keep names and place names as they are.\n");
        prompt.append("- Return every number you were given, even if a sentence is a fragment.\n\n");
        prompt.append("Return JSON exactly like {\"translations\":[{\"n\":1,\"t\":\"...\"}]} ")
                .append("and nothing else.\n\n");

        for (int i = 0; i < batch.size(); i++) {
            prompt.append(i + 1).append(". ").append(batch.get(i).getText()).append('\n');
        }
        return prompt.toString();
    }

    /**
     * Reads the model's answer into number -> translation.
     *
     * <p>Tolerant of the shapes a model reaches for when it is not concentrating
     * — a bare array, or the object under another key — because the alternative
     * is discarding a batch of perfectly good translations over its packaging.
     */
    Map<Integer, String> parseTranslations(String content) throws Exception {
        JsonNode root = objectMapper.readTree(content);
        JsonNode list = root.isArray() ? root : root.path("translations");
        if (!list.isArray()) {
            for (JsonNode child : root) {
                if (child.isArray()) {
                    list = child;
                    break;
                }
            }
        }
        if (!list.isArray()) {
            throw new IllegalStateException("no translation array in response");
        }

        Map<Integer, String> byIndex = new LinkedHashMap<>();
        List<String> positional = new ArrayList<>();
        for (JsonNode item : list) {
            String text = item.path("t").asText(item.path("translation").asText(""));
            if (item.isTextual()) {
                text = item.asText();
            }
            JsonNode number = item.path("n");
            if (number.isInt()) {
                byIndex.put(number.asInt(), text);
            } else {
                positional.add(text);
            }
        }
        // Only fall back to position when the model gave no numbers at all.
        // Mixing the two would silently attach a translation to the wrong
        // sentence, which is the one failure this must never produce.
        if (byIndex.isEmpty()) {
            for (int i = 0; i < positional.size(); i++) {
                byIndex.put(i + 1, positional.get(i));
            }
        }
        return byIndex;
    }
}
