package com.ingilizce.calismaapp.entity;

import jakarta.persistence.*;
import java.time.LocalDateTime;
import java.util.Random;

@Entity
@Table(name = "users")
public class User {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true)
    private String email;

    @com.fasterxml.jackson.annotation.JsonIgnore
    @Column(nullable = false)
    private String passwordHash;

    @Column(name = "display_name", nullable = false)
    private String displayName;

    @Column(name = "user_tag", nullable = false)
    private String userTag;

    @Column(name = "subscription_end_date")
    private LocalDateTime subscriptionEndDate;

    @Column(name = "ai_plan_code", nullable = false)
    private String aiPlanCode = "FREE";

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private Role role = Role.USER;

    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    @Column(name = "last_seen_at")
    private LocalDateTime lastSeenAt;

    @Column(name = "email_verified_at")
    private LocalDateTime emailVerifiedAt;

    @Column(name = "trial_eligible", nullable = false)
    private boolean trialEligible = true;

    public enum Role {
        USER,
        ADMIN,
        SYSTEM
    }

    public User() {
        this.createdAt = LocalDateTime.now();
        this.userTag = generateUserTag();
    }

    public User(String email, String passwordHash) {
        this.email = email;
        this.passwordHash = passwordHash;
        this.displayName = extractNameFromEmail(email);
        this.userTag = generateUserTag();
        this.createdAt = LocalDateTime.now();
        this.role = Role.USER;
    }

    public User(String email, String passwordHash, String displayName) {
        this.email = email;
        this.passwordHash = passwordHash;
        this.displayName = displayName != null ? displayName : extractNameFromEmail(email);
        this.userTag = generateUserTag();
        this.createdAt = LocalDateTime.now();
        this.role = Role.USER;
    }

    private String extractNameFromEmail(String email) {
        if (email == null || !email.contains("@")) {
            return "User";
        }
        return email.substring(0, email.indexOf("@"));
    }

    private String generateUserTag() {
        Random random = new Random();
        int tagNumber = 10000 + random.nextInt(90000); // 5 digit number
        return "#" + tagNumber;
    }

    // Getters and Setters

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public String getEmail() {
        return email;
    }

    public void setEmail(String email) {
        this.email = email;
    }

    public String getPasswordHash() {
        return passwordHash;
    }

    public void setPasswordHash(String passwordHash) {
        this.passwordHash = passwordHash;
    }

    public String getDisplayName() {
        return displayName;
    }

    public void setDisplayName(String displayName) {
        this.displayName = displayName;
    }

    public String getUserTag() {
        return userTag;
    }

    public void setUserTag(String userTag) {
        this.userTag = userTag;
    }

    public LocalDateTime getSubscriptionEndDate() {
        return subscriptionEndDate;
    }

    public void setSubscriptionEndDate(LocalDateTime subscriptionEndDate) {
        this.subscriptionEndDate = subscriptionEndDate;
    }

    public String getAiPlanCode() {
        return aiPlanCode;
    }

    public void setAiPlanCode(String aiPlanCode) {
        this.aiPlanCode = (aiPlanCode == null || aiPlanCode.isBlank()) ? "FREE" : aiPlanCode;
    }

    public Role getRole() {
        return role;
    }

    public void setRole(Role role) {
        this.role = role;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }

    public LocalDateTime getLastSeenAt() {
        return lastSeenAt;
    }

    public void setLastSeenAt(LocalDateTime lastSeenAt) {
        this.lastSeenAt = lastSeenAt;
    }

    public LocalDateTime getEmailVerifiedAt() {
        return emailVerifiedAt;
    }

    public void setEmailVerifiedAt(LocalDateTime emailVerifiedAt) {
        this.emailVerifiedAt = emailVerifiedAt;
    }

    // Helper method to check active subscription
    public boolean isSubscriptionActive() {
        return subscriptionEndDate != null && subscriptionEndDate.isAfter(LocalDateTime.now());
    }

    // Helper method to check if user is online (active within last 5 minutes)
    public boolean isOnline() {
        if (lastSeenAt == null)
            return false;
        return lastSeenAt.isAfter(LocalDateTime.now().minusMinutes(5));
    }

    public boolean isEmailVerified() {
        return emailVerifiedAt != null;
    }

    public boolean isTrialEligible() {
        return trialEligible;
    }

    public void setTrialEligible(boolean trialEligible) {
        this.trialEligible = trialEligible;
    }
}

