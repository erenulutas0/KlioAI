package com.ingilizce.calismaapp.service;

import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

class AiCompletionProviderTest {

    @Test
    void completionResultFactoriesShouldPreserveUsageFields() {
        AiCompletionProvider.CompletionResult result =
                AiCompletionProvider.CompletionResult.of("hello", 3, 4, 7);

        assertEquals("hello", result.content());
        assertEquals(3, result.promptTokens());
        assertEquals(4, result.completionTokens());
        assertEquals(7, result.totalTokens());

        AiCompletionProvider.CompletionResult empty = AiCompletionProvider.CompletionResult.empty();
        assertNull(empty.content());
        assertEquals(0, empty.totalTokens());
    }

    @Test
    void defaultChatCompletionShouldReturnContentOrNull() {
        AiCompletionProvider provider = new AiCompletionProvider() {
            @Override
            public CompletionResult chatCompletionWithUsage(List<Map<String, String>> messages,
                                                            boolean jsonResponse,
                                                            Integer maxTokens,
                                                            Double temperature,
                                                            String modelOverride) {
                assertEquals("groq-model", modelOverride);
                assertNull(maxTokens);
                assertNull(temperature);
                return CompletionResult.of(messages.get(0).get("content"), 1, 2, 3);
            }
        };

        String content = provider.chatCompletion(List.of(Map.of("content", "ping")), false, "groq-model");

        assertEquals("ping", content);
    }

    @Test
    void defaultChatCompletionShouldHandleNullUsageResult() {
        AiCompletionProvider provider = new AiCompletionProvider() {
            @Override
            public CompletionResult chatCompletionWithUsage(List<Map<String, String>> messages,
                                                            boolean jsonResponse,
                                                            Integer maxTokens,
                                                            Double temperature,
                                                            String modelOverride) {
                return null;
            }
        };

        assertNull(provider.chatCompletion(List.of(), true, null));
    }
}
