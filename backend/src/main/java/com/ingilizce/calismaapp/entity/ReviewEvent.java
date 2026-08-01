package com.ingilizce.calismaapp.entity;

import jakarta.persistence.*;
import java.time.Instant;

/**
 * One immutable record of a single graded recall attempt.
 *
 * <p>Nothing in this application used to remember that a review happened. {@code Word}
 * carries only the scheduler's current state -- next date, interval, ease factor -- so every
 * grade overwrote the one before it. The consequence is that the product's central claim,
 * a memory of how this learner is doing on their own vocabulary, had no data behind it.
 *
 * <p>What this table makes possible, none of which can be done from the current state alone:
 * fitting a scheduler to the individual (FSRS and its successors are trained on exactly this
 * shape of log), telling a learner which pairs they keep confusing, showing a real forgetting
 * curve, and measuring whether a change to the app helped anyone retain anything.
 *
 * <p>Append-only by intention. Rows are never updated or deleted, because the value is in the
 * history and a corrected row is a lost observation. {@link #sourceFeature} records which
 * surface produced the grade -- classic review, word galaxy, translation practice, grammar
 * drills -- so the same loop can be fed from anywhere the app judges an answer.
 */
@Entity
@Table(
        name = "review_events",
        indexes = {
                @Index(name = "idx_review_events_user_created", columnList = "user_id, created_at"),
                @Index(name = "idx_review_events_word_created", columnList = "word_id, created_at")
        })
public class ReviewEvent {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    @Column(name = "word_id", nullable = false)
    private Long wordId;

    /** Which surface produced this grade; see {@link ReviewSource}. */
    @Column(name = "source_feature", nullable = false, length = 40)
    private String sourceFeature;

    /** SM-2 quality, 0-5. */
    @Column(name = "grade", nullable = false)
    private int grade;

    /**
     * Scheduler state as it was immediately before this grade, and as it became after.
     *
     * <p>Both sides are stored so a row can be interpreted on its own. Reconstructing the
     * "before" by walking every earlier row is possible but fragile: a backfill, a manual
     * fix or a scheduler change would silently corrupt every later reconstruction.
     */
    @Column(name = "interval_before_days")
    private Integer intervalBeforeDays;

    @Column(name = "interval_after_days")
    private Integer intervalAfterDays;

    @Column(name = "ease_before")
    private Double easeBefore;

    @Column(name = "ease_after")
    private Double easeAfter;

    /** Review count before this attempt; the repetition number in SM-2 terms. */
    @Column(name = "repetition_before")
    private Integer repetitionBefore;

    /** How long the learner took to answer, when the client reports it. */
    @Column(name = "response_ms")
    private Integer responseMs;

    /** Always UTC. Local dates make the data unusable across time zones. */
    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    public ReviewEvent() {
    }

    public ReviewEvent(
            Long userId,
            Long wordId,
            String sourceFeature,
            int grade,
            Integer intervalBeforeDays,
            Integer intervalAfterDays,
            Double easeBefore,
            Double easeAfter,
            Integer repetitionBefore,
            Integer responseMs) {
        this.userId = userId;
        this.wordId = wordId;
        this.sourceFeature = sourceFeature;
        this.grade = grade;
        this.intervalBeforeDays = intervalBeforeDays;
        this.intervalAfterDays = intervalAfterDays;
        this.easeBefore = easeBefore;
        this.easeAfter = easeAfter;
        this.repetitionBefore = repetitionBefore;
        this.responseMs = responseMs;
        this.createdAt = Instant.now();
    }

    public Long getId() {
        return id;
    }

    public Long getUserId() {
        return userId;
    }

    public Long getWordId() {
        return wordId;
    }

    public String getSourceFeature() {
        return sourceFeature;
    }

    public int getGrade() {
        return grade;
    }

    public Integer getIntervalBeforeDays() {
        return intervalBeforeDays;
    }

    public Integer getIntervalAfterDays() {
        return intervalAfterDays;
    }

    public Double getEaseBefore() {
        return easeBefore;
    }

    public Double getEaseAfter() {
        return easeAfter;
    }

    public Integer getRepetitionBefore() {
        return repetitionBefore;
    }

    public Integer getResponseMs() {
        return responseMs;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(Instant createdAt) {
        this.createdAt = createdAt;
    }
}
