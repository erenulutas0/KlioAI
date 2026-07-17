package com.ingilizce.calismaapp.entity;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.time.LocalDateTime;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;

class DailyContentTest {

    @Test
    void constructorShouldSetContentFieldsAndTimestamps() {
        LocalDate date = LocalDate.of(2026, 7, 6);

        DailyContent content = new DailyContent(date, "daily_words_v3", "{\"words\":[]}");

        assertNull(content.getId());
        assertEquals(date, content.getContentDate());
        assertEquals("daily_words_v3", content.getContentType());
        assertEquals("{\"words\":[]}", content.getPayloadJson());
        assertNotNull(content.getCreatedAt());
        assertNotNull(content.getUpdatedAt());
    }

    @Test
    void settersShouldUpdateMutableFieldsAndUpdatedAt() {
        DailyContent content = new DailyContent();
        LocalDateTime createdAt = LocalDateTime.of(2026, 7, 6, 10, 0);
        LocalDateTime updatedAt = LocalDateTime.of(2026, 7, 6, 10, 5);

        content.setId(99L);
        content.setCreatedAt(createdAt);
        content.setUpdatedAt(updatedAt);
        content.setContentDate(LocalDate.of(2026, 7, 7));
        content.setContentType("daily_reading_v2_b1");
        content.setPayloadJson("{\"title\":\"Reading\"}");

        assertEquals(99L, content.getId());
        assertEquals(createdAt, content.getCreatedAt());
        assertEquals(LocalDate.of(2026, 7, 7), content.getContentDate());
        assertEquals("daily_reading_v2_b1", content.getContentType());
        assertEquals("{\"title\":\"Reading\"}", content.getPayloadJson());
        assertNotNull(content.getUpdatedAt());
    }
}
