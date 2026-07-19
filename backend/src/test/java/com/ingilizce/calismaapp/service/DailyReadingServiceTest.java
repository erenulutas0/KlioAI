package com.ingilizce.calismaapp.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ingilizce.calismaapp.entity.DailyContent;
import com.ingilizce.calismaapp.repository.DailyContentRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.dao.DataIntegrityViolationException;

import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertInstanceOf;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class DailyReadingServiceTest {

    @Mock
    private DailyContentRepository dailyContentRepository;

    @Mock
    private AiProxyService aiProxyService;

    private DailyReadingService service;
    private LocalDate date;

    @BeforeEach
    void setUp() {
        service = new DailyReadingService(dailyContentRepository, aiProxyService, new ObjectMapper());
        date = LocalDate.of(2026, 7, 5);
    }

    @Test
    void getDailyReading_shouldReturnCachedPayloadWithoutRegeneration() {
        String payloadJson = """
                {
                  "title": "Cached Reading",
                  "text": "A cached passage is already available.",
                  "questions": [
                    {"question":"What is available?","options":["A","B","C","D"],"correctAnswer":"A"}
                  ],
                  "cefrLevel": "B2"
                }
                """;
        when(dailyContentRepository.findByContentDateAndContentType(date, "daily_reading_v2_b2"))
                .thenReturn(Optional.of(new DailyContent(date, "daily_reading_v2_b2", payloadJson)));

        Map<String, Object> result = service.getDailyReading(date, " b2 ");

        assertEquals("Cached Reading", result.get("title"));
        assertEquals("B2", result.get("cefrLevel"));
        verify(aiProxyService, never()).generateReadingPassage(any(), any(), org.mockito.ArgumentMatchers.anyInt(), org.mockito.ArgumentMatchers.anyInt());
        verify(dailyContentRepository, never()).save(any());
    }

    @Test
    void getDailyReading_shouldPersistGeneratedPayloadWithDailyMetadata() {
        when(dailyContentRepository.findByContentDateAndContentType(date, "daily_reading_v2_c1"))
                .thenReturn(Optional.empty());
        when(aiProxyService.generateReadingPassage(org.mockito.ArgumentMatchers.eq("C1"), any(), org.mockito.ArgumentMatchers.anyInt(), org.mockito.ArgumentMatchers.anyInt()))
                .thenReturn(new AiProxyService.AiJsonResult(generatedReadingPayload(), 120, 80, 40));
        when(dailyContentRepository.save(any(DailyContent.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        Map<String, Object> result = service.getDailyReading(date, "c1");

        assertEquals("A Clear Decision", result.get("title"));
        assertEquals(Boolean.TRUE, result.get("daily"));
        assertEquals("C1", result.get("cefrLevel"));
        assertEquals(date.toString(), result.get("dateUtc"));
        assertEquals("daily_reading_v2_c1", result.get("contentType"));
        assertFalse(result.containsKey("fallback"));

        ArgumentCaptor<DailyContent> captor = ArgumentCaptor.forClass(DailyContent.class);
        verify(dailyContentRepository).save(captor.capture());
        assertEquals("daily_reading_v2_c1", captor.getValue().getContentType());
        assertTrue(captor.getValue().getPayloadJson().contains("\"daily\":true"));
    }

    @Test
    void getDailyReading_shouldFallbackWhenGeneratedPayloadIsIncomplete() {
        when(dailyContentRepository.findByContentDateAndContentType(date, "daily_reading_v2_a1"))
                .thenReturn(Optional.empty());
        when(aiProxyService.generateReadingPassage(org.mockito.ArgumentMatchers.eq("A1"), any(), org.mockito.ArgumentMatchers.anyInt(), org.mockito.ArgumentMatchers.anyInt()))
                .thenReturn(new AiProxyService.AiJsonResult(Map.of("title", "Broken"), 20, 10, 10));

        Map<String, Object> result = service.getDailyReading(date, "A1");

        assertEquals(Boolean.TRUE, result.get("fallback"));
        assertEquals("A1", result.get("cefrLevel"));
        assertEquals("daily_reading_v2_a1", result.get("contentType"));
        assertTrue(((String) result.get("text")).contains("Tom wakes up"));
        assertEquals(3, assertInstanceOf(List.class, result.get("questions")).size());
        verify(dailyContentRepository).save(any(DailyContent.class));
    }

    @Test
    void getDailyReading_shouldFallbackWhenProviderThrowsAndStillReturnContent() {
        when(dailyContentRepository.findByContentDateAndContentType(date, "daily_reading_v2_c2"))
                .thenReturn(Optional.empty());
        when(aiProxyService.generateReadingPassage(org.mockito.ArgumentMatchers.eq("C2"), any(), org.mockito.ArgumentMatchers.anyInt(), org.mockito.ArgumentMatchers.anyInt()))
                .thenThrow(new RuntimeException("provider unavailable"));

        Map<String, Object> result = service.getDailyReading(date, "C2");

        assertEquals(Boolean.TRUE, result.get("fallback"));
        assertEquals("C2", result.get("cefrLevel"));
        assertTrue(((String) result.get("text")).contains("Contemporary innovation policy"));
        verify(dailyContentRepository).save(any(DailyContent.class));
    }

    @Test
    void getDailyReading_shouldUseDefaultDateAndLevelWhenInputsAreMissing() {
        LocalDate today = LocalDate.now();
        when(dailyContentRepository.findByContentDateAndContentType(eq(today), eq("daily_reading_v2_b1")))
                .thenReturn(Optional.empty());
        when(aiProxyService.generateReadingPassage(org.mockito.ArgumentMatchers.eq("B1"), any(), org.mockito.ArgumentMatchers.anyInt(), org.mockito.ArgumentMatchers.anyInt()))
                .thenThrow(new RuntimeException("force fallback"));

        Map<String, Object> result = service.getDailyReading(null, "unknown");

        assertEquals(Boolean.TRUE, result.get("fallback"));
        assertEquals("B1", result.get("cefrLevel"));
        assertEquals(today.toString(), result.get("dateUtc"));
    }

    @Test
    void getDailyReading_shouldIgnoreConcurrentInsertFailureAndReturnGeneratedPayload() {
        when(dailyContentRepository.findByContentDateAndContentType(date, "daily_reading_v2_b1"))
                .thenReturn(Optional.empty());
        when(aiProxyService.generateReadingPassage(org.mockito.ArgumentMatchers.eq("B1"), any(), org.mockito.ArgumentMatchers.anyInt(), org.mockito.ArgumentMatchers.anyInt()))
                .thenReturn(new AiProxyService.AiJsonResult(generatedReadingPayload(), 120, 80, 40));
        when(dailyContentRepository.save(any(DailyContent.class)))
                .thenThrow(new DataIntegrityViolationException("duplicate"));

        Map<String, Object> result = service.getDailyReading(date, "B1");

        assertEquals("A Clear Decision", result.get("title"));
        assertEquals("B1", result.get("cefrLevel"));
    }

    @Test
    void getDailyReading_shouldReturnEmptyMapForMalformedCachedJson() {
        when(dailyContentRepository.findByContentDateAndContentType(date, "daily_reading_v2_b1"))
                .thenReturn(Optional.of(new DailyContent(date, "daily_reading_v2_b1", "{broken")));

        Map<String, Object> result = service.getDailyReading(date, "B1");

        assertTrue(result.isEmpty());
        verify(aiProxyService, never()).generateReadingPassage(any(), any(), org.mockito.ArgumentMatchers.anyInt(), org.mockito.ArgumentMatchers.anyInt());
    }

    private Map<String, Object> generatedReadingPayload() {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("title", "A Clear Decision");
        payload.put("text", "The committee explained its decision clearly, so people trusted the process.");
        payload.put("questions", List.of(
                Map.of(
                        "question", "Why did people trust the process?",
                        "options", List.of("A", "B", "C", "D"),
                        "correctAnswer", "A",
                        "explanation", "The decision was explained clearly."
                )
        ));
        return payload;
    }
}
