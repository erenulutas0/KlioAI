package com.ingilizce.calismaapp.entity;

import jakarta.persistence.*;

import java.time.LocalDateTime;

/**
 * A learner's 1-5 answer to "how was this?". See V031 for why this is not a support ticket.
 */
@Entity
@Table(name = "feature_ratings", indexes = {
        @Index(name = "idx_feature_ratings_created", columnList = "created_at"),
        @Index(name = "idx_feature_ratings_user_created", columnList = "user_id, created_at")
})
public class FeatureRating {

    /** What was rated. Stored by name; an unknown name from an app is read as PRACTICE. */
    public enum Feature {
        TUTOR,
        READING,
        WRITING,
        SESSION,
        PRACTICE
    }

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 32)
    private Feature feature;

    @Column(nullable = false)
    private Integer stars;

    @Column(columnDefinition = "TEXT")
    private String note;

    @Column(name = "scene_id", length = 64)
    private String sceneId;

    @Column(length = 16)
    private String locale;

    @Column(name = "app_version", length = 32)
    private String appVersion;

    @Column(name = "context_json", columnDefinition = "TEXT")
    private String contextJson;

    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    @PrePersist
    void onCreate() {
        if (createdAt == null) {
            createdAt = LocalDateTime.now();
        }
    }

    public Long getId() {
        return id;
    }

    public Long getUserId() {
        return userId;
    }

    public void setUserId(Long userId) {
        this.userId = userId;
    }

    public Feature getFeature() {
        return feature;
    }

    public void setFeature(Feature feature) {
        this.feature = feature;
    }

    public Integer getStars() {
        return stars;
    }

    public void setStars(Integer stars) {
        this.stars = stars;
    }

    public String getNote() {
        return note;
    }

    public void setNote(String note) {
        this.note = note;
    }

    public String getSceneId() {
        return sceneId;
    }

    public void setSceneId(String sceneId) {
        this.sceneId = sceneId;
    }

    public String getLocale() {
        return locale;
    }

    public void setLocale(String locale) {
        this.locale = locale;
    }

    public String getAppVersion() {
        return appVersion;
    }

    public void setAppVersion(String appVersion) {
        this.appVersion = appVersion;
    }

    public String getContextJson() {
        return contextJson;
    }

    public void setContextJson(String contextJson) {
        this.contextJson = contextJson;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }
}
