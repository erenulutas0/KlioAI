package com.ingilizce.calismaapp.service;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.nullable;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class AiProxyServiceTest {

    @Mock
    private AiCompletionProvider aiCompletionProvider;

    @Mock
    private AiModelRoutingService aiModelRoutingService;

    private AiProxyService aiProxyService;

    @BeforeEach
    void setUp() {
        aiProxyService = new AiProxyService(aiCompletionProvider);
    }

    @Test
    void dictionaryLookupDetailed_ShouldReturnFallbackPayload_WhenAiContentIsBlank() {
        when(aiCompletionProvider.chatCompletionWithUsage(anyList(), eq(true), any(), any(), nullable(String.class)))
                .thenReturn(AiCompletionProvider.CompletionResult.of("   ", 11, 5, 16));

        AiProxyService.AiJsonResult result = aiProxyService.dictionaryLookupDetailed("bring about");

        assertTrue((Boolean) result.json().get("fallback"));
        assertEquals("bring about", result.json().get("word"));
        assertTrue(result.json().containsKey("meanings"));
        assertEquals(16, result.totalTokens());
    }

    @Test
    void generateReadingPassage_ShouldReturnFallbackPayload_WhenAiContentIsNotJson() {
        when(aiCompletionProvider.chatCompletionWithUsage(anyList(), eq(true), any(), any(), nullable(String.class)))
                .thenReturn(AiCompletionProvider.CompletionResult.of("temporary text output", 7, 3, 10));

        AiProxyService.AiJsonResult result = aiProxyService.generateReadingPassage("Intermediate");

        assertTrue((Boolean) result.json().get("fallback"));
        assertEquals("Daily Reading Practice", result.json().get("title"));
        assertTrue(result.json().containsKey("questions"));
        assertTrue(result.json().get("questions") instanceof List<?>);
        assertFalse(((String) result.json().get("text")).isBlank());
    }

    @Test
    void generateReadingPassage_ShouldReturnFallbackPayload_WhenJsonSchemaIsInvalid() {
        when(aiCompletionProvider.chatCompletionWithUsage(anyList(), eq(true), any(), any(), nullable(String.class)))
                .thenReturn(AiCompletionProvider.CompletionResult.of("{\"message\":\"ok\"}", 7, 3, 10));

        AiProxyService.AiJsonResult result = aiProxyService.generateReadingPassage("Intermediate");

        assertTrue((Boolean) result.json().get("fallback"));
        assertEquals("Daily Reading Practice", result.json().get("title"));
        assertTrue(result.json().get("questions") instanceof List<?>);
    }

    @Test
    void dictionaryLookup_ShouldUseRescueModel_WhenPrimaryJsonParseFails() {
        ReflectionTestUtils.setField(aiProxyService, "aiModelRoutingService", aiModelRoutingService);
        when(aiModelRoutingService.resolveModelForScope("dictionary-lookup")).thenReturn("openai/gpt-oss-20b");
        when(aiModelRoutingService.defaultModel()).thenReturn("llama-3.3-70b-versatile");

        when(aiCompletionProvider.chatCompletionWithUsage(anyList(), eq(true), any(), any(), eq("openai/gpt-oss-20b")))
                .thenReturn(AiCompletionProvider.CompletionResult.of("   ", 11, 4, 15));

        String rescueJson = """
                {
                  "word":"focus",
                  "type":"noun",
                  "meanings":[
                    {"translation":"odak","context":"general","example":"Keep your focus."}
                  ]
                }
                """;
        when(aiCompletionProvider.chatCompletionWithUsage(anyList(), eq(false), any(), any(), eq("llama-3.3-70b-versatile")))
                .thenReturn(AiCompletionProvider.CompletionResult.of(rescueJson, 8, 3, 11));

        AiProxyService.AiJsonResult result = aiProxyService.dictionaryLookup("focus");

        assertNotNull(result.json());
        assertEquals("focus", result.json().get("word"));
        assertFalse(result.json().containsKey("fallback"));
        assertEquals(26, result.totalTokens());
    }

    @Test
    void evaluateWriting_ShouldUseProvidedLanguageProfile() {
        when(aiCompletionProvider.chatCompletionWithUsage(anyList(), eq(true), any(), any(), nullable(String.class)))
                .thenReturn(AiCompletionProvider.CompletionResult.of("""
                        {
                          "score": 80,
                          "strengths": [],
                          "improvements": [],
                          "grammar": "ok",
                          "vocabulary": "ok",
                          "coherence": "ok",
                          "overall": "ok",
                          "contextRelevance": "ok"
                        }
                        """, 7, 3, 10));

        aiProxyService.evaluateWriting(
                "This is my essay.",
                "B2",
                Map.of("topic", "Technology", "description", "AI in daily life"),
                LearningLanguageProfile.of("Turkish", "English", "English"));

        ArgumentCaptor<List<Map<String, String>>> messagesCaptor = ArgumentCaptor.forClass(List.class);
        verify(aiCompletionProvider).chatCompletionWithUsage(messagesCaptor.capture(), eq(true), any(), any(),
                nullable(String.class));
        String prompt = messagesCaptor.getValue().get(1).get("content");
        assertTrue(prompt.contains("Source/native language: Turkish"));
        assertTrue(prompt.contains("Target/practice language: English"));
        assertTrue(prompt.contains("Return learner-facing feedback in English"));
    }
}
