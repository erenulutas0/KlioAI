package com.ingilizce.calismaapp.entity;

import com.fasterxml.jackson.annotation.JsonBackReference;
import com.fasterxml.jackson.annotation.JsonIgnore;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.persistence.*;

import java.time.LocalDateTime;

/**
 * One meaning of a {@link Word}: a translation in the source language and an optional
 * definition. A word has one or more of these, ordered by {@link #position}.
 *
 * <p>Until V028 a word carried a single comma-joined {@code turkish_meaning} string. That
 * string is kept as a denormalised copy for the shipped client; this row is what new code
 * edits, and what a {@link Sentence} can be attached to.
 *
 * <p>Column names, lengths and nullability mirror V028 exactly -- production runs with
 * {@code ddl-auto=validate}.
 *
 * <p>{@code JsonIgnoreProperties}: when a word is loaded with its sentences fetch-joined, a
 * sentence's lazy {@code meaning} registers a proxy for this row before the word's own
 * meanings collection is read, and Hibernate then hands that same proxy back inside the
 * collection. Jackson would otherwise try to serialise the proxy's initializer.
 */
@Entity
@JsonIgnoreProperties(value = { "hibernateLazyInitializer", "handler" }, ignoreUnknown = true)
@Table(name = "word_meanings", indexes = {
        @Index(name = "idx_word_meanings_word", columnList = "word_id")
})
public class WordMeaning {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "word_id", nullable = false)
    @JsonBackReference("word-meanings")
    private Word word;

    @Column(nullable = false, length = 255)
    private String translation;

    @Column(columnDefinition = "TEXT")
    private String definition;

    @Column(nullable = false)
    private int position = 0;

    @JsonIgnore
    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    public WordMeaning() {
    }

    public WordMeaning(Word word, String translation, String definition, int position) {
        this.word = word;
        this.translation = translation;
        this.definition = definition;
        this.position = position;
    }

    @PrePersist
    void onCreate() {
        if (createdAt == null) {
            createdAt = LocalDateTime.now();
        }
    }

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public Word getWord() {
        return word;
    }

    public void setWord(Word word) {
        this.word = word;
    }

    public String getTranslation() {
        return translation;
    }

    public void setTranslation(String translation) {
        this.translation = translation;
    }

    public String getDefinition() {
        return definition;
    }

    public void setDefinition(String definition) {
        this.definition = definition;
    }

    public int getPosition() {
        return position;
    }

    public void setPosition(int position) {
        this.position = position;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }
}
