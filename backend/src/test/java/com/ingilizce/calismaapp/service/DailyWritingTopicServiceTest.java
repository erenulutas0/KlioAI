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
import java.util.Map;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class DailyWritingTopicServiceTest {

    @Mock
    private DailyContentRepository dailyContentRepository;

    @Mock
    private AiProxyService aiProxyService;

    private DailyWritingTopicService service;
    private LocalDate date;

    @BeforeEach
    void setUp() {
        service = new DailyWritingTopicService(dailyContentRepository, aiProxyService, new ObjectMapper());
        date = LocalDate.of(2026, 7, 5);
    }

    @Test
    void getDailyWritingTopic_shouldReturnCachedPayloadWithoutRegeneration() {
        String payloadJson = """
                {
                  "topic": "Cached topic",
                  "description": "Use two examples.",
                  "cefrLevel": "B2"
                }
                """;
        when(dailyContentRepository.findByContentDateAndContentType(date, "daily_writing_v1_b2"))
                .thenReturn(Optional.of(new DailyContent(date, "daily_writing_v1_b2", payloadJson)));

        Map<String, Object> result = service.getDailyWritingTopic(date, " b2 ");

        assertEquals("Cached topic", result.get("topic"));
        assertEquals("B2", result.get("cefrLevel"));
        assertEquals("120-170", result.get("wordCount"));
        verify(aiProxyService, never()).generateWritingTopic(any(), any(), anyInt());
        verify(dailyContentRepository, never()).save(any());
    }

    @Test
    void getDailyWritingTopic_shouldPersistGeneratedPayloadWithDailyMetadata() {
        when(dailyContentRepository.findByContentDateAndContentType(date, "daily_writing_v1_c1"))
                .thenReturn(Optional.empty());
        when(aiProxyService.generateWritingTopic("C1", "160-220", date.getDayOfYear()))
                .thenReturn(new AiProxyService.AiJsonResult(generatedWritingPayload(), 90, 60, 30));
        when(dailyContentRepository.save(any(DailyContent.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        Map<String, Object> result = service.getDailyWritingTopic(date, "c1");

        assertEquals("A city bans private cars downtown. Argue for or against the policy.", result.get("topic"));
        assertEquals(Boolean.TRUE, result.get("daily"));
        assertEquals("C1", result.get("cefrLevel"));
        assertEquals("160-220", result.get("wordCount"));
        assertEquals(date.toString(), result.get("dateUtc"));
        assertEquals("daily_writing_v1_c1", result.get("contentType"));
        assertFalse(result.containsKey("fallback"));

        ArgumentCaptor<DailyContent> captor = ArgumentCaptor.forClass(DailyContent.class);
        verify(dailyContentRepository).save(captor.capture());
        assertEquals("daily_writing_v1_c1", captor.getValue().getContentType());
        assertTrue(captor.getValue().getPayloadJson().contains("\"daily\":true"));
    }

    @Test
    void getDailyWritingTopic_shouldFallbackWhenGeneratedPayloadIsIncomplete() {
        when(dailyContentRepository.findByContentDateAndContentType(date, "daily_writing_v1_a2"))
                .thenReturn(Optional.empty());
        when(aiProxyService.generateWritingTopic("A2", "60-90", date.getDayOfYear()))
                .thenReturn(new AiProxyService.AiJsonResult(Map.of("topic", ""), 20, 10, 10));

        Map<String, Object> result = service.getDailyWritingTopic(date, "A2");

        assertEquals(Boolean.TRUE, result.get("fallback"));
        assertEquals("A2", result.get("cefrLevel"));
        assertEquals("60-90", result.get("wordCount"));
        assertEquals("daily_writing_v1_a2", result.get("contentType"));
        assertTrue(((String) result.get("topic")).contains("memorable trip"));
        verify(dailyContentRepository).save(any(DailyContent.class));
    }

    @Test
    void getDailyWritingTopic_shouldFallbackWhenProviderThrowsAndStillReturnContent() {
        when(dailyContentRepository.findByContentDateAndContentType(date, "daily_writing_v1_c2"))
                .thenReturn(Optional.empty());
        when(aiProxyService.generateWritingTopic("C2", "200-260", date.getDayOfYear()))
                .thenThrow(new RuntimeException("provider unavailable"));

        Map<String, Object> result = service.getDailyWritingTopic(date, "C2");

        assertEquals(Boolean.TRUE, result.get("fallback"));
        assertEquals("C2", result.get("cefrLevel"));
        assertTrue(((String) result.get("topic")).contains("technological progress"));
        verify(dailyContentRepository).save(any(DailyContent.class));
    }

    @Test
    void getDailyWritingTopic_shouldUseDefaultDateAndLevelWhenInputsAreMissing() {
        LocalDate today = LocalDate.now();
        when(dailyContentRepository.findByContentDateAndContentType(eq(today), eq("daily_writing_v1_b1")))
                .thenReturn(Optional.empty());
        when(aiProxyService.generateWritingTopic("B1", "90-130", today.getDayOfYear()))
                .thenThrow(new RuntimeException("force fallback"));

        Map<String, Object> result = service.getDailyWritingTopic(null, "unknown");

        assertEquals(Boolean.TRUE, result.get("fallback"));
        assertEquals("B1", result.get("cefrLevel"));
        assertEquals(today.toString(), result.get("dateUtc"));
    }

    @Test
    void getDailyWritingTopic_shouldIgnoreConcurrentInsertFailureAndReturnGeneratedPayload() {
        when(dailyContentRepository.findByContentDateAndContentType(date, "daily_writing_v1_b1"))
                .thenReturn(Optional.empty());
        when(aiProxyService.generateWritingTopic("B1", "90-130", date.getDayOfYear()))
                .thenReturn(new AiProxyService.AiJsonResult(generatedWritingPayload(), 90, 60, 30));
        when(dailyContentRepository.save(any(DailyContent.class)))
                .thenThrow(new DataIntegrityViolationException("duplicate"));

        Map<String, Object> result = service.getDailyWritingTopic(date, "B1");

        assertEquals("A city bans private cars downtown. Argue for or against the policy.", result.get("topic"));
        assertEquals("B1", result.get("cefrLevel"));
    }

    @Test
    void getDailyWritingTopic_shouldNormalizeMalformedCachedJsonToFallback() {
        when(dailyContentRepository.findByContentDateAndContentType(date, "daily_writing_v1_b1"))
                .thenReturn(Optional.of(new DailyContent(date, "daily_writing_v1_b1", "{broken")));

        Map<String, Object> result = service.getDailyWritingTopic(date, "B1");

        assertEquals(Boolean.TRUE, result.get("fallback"));
        assertEquals("B1", result.get("cefrLevel"));
        assertTrue(((String) result.get("topic")).contains("learning something new"));
        verify(aiProxyService, never()).generateWritingTopic(any(), any(), anyInt());
    }

    private Map<String, Object> generatedWritingPayload() {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("topic", "A city bans private cars downtown. Argue for or against the policy.");
        payload.put("description", "Explain your position with practical examples and a clear conclusion.");
        payload.put("suggestedStructure", "Introduction, two body paragraphs, conclusion");
        payload.put("grammarFocus", "argument clauses");
        return payload;
    }
}
