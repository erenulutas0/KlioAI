package com.ingilizce.calismaapp.entity;

import jakarta.persistence.*;

import java.time.LocalDate;
import java.time.LocalDateTime;

@Entity
@Table(name = "daily_content",
        uniqueConstraints = @UniqueConstraint(name = "ux_daily_content_date_type",
                columnNames = {"content_date", "content_type"}))
public class DailyContent {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "content_date", nullable = false)
    private LocalDate contentDate;

    @Column(name = "content_type", nullable = false, length = 50)
    private String contentType;

    @Column(name = "payload_json", nullable = false, columnDefinition = "text")
    private String payloadJson;

    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt;

    public DailyContent() {
        this.createdAt = LocalDateTime.now();
        this.updatedAt = LocalDateTime.now();
    }

    public DailyContent(LocalDate contentDate, String contentType, String payloadJson) {
        this();
        this.contentDate = contentDate;
        this.contentType = contentType;
        this.payloadJson = payloadJson;
    }

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public LocalDate getContentDate() {
        return contentDate;
    }

    public void setContentDate(LocalDate contentDate) {
        this.contentDate = contentDate;
        this.updatedAt = LocalDateTime.now();
    }

    public String getContentType() {
        return contentType;
    }

    public void setContentType(String contentType) {
        this.contentType = contentType;
        this.updatedAt = LocalDateTime.now();
    }

    public String getPayloadJson() {
        return payloadJson;
    }

    public void setPayloadJson(String payloadJson) {
        this.payloadJson = payloadJson;
        this.updatedAt = LocalDateTime.now();
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }

    public LocalDateTime getUpdatedAt() {
        return updatedAt;
    }

    public void setUpdatedAt(LocalDateTime updatedAt) {
        this.updatedAt = updatedAt;
    }
}

