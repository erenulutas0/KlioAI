package com.ingilizce.calismaapp.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import java.time.LocalDateTime;

@Entity
@Table(name = "notification_preferences")
public class NotificationPreference {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "user_id", nullable = false, unique = true)
    private Long userId;

    @Column(name = "daily_reminders_enabled", nullable = false)
    private boolean dailyRemindersEnabled;

    @Column(name = "streak_guard_enabled", nullable = false)
    private boolean streakGuardEnabled = true;

    @Column(name = "product_updates_enabled", nullable = false)
    private boolean productUpdatesEnabled;

    @Column(name = "subscription_alerts_enabled", nullable = false)
    private boolean subscriptionAlertsEnabled = true;

    @Column(name = "social_enabled", nullable = false)
    private boolean socialEnabled = true;

    @Column(name = "quiet_hours_enabled", nullable = false)
    private boolean quietHoursEnabled = true;

    @Column(name = "quiet_hours_start_local", nullable = false, length = 5)
    private String quietHoursStartLocal = "22:30";

    @Column(name = "quiet_hours_end_local", nullable = false, length = 5)
    private String quietHoursEndLocal = "09:00";

    @Column(nullable = false, length = 64)
    private String timezone = "Europe/Istanbul";

    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt;

    @PrePersist
    void onCreate() {
        LocalDateTime now = LocalDateTime.now();
        createdAt = now;
        updatedAt = now;
    }

    @PreUpdate
    void onUpdate() {
        updatedAt = LocalDateTime.now();
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

    public boolean isDailyRemindersEnabled() {
        return dailyRemindersEnabled;
    }

    public void setDailyRemindersEnabled(boolean dailyRemindersEnabled) {
        this.dailyRemindersEnabled = dailyRemindersEnabled;
    }

    public boolean isStreakGuardEnabled() {
        return streakGuardEnabled;
    }

    public void setStreakGuardEnabled(boolean streakGuardEnabled) {
        this.streakGuardEnabled = streakGuardEnabled;
    }

    public boolean isProductUpdatesEnabled() {
        return productUpdatesEnabled;
    }

    public void setProductUpdatesEnabled(boolean productUpdatesEnabled) {
        this.productUpdatesEnabled = productUpdatesEnabled;
    }

    public boolean isSubscriptionAlertsEnabled() {
        return subscriptionAlertsEnabled;
    }

    public void setSubscriptionAlertsEnabled(boolean subscriptionAlertsEnabled) {
        this.subscriptionAlertsEnabled = subscriptionAlertsEnabled;
    }

    public boolean isSocialEnabled() {
        return socialEnabled;
    }

    public void setSocialEnabled(boolean socialEnabled) {
        this.socialEnabled = socialEnabled;
    }

    public boolean isQuietHoursEnabled() {
        return quietHoursEnabled;
    }

    public void setQuietHoursEnabled(boolean quietHoursEnabled) {
        this.quietHoursEnabled = quietHoursEnabled;
    }

    public String getQuietHoursStartLocal() {
        return quietHoursStartLocal;
    }

    public void setQuietHoursStartLocal(String quietHoursStartLocal) {
        this.quietHoursStartLocal = quietHoursStartLocal;
    }

    public String getQuietHoursEndLocal() {
        return quietHoursEndLocal;
    }

    public void setQuietHoursEndLocal(String quietHoursEndLocal) {
        this.quietHoursEndLocal = quietHoursEndLocal;
    }

    public String getTimezone() {
        return timezone;
    }

    public void setTimezone(String timezone) {
        this.timezone = timezone;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public LocalDateTime getUpdatedAt() {
        return updatedAt;
    }
}
