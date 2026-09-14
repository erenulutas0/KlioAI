package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.entity.FeatureRating;
import com.ingilizce.calismaapp.repository.FeatureRatingRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Locale;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * A rating is written by a learner and sent by an app, so everything in it is bounded before
 * it is kept -- and none of that bounding may cost the rating itself.
 */
@ExtendWith(MockitoExtension.class)
class FeatureRatingServiceTest {

    @Mock
    private FeatureRatingRepository repository;

    private FeatureRatingService service;

    @BeforeEach
    void setUp() {
        service = new FeatureRatingService(repository);
        lenient().when(repository.save(any(FeatureRating.class))).thenAnswer(i -> i.getArgument(0));
    }

    private FeatureRating saved() {
        ArgumentCaptor<FeatureRating> captor = ArgumentCaptor.forClass(FeatureRating.class);
        verify(repository).save(captor.capture());
        return captor.getValue();
    }

    @Test
    void aRatingIsKeptWithWhatItWasAbout() {
        Map<String, Object> result = service.submit(7L, "tutor", 4, "  Luca was great  ",
                "restaurant_order", "tr", "1.4.1+484", "{\"turns\":6}");

        FeatureRating rating = saved();
        assertEquals(FeatureRating.Feature.TUTOR, rating.getFeature());
        assertEquals(4, rating.getStars());
        assertEquals("Luca was great", rating.getNote());
        assertEquals("restaurant_order", rating.getSceneId());
        assertEquals("1.4.1+484", rating.getAppVersion());
        assertEquals("{\"turns\":6}", rating.getContextJson());
        assertEquals("TUTOR", result.get("feature"));
        assertEquals(4, result.get("stars"));
    }

    @Test
    void onlyOneToFiveIsARating() {
        for (Integer stars : new Integer[] { null, 0, 6, -1 }) {
            assertThrows(IllegalArgumentException.class,
                    () -> service.submit(7L, "TUTOR", stars, null, null, null, null, null),
                    "accepted " + stars);
        }
        verify(repository, never()).save(any());
    }

    @Test
    void tenADayIsTheCeiling() {
        when(repository.countByUserIdAndCreatedAtBetween(anyLong(), any(), any()))
                .thenReturn((long) FeatureRatingService.DAILY_LIMIT);

        assertThrows(IllegalStateException.class,
                () -> service.submit(7L, "TUTOR", 5, null, null, null, null, null));
        verify(repository, never()).save(any());
    }

    @Test
    void anUnknownFeatureIsStillARating() {
        // A newer app naming a surface this server does not know yet must not lose the answer.
        service.submit(7L, "flashcards", 3, null, null, null, null, null);

        assertEquals(FeatureRating.Feature.PRACTICE, saved().getFeature());
    }

    @Test
    void theFeatureIsReadTheSameOnATurkishServer() {
        Locale before = Locale.getDefault();
        try {
            Locale.setDefault(Locale.forLanguageTag("tr-TR"));
            assertEquals(FeatureRating.Feature.WRITING, FeatureRatingService.parseFeature("writing"));
            assertEquals(FeatureRating.Feature.READING, FeatureRatingService.parseFeature("reading"));
        } finally {
            Locale.setDefault(before);
        }
    }

    @Test
    void aBlankNoteIsNoNote() {
        service.submit(7L, "TUTOR", 2, "   ", null, null, null, null);

        assertNull(saved().getNote());
    }

    @Test
    void aSceneIdThatIsNotACatalogIdIsNotKept() {
        service.submit(7L, "TUTOR", 5, null, "restaurant'; DROP TABLE users;--", null, null, null);

        assertNull(saved().getSceneId());
    }

    @Test
    void anOversizedNoteAndContextAreCutNotRefused() {
        service.submit(7L, "TUTOR", 1, "x".repeat(5000), null, null, null, "y".repeat(9000));

        FeatureRating rating = saved();
        assertEquals(FeatureRatingService.NOTE_MAX, rating.getNote().length());
        assertEquals(FeatureRatingService.CONTEXT_MAX, rating.getContextJson().length());
    }
}
