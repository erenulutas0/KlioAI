package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.entity.FeatureRating;
import com.ingilizce.calismaapp.entity.SupportTicket;
import com.ingilizce.calismaapp.repository.FeatureRatingRepository;
import com.ingilizce.calismaapp.repository.SupportTicketRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class FeedbackDigestServiceTest {

    private static final LocalDateTime END = LocalDateTime.of(2026, 9, 14, 18, 0);
    private static final LocalDateTime START = END.minusHours(24);
    private static final LocalDate DAY = LocalDate.of(2026, 9, 14);

    @Mock
    private FeatureRatingRepository ratings;

    @Mock
    private SupportTicketRepository tickets;

    private FeedbackDigestService service;

    @BeforeEach
    void setUp() {
        service = new FeedbackDigestService(ratings, tickets);
        lenient().when(tickets.findByCreatedAtAfterOrderByCreatedAtDesc(eq(START), any()))
                .thenReturn(List.of());
        lenient().when(ratings.findByCreatedAtBetweenOrderByCreatedAtAsc(eq(END.minusDays(7)), eq(END)))
                .thenReturn(List.of());
    }

    private static FeatureRating rating(FeatureRating.Feature feature, int stars, String note, String scene) {
        FeatureRating r = new FeatureRating();
        r.setUserId(12L);
        r.setFeature(feature);
        r.setStars(stars);
        r.setNote(note);
        r.setSceneId(scene);
        r.setAppVersion("1.4.1+484");
        r.setCreatedAt(END.minusHours(2));
        return r;
    }

    private static SupportTicket ticket(long id, SupportTicket.TicketType type, String title, String message) {
        SupportTicket t = new SupportTicket();
        ReflectionTestUtils.setField(t, "id", id);
        t.setUserId(5L);
        t.setType(type);
        t.setTitle(title);
        t.setMessage(message);
        ReflectionTestUtils.setField(t, "createdAt", END.minusHours(3));
        return t;
    }

    @Test
    void aQuietDayStillSaysSo() {
        // Silence and a broken digest look the same from the phone.
        when(ratings.findByCreatedAtBetweenOrderByCreatedAtAsc(START, END)).thenReturn(List.of());

        FeedbackDigestService.Digest digest = service.build(START, END, DAY);

        assertTrue(digest.empty());
        assertTrue(digest.text().contains("14 Eylül"), digest.text());
        assertTrue(digest.text().contains("yeni puan ya da ticket yok"), digest.text());
    }

    @Test
    void theDayIsSummedUpByFeatureAndByScene() {
        when(ratings.findByCreatedAtBetweenOrderByCreatedAtAsc(START, END)).thenReturn(List.of(
                rating(FeatureRating.Feature.TUTOR, 5, null, "restaurant_order"),
                rating(FeatureRating.Feature.TUTOR, 4, null, "restaurant_order"),
                rating(FeatureRating.Feature.READING, 3, null, null)));

        String text = service.build(START, END, DAY).text();

        assertTrue(text.contains("3 puan · ortalama 4,0"), text);
        assertTrue(text.contains("Eğitmen 4,5 (2)"), text);
        assertTrue(text.contains("Okuma 3,0 (1)"), text);
        assertTrue(text.contains("restaurant_order 4,5 (2)"), text);
    }

    @Test
    void lowRatingsAndNotesAreListedLowestFirst() {
        when(ratings.findByCreatedAtBetweenOrderByCreatedAtAsc(START, END)).thenReturn(List.of(
                rating(FeatureRating.Feature.TUTOR, 5, "Harika bir konuşma", "cafe_order"),
                rating(FeatureRating.Feature.TUTOR, 2, "Luca beni anlamadı", "restaurant_order"),
                rating(FeatureRating.Feature.WRITING, 5, null, null)));

        String text = service.build(START, END, DAY).text();

        int low = text.indexOf("Luca beni anlamadı");
        int high = text.indexOf("Harika bir konuşma");
        assertTrue(low > 0 && high > low, text);
        assertTrue(text.contains("★★☆☆☆ Eğitmen · restaurant_order · #12"), text);
        // A five with nothing to say is in the average, not in the list.
        assertFalse(text.contains("★★★★★ Yazma"), text);
    }

    @Test
    void ticketsComeWithTheirWords() {
        when(ratings.findByCreatedAtBetweenOrderByCreatedAtAsc(START, END)).thenReturn(List.of());
        when(tickets.findByCreatedAtAfterOrderByCreatedAtDesc(eq(START), any())).thenReturn(List.of(
                ticket(9, SupportTicket.TicketType.BUG, "Ses gelmiyor", "Luca konuşmuyor")));

        FeedbackDigestService.Digest digest = service.build(START, END, DAY);

        assertFalse(digest.empty());
        assertTrue(digest.text().contains("1 ticket: BUG 1"), digest.text());
        assertTrue(digest.text().contains("#9 BUG · #5 · \"Ses gelmiyor\": Luca konuşmuyor"), digest.text());
    }

    @Test
    void theWeekIsShownWhenThereIsMoreOfItThanToday() {
        List<FeatureRating> today = List.of(rating(FeatureRating.Feature.TUTOR, 2, null, null));
        List<FeatureRating> week = new ArrayList<>(today);
        for (int i = 0; i < 4; i++) {
            week.add(rating(FeatureRating.Feature.TUTOR, 5, null, null));
        }
        when(ratings.findByCreatedAtBetweenOrderByCreatedAtAsc(START, END)).thenReturn(today);
        when(ratings.findByCreatedAtBetweenOrderByCreatedAtAsc(END.minusDays(7), END)).thenReturn(week);

        String text = service.build(START, END, DAY).text();

        assertTrue(text.contains("Son 7 gün: 4,4 (5 puan)"), text);
    }

    @Test
    void aLongDayFitsInOneTelegramMessage() {
        List<FeatureRating> many = new ArrayList<>();
        for (int i = 0; i < 40; i++) {
            many.add(rating(FeatureRating.Feature.TUTOR, 1, "x".repeat(600), "restaurant_order"));
        }
        when(ratings.findByCreatedAtBetweenOrderByCreatedAtAsc(START, END)).thenReturn(many);

        String text = service.build(START, END, DAY).text();

        assertTrue(text.length() <= 4096, "length " + text.length());
    }
}
