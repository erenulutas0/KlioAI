package com.ingilizce.calismaapp.service;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Translations a person has read and corrected, kept next to the books.
 *
 * <p>Machine translation of this shelf is good at the easy end and poor at the
 * hard one: roughly a fifth of Peter Rabbit's sentences came back with a real
 * error, four fifths of Conrad's. A wrong translation teaches worse than none,
 * because a learner has no way to see that it is wrong — so a book is only
 * shown with translations once someone has actually read them.
 *
 * <p>That verification has to survive an import. Corrections applied straight to
 * the database would be wiped by the next re-import, and this segmenter has
 * already changed twice; the work would be lost silently, which is the worst
 * way to lose it.
 *
 * <p>Entries are keyed by the sentence's own text rather than its position, for
 * the same reason. A re-segmentation moves every index but leaves the sentences
 * themselves alone, so a text key still finds its translation afterwards — and
 * a sentence that genuinely changed stops matching, which is correct: it is not
 * the sentence that was checked.
 */
public final class VerifiedTranslations {

    private static final Logger log = LoggerFactory.getLogger(VerifiedTranslations.class);

    private VerifiedTranslations() {
    }

    /**
     * Loads the corrections for a book, or an empty map when it has none.
     *
     * <p>A missing file is the normal case: five of the six books have not been
     * checked by anyone, and are shipped untranslated because of it.
     */
    public static Map<String, String> forSlug(String slug) {
        String resource = "/books/verified/" + slug + ".tsv";
        try (InputStream in = VerifiedTranslations.class.getResourceAsStream(resource)) {
            if (in == null) {
                return Map.of();
            }
            return parse(new InputStreamReader(in, StandardCharsets.UTF_8), slug);
        } catch (IOException e) {
            // A book without its corrections is a book with machine
            // translations, not a broken import.
            log.warn("Could not read verified translations for {}: {}", slug, e.toString());
            return Map.of();
        }
    }

    static Map<String, String> parse(java.io.Reader reader, String slug) throws IOException {
        Map<String, String> verified = new HashMap<>();
        try (BufferedReader lines = new BufferedReader(reader)) {
            String line;
            int number = 0;
            while ((line = lines.readLine()) != null) {
                number++;
                if (line.isBlank() || line.startsWith("#")) {
                    continue;
                }
                int tab = line.indexOf('\t');
                if (tab <= 0 || tab == line.length() - 1) {
                    // Named rather than skipped: a line that looks like a
                    // correction and is not one would otherwise leave the
                    // machine's version on screen with nobody the wiser.
                    log.warn("Verified translations for {}: line {} has no tab separator", slug, number);
                    continue;
                }
                String english = normalise(line.substring(0, tab));
                String turkish = line.substring(tab + 1).strip();
                if (english.isEmpty() || turkish.isEmpty()) {
                    log.warn("Verified translations for {}: line {} has an empty side", slug, number);
                    continue;
                }
                verified.put(english, turkish);
            }
        }
        return verified;
    }

    /**
     * The form a sentence is matched by.
     *
     * <p>Whitespace only. The file is hand-edited, so a line wrapped differently
     * from the segmenter's output should still match; anything more aggressive
     * would start matching sentences that are not the one that was checked.
     */
    public static String normalise(String sentence) {
        return sentence == null ? "" : sentence.strip().replaceAll("\\s+", " ");
    }
}
