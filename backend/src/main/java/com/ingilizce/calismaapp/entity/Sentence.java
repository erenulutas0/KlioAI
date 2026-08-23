package com.ingilizce.calismaapp.entity;

import jakarta.persistence.*;
import com.fasterxml.jackson.annotation.JsonBackReference;
import com.fasterxml.jackson.annotation.JsonGetter;
import com.fasterxml.jackson.annotation.JsonIgnore;
import com.fasterxml.jackson.annotation.JsonSetter;
import org.hibernate.annotations.OnDelete;
import org.hibernate.annotations.OnDeleteAction;

@Entity
@Table(name = "sentences", indexes = {
        @Index(name = "idx_sentence_content", columnList = "sentence"),
        @Index(name = "idx_sentence_word_id", columnList = "word_id, id"),
        @Index(name = "idx_sentences_meaning", columnList = "meaning_id")
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

    /**
     * The meaning this sentence illustrates, or null for "unassigned" (V028). Every sentence
     * written before V028 is unassigned: we do not know which meaning it was written for, and
     * the UI treats null as "all meanings". Deleting a meaning sets this back to null rather
     * than deleting the sentence -- the database FK does it in production, {@code OnDelete}
     * makes the generated test schema behave the same way. Exposed in JSON as
     * {@code meaningId} only.
     */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "meaning_id")
    @OnDelete(action = OnDeleteAction.SET_NULL)
    @JsonIgnore
    private WordMeaning meaning;

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

    @JsonGetter("sourceTranslation")
    public String getSourceTranslation() {
        return translation;
    }

    @JsonSetter("sourceTranslation")
    public void setSourceTranslation(String sourceTranslation) {
        if ((this.translation == null || this.translation.isBlank()) && sourceTranslation != null) {
            this.translation = sourceTranslation;
        }
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

    public WordMeaning getMeaning() {
        return meaning;
    }

    public void setMeaning(WordMeaning meaning) {
        this.meaning = meaning;
    }

    /** Plain id rather than the nested meaning; reading the id does not initialise the proxy. */
    @JsonGetter("meaningId")
    public Long getMeaningId() {
        return meaning != null ? meaning.getId() : null;
    }
}
