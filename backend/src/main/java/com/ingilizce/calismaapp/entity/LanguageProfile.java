package com.ingilizce.calismaapp.entity;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.persistence.*;

import java.time.LocalDateTime;

/**
 * One language a user is learning: source language, target language, level and goal.
 *
 * <p>A user has one or more of these and exactly one is active. Every {@link Word} belongs to
 * a profile. The app is English-only today, so in practice each user has a single
 * Turkish -> English profile created by the V028 backfill; the structure exists so that a
 * second target language can be added without touching the words table again.
 *
 * <p>Column names, lengths and nullability mirror V028 exactly -- production runs with
 * {@code ddl-auto=validate}.
 */
@Entity
@JsonIgnoreProperties(value = { "hibernateLazyInitializer", "handler" }, ignoreUnknown = true)
@Table(name = "language_profiles", indexes = {
        @Index(name = "idx_language_profiles_user", columnList = "user_id")
}, uniqueConstraints = {
        @UniqueConstraint(name = "uk_language_profiles_user_target", columnNames = { "user_id", "target_language" })
})
public class LanguageProfile {

    public static final String DEFAULT_SOURCE_LANGUAGE = "Turkish";
    public static final String DEFAULT_TARGET_LANGUAGE = "English";
    public static final String DEFAULT_LEVEL = "B1";

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    @Column(name = "source_language", nullable = false, length = 32)
    private String sourceLanguage;

    @Column(name = "target_language", nullable = false, length = 32)
    private String targetLanguage;

    @Column(name = "level", nullable = false, length = 8)
    private String level = DEFAULT_LEVEL;

    @Column(name = "learning_goal", length = 32)
    private String learningGoal;

    /** Serialised as {@code isActive}; the bare field name would become {@code active}. */
    @JsonProperty("isActive")
    @Column(name = "is_active", nullable = false)
    private boolean active = true;

    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    public LanguageProfile() {
    }

    public LanguageProfile(Long userId, String sourceLanguage, String targetLanguage, String level,
            String learningGoal, boolean active) {
        this.userId = userId;
        this.sourceLanguage = sourceLanguage;
        this.targetLanguage = targetLanguage;
        this.level = level != null ? level : DEFAULT_LEVEL;
        this.learningGoal = learningGoal;
        this.active = active;
    }

    /** The Turkish -> English profile the backfill gives everyone; used when a user has none. */
    public static LanguageProfile defaultEnglishProfile(Long userId) {
        return new LanguageProfile(userId, DEFAULT_SOURCE_LANGUAGE, DEFAULT_TARGET_LANGUAGE, DEFAULT_LEVEL, null, true);
    }

    @PrePersist
    void onCreate() {
        if (createdAt == null) {
            createdAt = LocalDateTime.now();
        }
        if (level == null || level.isBlank()) {
            level = DEFAULT_LEVEL;
        }
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

    public String getSourceLanguage() {
        return sourceLanguage;
    }

    public void setSourceLanguage(String sourceLanguage) {
        this.sourceLanguage = sourceLanguage;
    }

    public String getTargetLanguage() {
        return targetLanguage;
    }

    public void setTargetLanguage(String targetLanguage) {
        this.targetLanguage = targetLanguage;
    }

    public String getLevel() {
        return level;
    }

    public void setLevel(String level) {
        this.level = level;
    }

    public String getLearningGoal() {
        return learningGoal;
    }

    public void setLearningGoal(String learningGoal) {
        this.learningGoal = learningGoal;
    }

    public boolean isActive() {
        return active;
    }

    public void setActive(boolean active) {
        this.active = active;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }
}
