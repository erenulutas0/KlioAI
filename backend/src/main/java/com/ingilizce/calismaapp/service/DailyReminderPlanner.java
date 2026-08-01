package com.ingilizce.calismaapp.service;

import java.time.DayOfWeek;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.util.Locale;

/**
 * Decides whether a device should be reminded right now, and what the reminder should say.
 *
 * <p>What this replaces: one cron at 17:00 UTC that sent every enabled device the same
 * hardcoded English string — "A quick practice session is ready for today." — with no
 * knowledge of whether the person had already practised, whether anything was actually due,
 * what time it was where they live, or whether they had opened the app in a month. To a
 * learner in Istanbul that is a notification in the wrong language, at 20:00 sharp, claiming
 * something is waiting when frequently nothing is, on the same day they finished their
 * words. That notification does not get a session; it gets the app uninstalled, and for a
 * language app the reminder is most of the retention mechanism.
 *
 * <p>Every input needed to fix this was already being stored and none of it was being read:
 * {@code device_push_tokens} has carried {@code locale} and {@code timezone} per device from
 * the beginning, and {@code review_events} records every graded recall, which is exactly the
 * "has this person studied today" signal.
 *
 * <p>Pure and static so the rules can be tested against a fixed clock rather than inferred
 * from send logs. The rules run in order and the first one that matches wins.
 */
public final class DailyReminderPlanner {

    /** Beyond this, someone has stopped using the app and a daily nudge is just noise. */
    static final int DORMANT_AFTER_DAYS = 14;

    private DailyReminderPlanner() {}

    /** Why a device was passed over, or the message it should receive. */
    public record Decision(boolean send, String skipReason, String title, String body) {

        static Decision skip(String reason) {
            return new Decision(false, reason, null, null);
        }

        static Decision send(String title, String body) {
            return new Decision(true, null, title, body);
        }
    }

    /**
     * @param timezone        the device's IANA zone, as reported at registration; may be junk
     * @param locale          the device's language tag; may be null
     * @param targetLocalHour the hour, in the learner's own zone, a reminder belongs at
     * @param now             current instant
     * @param dueCount        words whose next review date has arrived
     * @param lastReviewAt    when this learner last graded anything, or null if never
     */
    public static Decision plan(
            String timezone,
            String locale,
            int targetLocalHour,
            Instant now,
            long dueCount,
            Instant lastReviewAt) {

        ZoneId zone = resolveZone(timezone);
        ZonedDateTime localNow = now.atZone(zone);

        // 1. The wrong time of day where they actually are. The scheduler runs hourly and
        // lets each device through on its own hour, which is the only way one cron can
        // serve more than one timezone.
        if (localNow.getHour() != targetLocalHour) {
            return Decision.skip("not-local-hour");
        }

        // 2. Already practised today. This is the single worst notification the old version
        // sent: a reminder to study, to somebody who has just studied. It teaches people
        // that the notification carries no information, and after that none of them work.
        LocalDate today = localNow.toLocalDate();
        if (lastReviewAt != null && lastReviewAt.atZone(zone).toLocalDate().isEqual(today)) {
            return Decision.skip("already-practised-today");
        }

        // 3. Nothing is actually waiting. The old copy claimed a session was ready every
        // single day whether or not one was. A reminder that is sometimes untrue is worth
        // less than no reminder, because the learner cannot tell which kind they are
        // holding — so when there is nothing to say, say nothing.
        if (dueCount <= 0) {
            return Decision.skip("nothing-due");
        }

        // 4. Dormant. Someone who has not opened the app in two weeks has decided something,
        // and sending them a 365th consecutive notification will not change it. Back off to
        // one attempt a week rather than going silent forever — a returning learner with
        // real words waiting is worth one message.
        boolean dormant = lastReviewAt == null
                || lastReviewAt.atZone(zone).toLocalDate().isBefore(today.minusDays(DORMANT_AFTER_DAYS));
        if (dormant && localNow.getDayOfWeek() != DayOfWeek.MONDAY) {
            return Decision.skip("dormant-backoff");
        }

        boolean turkish = isTurkish(locale);
        return Decision.send(title(turkish), body(turkish, dueCount, dormant));
    }

    /**
     * A device's reported zone is not trustworthy input — it arrives from the client and has
     * been null on every row that predates the column. Istanbul is the fallback because the
     * app is built for Turkish speakers learning English; guessing UTC would put the evening
     * reminder at 23:00 for most of them.
     */
    static ZoneId resolveZone(String timezone) {
        if (timezone == null || timezone.isBlank()) {
            return ZoneId.of("Europe/Istanbul");
        }
        try {
            return ZoneId.of(timezone.trim());
        } catch (Exception ignored) {
            return ZoneId.of("Europe/Istanbul");
        }
    }

    static boolean isTurkish(String locale) {
        // Default to Turkish rather than English: the audience is Turkish speakers, so an
        // unknown locale is far more likely to be one of them than not, and the old default
        // sent English to all of them.
        if (locale == null || locale.isBlank()) {
            return true;
        }
        return locale.trim().toLowerCase(Locale.ROOT).startsWith("tr");
    }

    private static String title(boolean turkish) {
        return turkish ? "Tekrar zamanı" : "Review time";
    }

    private static String body(boolean turkish, long dueCount, boolean returning) {
        if (turkish) {
            // Turkish takes no plural agreement after a number, so one form covers every
            // count: "1 kelime" and "12 kelime" are both correct.
            return returning
                    ? "Ara vermişsin — " + dueCount + " kelime hâlâ seni bekliyor."
                    : dueCount + " kelime tekrar için hazır. Birkaç dakika yeter.";
        }
        String words = dueCount == 1 ? "word is" : "words are";
        return returning
                ? "You have been away — " + dueCount + " " + words + " still waiting."
                : dueCount + " " + words + " ready for review. A few minutes is enough.";
    }
}
