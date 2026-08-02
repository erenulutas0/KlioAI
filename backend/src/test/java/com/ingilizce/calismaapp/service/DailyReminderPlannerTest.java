package com.ingilizce.calismaapp.service;

import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.time.ZoneId;
import java.time.ZonedDateTime;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * The reminder used to be a single string sent to everyone at 17:00 UTC.
 *
 * <p>These tests are mostly about what it now declines to send. A daily notification that is
 * sometimes wrong is worse than none, because the learner cannot tell which one they are
 * holding, and after the second useless one they turn the category off — at which point the
 * app has no way to reach them at all.
 */
class DailyReminderPlannerTest {

    private static final ZoneId ISTANBUL = ZoneId.of("Europe/Istanbul");
    private static final int EVENING = 20;

    /** A Thursday, 20:00 in Istanbul. */
    private static Instant istanbulAt(int hour) {
        return ZonedDateTime.of(2026, 8, 6, hour, 0, 0, 0, ISTANBUL).toInstant();
    }

    @Test
    void nobodyIsRemindedOutsideTheirOwnEvening() {
        // The same instant is the right hour for one learner and the middle of the night for
        // another. That is the whole reason the job runs hourly.
        Instant nineInIstanbul = istanbulAt(9);

        var early = DailyReminderPlanner.plan(
                "Europe/Istanbul", "tr", EVENING, nineInIstanbul, 5, nineInIstanbul.minusSeconds(200_000));

        assertFalse(early.send());
        assertEquals("not-local-hour", early.skipReason());
    }

    @Test
    void aLearnerInAnotherTimezoneGetsTheirOwnEvening() {
        // 20:00 in Berlin is 21:00 in Istanbul. One instant, two verdicts.
        Instant nineIstanbulEvening = istanbulAt(21);

        var berlin = DailyReminderPlanner.plan(
                "Europe/Berlin", "en", EVENING, nineIstanbulEvening, 3, nineIstanbulEvening.minusSeconds(200_000));
        var istanbul = DailyReminderPlanner.plan(
                "Europe/Istanbul", "tr", EVENING, nineIstanbulEvening, 3, nineIstanbulEvening.minusSeconds(200_000));

        assertTrue(berlin.send(), "20:00 in Berlin");
        assertFalse(istanbul.send(), "21:00 in Istanbul");
    }

    @Test
    void somebodyWhoAlreadyPractisedTodayIsLeftAlone() {
        // The worst notification the old version sent: "time to practise", to a person who
        // practised this afternoon. Nothing erodes a notification channel faster.
        Instant evening = istanbulAt(20);
        Instant thisAfternoon = istanbulAt(15);

        var decision = DailyReminderPlanner.plan(
                "Europe/Istanbul", "tr", EVENING, evening, 7, thisAfternoon);

        assertFalse(decision.send());
        assertEquals("already-practised-today", decision.skipReason());
    }

    @Test
    void nothingDueMeansNothingIsSaid() {
        // The old copy claimed a session was ready every day whether or not one was.
        Instant evening = istanbulAt(20);

        var decision = DailyReminderPlanner.plan(
                "Europe/Istanbul", "tr", EVENING, evening, 0, evening.minusSeconds(200_000));

        assertFalse(decision.send());
        assertEquals("nothing-due", decision.skipReason());
    }

    @Test
    void theMessageNamesHowManyWordsAreWaiting() {
        Instant evening = istanbulAt(20);

        var decision = DailyReminderPlanner.plan(
                "Europe/Istanbul", "tr", EVENING, evening, 12, evening.minusSeconds(200_000));

        assertTrue(decision.send());
        assertTrue(decision.body().contains("12"),
                "a count is the difference between a reason and a nag: " + decision.body());
    }

    @Test
    void turkishLearnersAreNotRemindedInEnglish() {
        Instant evening = istanbulAt(20);

        var turkish = DailyReminderPlanner.plan(
                "Europe/Istanbul", "tr-TR", EVENING, evening, 4, evening.minusSeconds(200_000));
        var english = DailyReminderPlanner.plan(
                "Europe/Istanbul", "en-US", EVENING, evening, 4, evening.minusSeconds(200_000));

        assertEquals("Tekrar zamanı", turkish.title());
        assertEquals("Review time", english.title());
        assertTrue(turkish.body().contains("kelime"));
        assertTrue(english.body().contains("ready for review"));
    }

    @Test
    void anUnknownLocaleIsTreatedAsTurkish() {
        // The app is built for Turkish speakers learning English. The old default sent
        // English to every device including all of theirs.
        Instant evening = istanbulAt(20);

        var decision = DailyReminderPlanner.plan(
                "Europe/Istanbul", null, EVENING, evening, 2, evening.minusSeconds(200_000));

        assertTrue(decision.body().contains("kelime"));
    }

