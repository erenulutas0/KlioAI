package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.entity.FeatureRating;
import com.ingilizce.calismaapp.entity.SupportTicket;
import com.ingilizce.calismaapp.repository.FeatureRatingRepository;
import com.ingilizce.calismaapp.repository.SupportTicketRepository;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * One message a day: what learners rated, what they wrote, and what they asked for help with.
 *
 * <p>The support tickets were written to a table and a log line, and nobody looked -- the one
 * ticket in it, a month later, was a test. A report nobody reads is decoration, so this puts
 * the day's answers where the person who has to act on them already looks.
 *
 * <p>In Turkish, because it is read by the developer, not by a learner. Plain text: the notes
 * are learners' own words, and a formatting mode would let a stray asterisk in one of them
 * break the whole message.
 */
@Service
public class FeedbackDigestService {

    /** Telegram's limit is 4096; the rest is left for the closing line. */
    static final int MAX_CHARS = 3900;

    /** Listed one by one: every low rating, and every rating with a note, up to this many. */
    static final int MAX_LISTED = 15;

    static final int NOTE_SHOWN = 220;

    private static final Locale TR = Locale.forLanguageTag("tr");
    private static final DateTimeFormatter DAY = DateTimeFormatter.ofPattern("d MMMM", TR);

    private final FeatureRatingRepository ratings;
    private final SupportTicketRepository tickets;

    public FeedbackDigestService(FeatureRatingRepository ratings, SupportTicketRepository tickets) {
        this.ratings = ratings;
        this.tickets = tickets;
    }

    /** The message, and whether there was anything in it. */
    public record Digest(String text, boolean empty) {
    }

    /**
     * @param start the window, on the database's clock (rows are stamped LocalDateTime.now())
     * @param day   the date the message is for, in the reader's zone
     */
    public Digest build(LocalDateTime start, LocalDateTime end, LocalDate day) {
        List<FeatureRating> rated = ratings.findByCreatedAtBetweenOrderByCreatedAtAsc(start, end);
        List<SupportTicket> asked = tickets
                .findByCreatedAtAfterOrderByCreatedAtDesc(start, PageRequest.of(0, 50))
                .stream()
                .filter(t -> t.getCreatedAt() == null || t.getCreatedAt().isBefore(end))
                .toList();

        String title = "KlioAI · " + DAY.format(day);
        if (rated.isEmpty() && asked.isEmpty()) {
            // Sent anyway, by default: a day of silence and a broken digest look the same from
            // the phone, and with a handful of learners most days are quiet.
            return new Digest(title + ": bugün yeni puan ya da ticket yok.", true);
        }

        StringBuilder out = new StringBuilder(title).append(" geri bildirimi\n");
        if (!rated.isEmpty()) {
            appendRatings(out, rated, start, end);
        }
        if (!asked.isEmpty()) {
            appendTickets(out, asked);
        }
        return new Digest(capped(out.toString()), false);
    }

    private void appendRatings(StringBuilder out, List<FeatureRating> rated,
            LocalDateTime start, LocalDateTime end) {
        out.append("\n⭐ ").append(rated.size()).append(" puan · ortalama ")
                .append(average(rated)).append('\n');

        Map<FeatureRating.Feature, List<FeatureRating>> byFeature = new LinkedHashMap<>();
        for (FeatureRating r : rated) {
            byFeature.computeIfAbsent(r.getFeature(), k -> new ArrayList<>()).add(r);
        }
        List<String> parts = new ArrayList<>();
        byFeature.forEach((feature, list) ->
                parts.add(label(feature) + " " + average(list) + " (" + list.size() + ")"));
        out.append(String.join(" · ", parts)).append('\n');

        Map<String, List<FeatureRating>> byScene = new LinkedHashMap<>();
        for (FeatureRating r : rated) {
            if (r.getSceneId() != null) {
                byScene.computeIfAbsent(r.getSceneId(), k -> new ArrayList<>()).add(r);
            }
        }
        if (!byScene.isEmpty()) {
            List<String> scenes = new ArrayList<>();
            byScene.forEach((scene, list) ->
                    scenes.add(scene + " " + average(list) + " (" + list.size() + ")"));
            out.append("Sahneler: ").append(String.join(" · ", scenes)).append('\n');
        }

        // The week, for a trend: one quiet day with a single 2 is not a problem, a week of 3s is.
        List<FeatureRating> week = ratings.findByCreatedAtBetweenOrderByCreatedAtAsc(end.minusDays(7), end);
        if (week.size() > rated.size()) {
            out.append("Son 7 gün: ").append(average(week)).append(" (").append(week.size())
                    .append(" puan)\n");
        }

        List<FeatureRating> listed = rated.stream()
                .filter(r -> r.getStars() <= 3 || r.getNote() != null)
                .sorted(Comparator.comparing(FeatureRating::getStars))
                .limit(MAX_LISTED)
                .toList();
        if (!listed.isEmpty()) {
            out.append("\nNotlar ve düşük puanlar:\n");
            for (FeatureRating r : listed) {
                out.append(stars(r.getStars())).append(' ').append(label(r.getFeature()));
                if (r.getSceneId() != null) {
                    out.append(" · ").append(r.getSceneId());
                }
                out.append(" · #").append(r.getUserId());
                if (r.getAppVersion() != null) {
                    out.append(" · ").append(r.getAppVersion());
                }
                out.append('\n');
                if (r.getNote() != null) {
                    out.append("  \"").append(shortened(r.getNote())).append("\"\n");
                }
            }
        }
    }

    private void appendTickets(StringBuilder out, List<SupportTicket> asked) {
        Map<String, Integer> byType = new LinkedHashMap<>();
        for (SupportTicket t : asked) {
            byType.merge(t.getType().name(), 1, Integer::sum);
        }
        List<String> counts = new ArrayList<>();
        byType.forEach((type, n) -> counts.add(type + " " + n));
        out.append("\n🎫 ").append(asked.size()).append(" ticket: ")
                .append(String.join(", ", counts)).append('\n');
        for (SupportTicket t : asked) {
            out.append("• #").append(t.getId()).append(' ').append(t.getType().name())
                    .append(" · #").append(t.getUserId()).append(" · \"")
                    .append(shortened(t.getTitle())).append("\": ")
                    .append(shortened(t.getMessage())).append('\n');
        }
    }

    static String average(List<FeatureRating> list) {
        double avg = list.stream().mapToInt(FeatureRating::getStars).average().orElse(0);
        return String.format(TR, "%.1f", avg);
    }

    static String stars(int n) {
        return "★".repeat(n) + "☆".repeat(5 - n);
    }

    private static String label(FeatureRating.Feature feature) {
        return switch (feature) {
            case TUTOR -> "Eğitmen";
            case READING -> "Okuma";
            case WRITING -> "Yazma";
            case SESSION -> "Günlük oturum";
            case PRACTICE -> "Pratik";
        };
    }

    private static String shortened(String text) {
        String flat = text.replaceAll("\\s+", " ").trim();
        return flat.length() > NOTE_SHOWN ? flat.substring(0, NOTE_SHOWN) + "…" : flat;
    }

    private static String capped(String text) {
        if (text.length() <= MAX_CHARS) {
            return text;
        }
        return text.substring(0, MAX_CHARS) + "\n… (devamı veritabanında)";
    }
}
