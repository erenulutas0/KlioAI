package com.ingilizce.calismaapp.entity;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.persistence.*;

import java.time.LocalDateTime;

/**
 * A book on the reading shelf.
 *
 * <p>Only works whose copyright has expired. The text is imported once,
 * translated once and served from the database, so a chapter costs nothing to
 * read no matter how many learners read it.
 *
 * <p>Column names, lengths and nullability mirror V029 exactly -- production
 * runs with {@code ddl-auto=validate}.
 */
@Entity
@JsonIgnoreProperties(value = { "hibernateLazyInitializer", "handler" }, ignoreUnknown = true)
@Table(name = "books")
public class Book {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * Stable identifier shared with the import script, so re-importing a book
     * updates it rather than shelving a second copy.
     */
    @Column(name = "slug", nullable = false, unique = true, length = 120)
    private String slug;

    @Column(name = "title", nullable = false, length = 300)
    private String title;

    @Column(name = "author", nullable = false, length = 200)
    private String author;

    /**
     * The language the book is written in, matching
     * {@link LanguageProfile#getTargetLanguage()}. English today; the field is
     * what lets a German shelf appear later without a migration.
     */
    @Column(name = "language", nullable = false, length = 40)
    private String language = LanguageProfile.DEFAULT_TARGET_LANGUAGE;

    /** Rough CEFR reading level, for ordering the shelf. Null when unjudged. */
    @Column(name = "level", length = 10)
    private String level;

    /**
     * Where the text came from, e.g. {@code gutenberg:1661}. Kept so the
     * provenance of anything in the library can still be answered years later.
     */
    @Column(name = "source", length = 200)
    private String source;

    /** Denormalised: the shelf needs a length without counting sentence rows. */
    @Column(name = "sentence_count", nullable = false)
    private Integer sentenceCount = 0;

    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt = LocalDateTime.now();

    public Book() {
    }

    public Book(String slug, String title, String author, String language, String level, String source) {
        this.slug = slug;
        this.title = title;
        this.author = author;
        this.language = language == null ? LanguageProfile.DEFAULT_TARGET_LANGUAGE : language;
        this.level = level;
        this.source = source;
    }

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public String getSlug() {
        return slug;
    }

    public void setSlug(String slug) {
        this.slug = slug;
    }

    public String getTitle() {
        return title;
    }

    public void setTitle(String title) {
        this.title = title;
    }

    public String getAuthor() {
        return author;
    }

    public void setAuthor(String author) {
        this.author = author;
    }

    public String getLanguage() {
        return language;
    }

    public void setLanguage(String language) {
        this.language = language;
    }

    public String getLevel() {
        return level;
    }

    public void setLevel(String level) {
        this.level = level;
    }

    public String getSource() {
        return source;
    }

    public void setSource(String source) {
        this.source = source;
    }

    public Integer getSentenceCount() {
        return sentenceCount == null ? 0 : sentenceCount;
    }

    public void setSentenceCount(Integer sentenceCount) {
        this.sentenceCount = sentenceCount;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }
}
