package com.ingilizce.calismaapp.entity;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.persistence.*;

import java.time.LocalDateTime;

/**
 * How far one learner has read one book.
 *
 * <p>A row with {@code lastSentenceIndex = 0} is a book that has been opened
 * and not yet read; no row at all is a book never started. The shelf shows
 * those differently, so the distinction is kept rather than collapsed into a
 * default.
 *
 * <p>Mirrors V029 exactly -- production runs with {@code ddl-auto=validate}.
 */
@Entity
@JsonIgnoreProperties(value = { "hibernateLazyInitializer", "handler" }, ignoreUnknown = true)
@Table(name = "book_progress", indexes = {
        @Index(name = "idx_book_progress_user", columnList = "user_id")
}, uniqueConstraints = {
        @UniqueConstraint(name = "uq_book_progress_user_book", columnNames = { "user_id", "book_id" })
})
public class BookProgress {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "book_id", nullable = false)
    private Book book;

    @Column(name = "last_sentence_index", nullable = false)
    private Integer lastSentenceIndex = 0;

    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt = LocalDateTime.now();

    public BookProgress() {
    }

    public BookProgress(Long userId, Book book) {
        this.userId = userId;
        this.book = book;
    }

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public Long getUserId() {
        return userId;
    }

    public void setUserId(Long userId) {
        this.userId = userId;
    }

    public Book getBook() {
        return book;
    }

    public void setBook(Book book) {
        this.book = book;
    }

    public Integer getLastSentenceIndex() {
        return lastSentenceIndex == null ? 0 : lastSentenceIndex;
    }

    public void setLastSentenceIndex(Integer lastSentenceIndex) {
        this.lastSentenceIndex = lastSentenceIndex;
    }

    public LocalDateTime getUpdatedAt() {
        return updatedAt;
    }

    public void setUpdatedAt(LocalDateTime updatedAt) {
        this.updatedAt = updatedAt;
    }
}
