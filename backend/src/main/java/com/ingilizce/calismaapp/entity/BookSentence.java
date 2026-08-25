package com.ingilizce.calismaapp.entity;

import com.fasterxml.jackson.annotation.JsonIgnore;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.persistence.*;

/**
 * One sentence of a book.
 *
 * <p>Not decoration. A learner taps a word inside this sentence and it enters
 * their deck with this text as its context, so the sentence becomes review
 * material they will see for months. That is why it is a row: stored once,
 * checked once, and identical for everyone who reads the book.
 *
 * <p>Mirrors V029 exactly -- production runs with {@code ddl-auto=validate}.
 */
@Entity
@JsonIgnoreProperties(value = { "hibernateLazyInitializer", "handler" }, ignoreUnknown = true)
@Table(name = "book_sentences", indexes = {
        @Index(name = "idx_book_sentences_book_position", columnList = "book_id, sentence_index")
}, uniqueConstraints = {
        @UniqueConstraint(name = "uq_book_sentence_position", columnNames = { "book_id", "sentence_index" })
})
public class BookSentence {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "book_id", nullable = false)
    @JsonIgnore
    private Book book;

    /**
     * Position in the book as a whole, and what reading progress points at.
     * Stable on purpose: renumbering on a re-import would move every reader.
     */
    @Column(name = "sentence_index", nullable = false)
    private Integer sentenceIndex;

    @Column(name = "chapter_index", nullable = false)
    private Integer chapterIndex = 0;

    @Column(name = "chapter_title", length = 300)
    private String chapterTitle;

    @Column(name = "text", nullable = false, columnDefinition = "TEXT")
    private String text;

    /**
     * Translated once at import. Null means "not translated yet" — which the
     * reader shows as a translation being unavailable, never as an empty one.
     */
    @Column(name = "translation", columnDefinition = "TEXT")
    private String translation;

    public BookSentence() {
    }

    public BookSentence(Book book, int sentenceIndex, int chapterIndex, String chapterTitle, String text) {
        this.book = book;
        this.sentenceIndex = sentenceIndex;
        this.chapterIndex = chapterIndex;
        this.chapterTitle = chapterTitle;
        this.text = text;
    }

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public Book getBook() {
        return book;
    }

    public void setBook(Book book) {
        this.book = book;
    }

    public Integer getSentenceIndex() {
        return sentenceIndex;
    }

    public void setSentenceIndex(Integer sentenceIndex) {
        this.sentenceIndex = sentenceIndex;
    }

    public Integer getChapterIndex() {
        return chapterIndex == null ? 0 : chapterIndex;
    }

    public void setChapterIndex(Integer chapterIndex) {
        this.chapterIndex = chapterIndex;
    }

    public String getChapterTitle() {
        return chapterTitle;
    }

    public void setChapterTitle(String chapterTitle) {
        this.chapterTitle = chapterTitle;
    }

    public String getText() {
        return text;
    }

    public void setText(String text) {
        this.text = text;
    }

    public String getTranslation() {
        return translation;
    }

    public void setTranslation(String translation) {
        this.translation = translation;
    }
}
