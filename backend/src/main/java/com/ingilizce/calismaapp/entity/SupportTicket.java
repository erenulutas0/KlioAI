package com.ingilizce.calismaapp.entity;

import jakarta.persistence.*;

import java.time.LocalDateTime;

@Entity
@Table(name = "support_tickets", indexes = {
        @Index(name = "idx_support_tickets_user_created", columnList = "user_id, created_at"),
        @Index(name = "idx_support_tickets_expires_at", columnList = "expires_at")
})
public class SupportTicket {

    public enum TicketType {
        REQUEST,
        COMPLAINT,
        BUG,
        ACCOUNT_DELETION,

        /**
         * A learner flagging generated content as wrong.
         *
         * <p>Separate from BUG because it is the one failure the instrumentation cannot see.
         * For three months this app served hardcoded template sentences -- "Maya noticed
         * evaluate during the trip" -- as if a model had written them, while the dashboard
         * reported every one of those calls a success. A metric can say the request
         * returned 200; only a person can say the sentence was nonsense.
         */
        CONTENT_REPORT,

        /**
         * An answer to the app asking how it is going, unprompted by any problem.
         *
         * <p>Distinct from CONTENT_REPORT, which is somebody reacting to one bad sentence in
         * front of them. This is the wider question -- is the app teaching you anything --
         * and it only exists because we ask it. Nobody opens a support form to say "it is
         * fine but the sentences feel repetitive", and that is exactly the kind of thing
         * worth knowing before the reviews arrive.
         */
        FEEDBACK
    }

    public enum TicketStatus {
        OPEN,
        CLOSED
    }

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 32)
    private TicketType type;

    @Column(nullable = false, length = 140)
    private String title;

    @Column(nullable = false, columnDefinition = "TEXT")
    private String message;

    @Column(length = 16)
    private String locale;

    /**
     * Machine-collected context: app version, the screen it was sent from, and for a content
     * report the offending text itself.
     *
     * <p>Without this a report is unactionable. "Bu çalışmıyor" from an unknown build on an
     * unknown screen cannot be reproduced, and a beta tester should not have to write a bug
     * report to be useful — the app knows where they were, so the app should say so.
     *
     * <p>Deliberately free-form JSON rather than columns: what is worth capturing will change
     * faster than the schema should, and an unknown key is better stored than dropped.
     */
    @Column(name = "context_json", columnDefinition = "TEXT")
    private String contextJson;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 32)
    private TicketStatus status = TicketStatus.OPEN;

    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    @Column(name = "expires_at", nullable = false)
    private LocalDateTime expiresAt;

    @PrePersist
    void onCreate() {
        if (createdAt == null) {
            createdAt = LocalDateTime.now();
        }
        if (expiresAt == null) {
            expiresAt = createdAt.plusDays(7);
        }
        if (status == null) {
            status = TicketStatus.OPEN;
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

    public TicketType getType() {
        return type;
    }

    public void setType(TicketType type) {
        this.type = type;
    }

    public String getTitle() {
        return title;
    }

    public void setTitle(String title) {
        this.title = title;
    }

    public String getMessage() {
        return message;
    }

    public void setMessage(String message) {
        this.message = message;
    }

    public String getContextJson() {
        return contextJson;
    }

    public void setContextJson(String contextJson) {
        this.contextJson = contextJson;
    }

    public String getLocale() {
        return locale;
    }

    public void setLocale(String locale) {
        this.locale = locale;
    }

    public TicketStatus getStatus() {
        return status;
    }

    public void setStatus(TicketStatus status) {
        this.status = status;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public LocalDateTime getExpiresAt() {
        return expiresAt;
    }

    public void setExpiresAt(LocalDateTime expiresAt) {
        this.expiresAt = expiresAt;
    }
}
