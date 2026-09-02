package com.ingilizce.calismaapp.service;

import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * The rule that turns a legacy {@code turkish_meaning} string into meanings.
 *
 * <p>Two things depend on it agreeing with itself: the V028 backfill split every existing
 * row with this rule, and every word the shipped client creates from now on is split with
 * it on the server. If the rule drifts, a word saved yesterday and the same word saved today
 * end up with different meanings, and the learner sees the difference. These cases are the
 * contract; change them only together with the migration.
 */
class MeaningSplitRuleTest {

    @Test
    void commaSeparatesTwoMeanings() {
        assertEquals(List.of("gecikme", "ertelemek"), WordService.splitMeaningString("gecikme, ertelemek"));
    }

    @Test
    void dailyWordsMarkerIsStripped_AndDoesNotCountAsAMeaning() {
        // The star is provenance, not a translation: the shipped client reads it from the
        // legacy string, and it must never surface as a meaning of its own.
        assertEquals(List.of("tuval"), WordService.splitMeaningString("⭐ tuval"));
        assertEquals(List.of("tuval"), WordService.splitMeaningString("tuval ★"));
        assertEquals(List.of("tuval"), WordService.splitMeaningString("⭐tuval"));
        assertEquals(List.of("tuval", "kanvas"), WordService.splitMeaningString("⭐ tuval, kanvas"));
    }

    @Test
    void blankInputGivesNoMeanings() {
        assertEquals(List.of(), WordService.splitMeaningString(null));
        assertEquals(List.of(), WordService.splitMeaningString(""));
        assertEquals(List.of(), WordService.splitMeaningString("   "));
        assertEquals(List.of(), WordService.splitMeaningString("⭐"), "a bare marker is not a meaning");
        assertEquals(List.of(), WordService.splitMeaningString(" ⭐ , ★ "));
        assertEquals(List.of(), WordService.splitMeaningString(", , ;"), "separators alone are not meanings");
    }

    @Test
    void duplicatesCollapse_KeepingTheFirstSpelling() {
        assertEquals(List.of("gecikme"), WordService.splitMeaningString("gecikme, gecikme"));
        assertEquals(List.of("Banka"), WordService.splitMeaningString("Banka, banka, BANKA"),
                "case-insensitive: the first spelling wins");
        assertEquals(List.of("gecikme", "ertelemek"), WordService.splitMeaningString("gecikme, ertelemek, gecikme"));
    }

    @Test
    void slashWithSpacesSeparates_ButASlashInsideAWordDoesNot() {
        assertEquals(List.of("gecikme", "ertelemek"), WordService.splitMeaningString("gecikme / ertelemek"));
        assertEquals(List.of("gecikme", "ertelemek", "geciktirmek"),
                WordService.splitMeaningString("gecikme / ertelemek, geciktirmek"));
        // "km/h"-style tokens stay whole; the backfill SQL splits only on a spaced slash.
        assertEquals(List.of("km/h"), WordService.splitMeaningString("km/h"));
    }

    @Test
    void semicolonSeparates() {
        assertEquals(List.of("gecikme", "ertelemek"), WordService.splitMeaningString("gecikme; ertelemek"));
    }

    @Test
    void partsAreTrimmed_EmptyPartsAreDropped_AndOrderIsKept() {
        assertEquals(List.of("gecikme", "ertelemek"), WordService.splitMeaningString("  gecikme ,ertelemek  "));
        assertEquals(List.of("gecikme", "ertelemek"), WordService.splitMeaningString("gecikme,,ertelemek,"));
        assertEquals(List.of("c", "a", "b"), WordService.splitMeaningString("c, a, b"));
    }

    @Test
    void resultIsNeverNullAndNeverContainsABlankOrStarredEntry() {
        for (String input : new String[] { null, "", " ", "⭐", "a, ⭐, b", "★a★", ",,", " / " }) {
            List<String> result = WordService.splitMeaningString(input);
            assertTrue(result != null, "null result for " + input);
            for (String part : result) {
                assertTrue(!part.isBlank(), "blank meaning for input " + input);
                assertTrue(!part.contains("⭐") && !part.contains("★"), "marker left in meaning for input " + input);
                assertEquals(part, part.trim(), "untrimmed meaning for input " + input);
            }
        }
    }

    @Test
    void aCommaInsideAClauseIsPunctuation_NotASecondMeaning() {
        // Seen on the word screen: "underneath" was saved as "Bir şeyin alt kısmında, üstünde
        // değil" -- one meaning with a clarifying clause, which Turkish writes with a comma as
        // a matter of course -- and the comma rule turned it into two rows, the second reading
        // "üstünde değil." on its own. That is not a meaning of anything. A comma stays a list
        // only while every piece is short; one long piece makes the whole run a single sense.
        assertEquals(List.of("Bir şeyin alt kısmında, üstünde değil"),
                WordService.splitMeaningString("Bir şeyin alt kısmında, üstünde değil"));
        assertEquals(List.of("(n) banka", "(n) kıyı"), WordService.splitMeaningString("(n) banka, (n) kıyı"),
                "two tagged senses are still two");
        assertEquals(List.of("hasta olmak", "rahatsız"), WordService.splitMeaningString("hasta olmak, rahatsız"),
                "two-word senses are still listed");
        // Semicolons split regardless of length: nobody writes a clause with one.
        assertEquals(List.of("Bir şeyin alt kısmında", "üstünde değil"),
                WordService.splitMeaningString("Bir şeyin alt kısmında; üstünde değil"));
    }
}
