package com.ingilizce.calismaapp.entity;

import jakarta.persistence.*;
import com.fasterxml.jackson.annotation.JsonBackReference;

@Entity
@Table(name = "sentences", indexes = {
        @Index(name = "idx_sentence_content", columnList = "sentence"),
        @Index(name = "idx_sentence_word_id", columnList = "word_id, id")
})
public class Sentence {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String sentence;

    @Column
    private String translation;

    @Column
    private String difficulty;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "word_id", nullable = false)
    @JsonBackReference
    private Word word;

    // Constructors
    public Sentence() {
    }

    public Sentence(String sentence, String translation, String difficulty, Word word) {
        this.sentence = sentence;
        this.translation = translation;
        this.difficulty = difficulty;
        this.word = word;
    }

    // Getters and Setters
    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public String getSentence() {
        return sentence;
    }

    public void setSentence(String sentence) {
        this.sentence = sentence;
    }

    public String getTranslation() {
        return translation;
    }

    public void setTranslation(String translation) {
        this.translation = translation;
    }

    public Word getWord() {
        return word;
    }

    public void setWord(Word word) {
        this.word = word;
    }

    public String getDifficulty() {
        return difficulty;
    }

    public void setDifficulty(String difficulty) {
        this.difficulty = difficulty;
    }

    // Helper method to get wordId for JSON serialization
    @com.fasterxml.jackson.annotation.JsonGetter("wordId")
    public Long getWordId() {
        return word != null ? word.getId() : null;
    }
}