    @Test
    void englishSingularAndPluralBothRead() {
        Instant evening = istanbulAt(20);
        Instant yesterday = evening.minusSeconds(200_000);

        var one = DailyReminderPlanner.plan("Europe/Istanbul", "en", EVENING, evening, 1, yesterday);
        var many = DailyReminderPlanner.plan("Europe/Istanbul", "en", EVENING, evening, 9, yesterday);

        assertTrue(one.body().contains("1 word is"), one.body());
        assertTrue(many.body().contains("9 words are"), many.body());
    }

    @Test
    void aDormantLearnerIsNotChasedEveryEvening() {
        // Thursday. Someone who has not studied in a month has decided something, and a
        // thirtieth consecutive reminder is not going to change it.
        Instant thursdayEvening = istanbulAt(20);
        Instant longAgo = thursdayEvening.minusSeconds(60L * 60 * 24 * 30);

        var decision = DailyReminderPlanner.plan(
                "Europe/Istanbul", "tr", EVENING, thursdayEvening, 40, longAgo);

        assertFalse(decision.send());
        assertEquals("dormant-backoff", decision.skipReason());
    }

    @Test
    void aDormantLearnerStillGetsOneAttemptAWeek() {
        // Monday, 20:00 Istanbul. Going silent forever is the other way to lose them.
        Instant mondayEvening = ZonedDateTime.of(2026, 8, 3, 20, 0, 0, 0, ISTANBUL).toInstant();
        Instant longAgo = mondayEvening.minusSeconds(60L * 60 * 24 * 30);

        var decision = DailyReminderPlanner.plan(
                "Europe/Istanbul", "tr", EVENING, mondayEvening, 40, longAgo);

        assertTrue(decision.send());
        assertTrue(decision.body().contains("Ara vermişsin"),
                "a returning learner should not be greeted as if they never left: " + decision.body());
    }

    @Test
    void aLearnerWhoHasNeverStudiedCountsAsDormant() {
        Instant thursdayEvening = istanbulAt(20);

        var decision = DailyReminderPlanner.plan(
                "Europe/Istanbul", "tr", EVENING, thursdayEvening, 5, null);

        assertFalse(decision.send());
        assertEquals("dormant-backoff", decision.skipReason());
    }

    @Test
    void aBrokenTimezoneFallsBackToIstanbulRatherThanThrowing() {
        // The zone string comes from the client and is null on every row written before the
        // column existed. An exception here would stop the whole run for everyone.
        Instant evening = istanbulAt(20);
        Instant yesterday = evening.minusSeconds(200_000);

        assertEquals(ISTANBUL, DailyReminderPlanner.resolveZone(null));
        assertEquals(ISTANBUL, DailyReminderPlanner.resolveZone("   "));
        assertEquals(ISTANBUL, DailyReminderPlanner.resolveZone("Mars/Olympus_Mons"));

        var decision = DailyReminderPlanner.plan(null, "tr", EVENING, evening, 3, yesterday);
        assertTrue(decision.send(), "a missing zone must not silently mute a learner");
    }

    @Test
    void utcWouldHaveBeenTheWrongFallback() {
        // Guarding the choice, not just the behaviour: falling back to UTC would put the
        // "evening" reminder at 23:00 for a learner in Turkey.
        Instant elevenPmIstanbul = istanbulAt(23);

        var decision = DailyReminderPlanner.plan(
                null, "tr", EVENING, elevenPmIstanbul, 3, elevenPmIstanbul.minusSeconds(200_000));

        assertFalse(decision.send(), "23:00 local is not the evening reminder hour");
    }

    @Test
    void anAbbreviationIsNotAnIdentifier() {
        // The client was sending DateTime.now().timeZoneName, which is an abbreviation:
        // "GMT+03:00" on Android, "CEST" in Berlin in August. Offsets happen to parse;
        // names do not, and the fallback then quietly relocates that learner to Istanbul.
        assertTrue(DailyReminderPlanner.isResolvableZone("Europe/Berlin"));
        assertTrue(DailyReminderPlanner.isResolvableZone("GMT+03:00"));

        assertFalse(DailyReminderPlanner.isResolvableZone("CEST"));
        assertFalse(DailyReminderPlanner.isResolvableZone("TRT"));
        assertFalse(DailyReminderPlanner.isResolvableZone(null));
        assertFalse(DailyReminderPlanner.isResolvableZone("  "));
    }
}
