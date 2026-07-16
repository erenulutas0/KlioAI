package com.ingilizce.calismaapp.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

class GroqAiCompletionProviderTest {

    @Test
    void chatCompletionWithUsageShouldMapGroqUsageAndRecordSuccess() {
        GroqService groqService = mock(GroqService.class);
        AiProviderMetricsService metricsService = mock(AiProviderMetricsService.class);
        List<Map<String, String>> messages = List.of(Map.of("role", "user", "content", "hello"));
        when(groqService.chatCompletionWithUsage(messages, true, 128, 0.3, "llama-test"))
                .thenReturn(new GroqService.ChatCompletionResult("answer", 10, 20, 30));

        GroqAiCompletionProvider provider = new GroqAiCompletionProvider(groqService, metricsService);
        AiCompletionProvider.CompletionResult result = provider.chatCompletionWithUsage(
                messages,
                true,
                128,
                0.3,
                "llama-test");

        assertEquals("answer", result.content());
        assertEquals(10, result.promptTokens());
        assertEquals(20, result.completionTokens());
        assertEquals(30, result.totalTokens());
        verify(metricsService).recordSuccess("groq", "llama-test", result);
    }

    @Test
    void chatCompletionWithUsageShouldReturnEmptyResultWhenGroqReturnsNull() {
        GroqService groqService = mock(GroqService.class);
        AiProviderMetricsService metricsService = mock(AiProviderMetricsService.class);
        when(groqService.chatCompletionWithUsage(any(), eq(false), eq(null), eq(null), eq(null)))
                .thenReturn(null);

        GroqAiCompletionProvider provider = new GroqAiCompletionProvider(groqService, metricsService);
        AiCompletionProvider.CompletionResult result = provider.chatCompletionWithUsage(
                List.of(Map.of("role", "user", "content", "hello")),
                false,
                null,
                null,
                null);

        assertNull(result.content());
        assertEquals(0, result.totalTokens());
        verify(metricsService).recordSuccess("groq", null, result);
    }

    @Test
    void chatCompletionWithUsageShouldRecordErrorAndRethrow() {
        GroqService groqService = mock(GroqService.class);
        AiProviderMetricsService metricsService = mock(AiProviderMetricsService.class);
        RuntimeException failure = new RuntimeException("provider down");
        when(groqService.chatCompletionWithUsage(any(), eq(false), eq(64), eq(0.7), eq("model-a")))
                .thenThrow(failure);

        GroqAiCompletionProvider provider = new GroqAiCompletionProvider(groqService, metricsService);
        RuntimeException thrown = assertThrows(
                RuntimeException.class,
                () -> provider.chatCompletionWithUsage(
                        List.of(Map.of("role", "user", "content", "hello")),
                        false,
                        64,
                        0.7,
                        "model-a"));

        assertEquals(failure, thrown);
        verify(metricsService).recordError("groq", "model-a");
    }

    @Test
    void chatCompletionDefaultMethodShouldReturnOnlyContent() {
        GroqService groqService = mock(GroqService.class);
        when(groqService.chatCompletionWithUsage(any(), eq(false), eq(null), eq(null), eq("model-b")))
                .thenReturn(new GroqService.ChatCompletionResult("plain answer", 1, 2, 3));

        GroqAiCompletionProvider provider = new GroqAiCompletionProvider(groqService, null);

        assertEquals("plain answer", provider.chatCompletion(
                List.of(Map.of("role", "user", "content", "hello")),
                false,
                "model-b"));
    }
}
