package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.entity.ReviewEvent;
import com.ingilizce.calismaapp.entity.ReviewSource;
import com.ingilizce.calismaapp.entity.Word;
import com.ingilizce.calismaapp.repository.ReviewEventRepository;
import com.ingilizce.calismaapp.repository.WordRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

import java.time.LocalDate;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

/**
 * Nothing recorded that a review happened. Word carries only the scheduler's current state,
 * so every grade overwrote the one before it and the history was gone — which left the
 * product's central claim, a memory of how this learner is doing, with no data behind it.
 *
 * <p>These tests hold the log in place, and in particular that the "before" state is read
 * before the update overwrites it. Capturing it a line too late would store the new interval
 * as if it were the old one, and every model later fitted on this table would be wrong in a
 * way nobody would notice.
 */
class SRSReviewEventTest {

    @InjectMocks
    private SRSService srsService;

    @Mock
    private WordRepository wordRepository;

    @Mock
    private ProgressService progressService;

    @Mock
    private ReviewEventRepository reviewEventRepository;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
        when(wordRepository.save(any(Word.class))).thenAnswer(inv -> inv.getArgument(0));
    }

    private Word scheduledWord() {
        Word word = new Word();
        word.setId(7L);
        word.setUserId(1L);
        word.setEnglishWord("elaborate");
        word.setReviewCount(3);
        word.setEaseFactor(2.36);
        // Last reviewed 10 days ago and scheduled 6 days after that: the previous interval
        // was 6 days.
        word.setLastReviewDate(LocalDate.now().minusDays(10));
        word.setNextReviewDate(LocalDate.now().minusDays(4));
        return word;
    }

    @Test
    void submitReview_writesAnEventCarryingBothSidesOfTheChange() {
        Word word = scheduledWord();
        when(wordRepository.findByIdAndUserId(7L, 1L)).thenReturn(Optional.of(word));

        srsService.submitReview(1L, 7L, 4, ReviewSource.CLASSIC_REVIEW, 3200);

        ArgumentCaptor<ReviewEvent> captor = ArgumentCaptor.forClass(ReviewEvent.class);
        verify(reviewEventRepository).save(captor.capture());
        ReviewEvent event = captor.getValue();

        assertEquals(1L, event.getUserId());
        assertEquals(7L, event.getWordId());
        assertEquals(4, event.getGrade());
        assertEquals(ReviewSource.CLASSIC_REVIEW, event.getSourceFeature());
        assertEquals(3200, event.getResponseMs());
        assertNotNull(event.getCreatedAt());

        // The state as it was, not as it became.
        assertEquals(2.36, event.getEaseBefore(),
                "ease must be captured before SM-2 recomputes it");
        assertEquals(3, event.getRepetitionBefore(),
                "repetition must be the count before this attempt");
        assertEquals(6, event.getIntervalBeforeDays(),
                "the previous interval is the gap between last and next review");

        // And the state it became, so a row can be read without replaying the history.
        //
        // Note the ease is unchanged here and that is correct SM-2, not a missed write:
        // EF' = EF + (0.1 - (5-q)(0.08 + (5-q)0.02)) is exactly zero at q=4. A "good"
        // answer is defined as one that leaves difficulty where it was.
        assertNotNull(event.getEaseAfter());
        assertEquals(2.36, event.getEaseAfter(), 1e-9);
        assertNotNull(event.getIntervalAfterDays());
        assertTrue(event.getIntervalAfterDays() > 0);
    }

    @Test
    void anEasyAnswerRaisesTheEaseAndAHardOneLowersIt() {
        // The pair that proves both sides of the change are really being captured rather
        // than the same number written twice.
        Word easy = scheduledWord();
        when(wordRepository.findByIdAndUserId(7L, 1L)).thenReturn(Optional.of(easy));
        srsService.submitReview(1L, 7L, 5, ReviewSource.CLASSIC_REVIEW, null);

        ArgumentCaptor<ReviewEvent> captor = ArgumentCaptor.forClass(ReviewEvent.class);
        verify(reviewEventRepository).save(captor.capture());
        ReviewEvent afterEasy = captor.getValue();
        assertTrue(afterEasy.getEaseAfter() > afterEasy.getEaseBefore(),
                "a perfect answer must make the word easier");

        reset(reviewEventRepository);
        Word hard = scheduledWord();
        when(wordRepository.findByIdAndUserId(7L, 1L)).thenReturn(Optional.of(hard));
        srsService.submitReview(1L, 7L, 2, ReviewSource.CLASSIC_REVIEW, null);

        ArgumentCaptor<ReviewEvent> hardCaptor = ArgumentCaptor.forClass(ReviewEvent.class);
        verify(reviewEventRepository).save(hardCaptor.capture());
        ReviewEvent afterHard = hardCaptor.getValue();
        assertTrue(afterHard.getEaseAfter() < afterHard.getEaseBefore(),
                "a failed answer must make the word harder");
    }

    @Test
    void submitReview_recordsWhichScreenProducedTheGrade() {
        // The point of the log is to accept evidence from anywhere the app judges an answer,
        // not only the flashcard screen.
        Word word = scheduledWord();
        when(wordRepository.findByIdAndUserId(7L, 1L)).thenReturn(Optional.of(word));

        srsService.submitReview(1L, 7L, 5, ReviewSource.GRAMMAR_PRACTICE, null);

        ArgumentCaptor<ReviewEvent> captor = ArgumentCaptor.forClass(ReviewEvent.class);
        verify(reviewEventRepository).save(captor.capture());
        assertEquals(ReviewSource.GRAMMAR_PRACTICE, captor.getValue().getSourceFeature());
        assertNull(captor.getValue().getResponseMs(), "an unreported time stays null");
    }

    @Test
    void submitReview_fromAnOlderClientStillLogsAUsableRow() {
        // A client that sends no source must not be refused; losing the observation would be
        // worse than storing an unnamed one.
        Word word = scheduledWord();
        when(wordRepository.findByIdAndUserId(7L, 1L)).thenReturn(Optional.of(word));

        srsService.submitReview(1L, 7L, 3);

        ArgumentCaptor<ReviewEvent> captor = ArgumentCaptor.forClass(ReviewEvent.class);
        verify(reviewEventRepository).save(captor.capture());
        assertEquals(ReviewSource.UNSPECIFIED, captor.getValue().getSourceFeature());
        assertEquals(3, captor.getValue().getGrade());
    }

    @Test
    void aFailedLogWriteNeverBreaksTheReview() {
        // The learner's progress must not depend on an analytics write succeeding.
        Word word = scheduledWord();
        when(wordRepository.findByIdAndUserId(7L, 1L)).thenReturn(Optional.of(word));
        when(reviewEventRepository.save(any(ReviewEvent.class)))
                .thenThrow(new RuntimeException("database unavailable"));

        Word result = assertDoesNotThrow(
                () -> srsService.submitReview(1L, 7L, 4, ReviewSource.CLASSIC_REVIEW, 1000));

        assertNotNull(result);
        verify(wordRepository).save(any(Word.class));
    }

    @Test
    void aFirstEverReviewReportsNoPreviousInterval() {
        // There genuinely was no previous interval; reporting zero would be a lie that a
        // model would read as "this was due immediately".
        Word word = new Word();
        word.setId(9L);
        word.setUserId(1L);
        word.setEnglishWord("nascent");
        when(wordRepository.findByIdAndUserId(9L, 1L)).thenReturn(Optional.of(word));

        srsService.submitReview(1L, 9L, 4, ReviewSource.CLASSIC_REVIEW, null);

        ArgumentCaptor<ReviewEvent> captor = ArgumentCaptor.forClass(ReviewEvent.class);
        verify(reviewEventRepository).save(captor.capture());
        assertNull(captor.getValue().getIntervalBeforeDays());
    }
}
