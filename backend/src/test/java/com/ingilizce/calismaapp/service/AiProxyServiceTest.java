package com.ingilizce.calismaapp.service;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Arrays;
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
        Map<?, ?> firstMeaning = (Map<?, ?>) ((List<?>) result.json().get("meanings")).get(0);
        assertEquals(firstMeaning.get("turkishMeaning"), firstMeaning.get("sourceMeaning"));
        assertEquals(16, result.totalTokens());
    }

    @Test
    void dictionaryLookupDetailed_ShouldAddSourceMeaningAlias_WhenModelReturnsLegacyTurkishMeaning() {
        when(aiCompletionProvider.chatCompletionWithUsage(anyList(), eq(true), any(), any(), nullable(String.class)))
                .thenReturn(AiCompletionProvider.CompletionResult.of("""
                        {
                          "word": "bring about",
                          "phonetic": "/brɪŋ əˈbaʊt/",
                          "meanings": [
                            {
                              "type": "phr",
                              "turkishMeaning": "neden olmak",
                              "englishDefinition": "to cause something",
                              "example": "The plan brought about change.",
                              "exampleTranslation": "Plan değişime neden oldu."
                            }
                          ]
                        }
                        """, 20, 12, 32));

        AiProxyService.AiJsonResult result = aiProxyService.dictionaryLookupDetailed("bring about");

        Map<?, ?> firstMeaning = (Map<?, ?>) ((List<?>) result.json().get("meanings")).get(0);
        assertEquals("neden olmak", firstMeaning.get("sourceMeaning"));
        assertEquals("neden olmak", firstMeaning.get("turkishMeaning"));
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

    @Test
    void generatePronunciationTexts_ShouldSanitizeFocusWordsAndUseLevelRule() {
        when(aiCompletionProvider.chatCompletionWithUsage(anyList(), eq(true), any(), any(), nullable(String.class)))
                .thenReturn(AiCompletionProvider.CompletionResult.of("""
                        {
                          "texts": [
                            "The delayed train finally arrived at the station.",
                            "A calm voice helped everyone focus on the plan.",
                            "The speaker gave a clear example during the meeting."
                          ],
                          "focusWords": ["delayed", "focus"],
                          "level": "B2"
                        }
                        """, 9, 4, 13));

        AiProxyService.AiJsonResult result = aiProxyService.generatePronunciationTexts(
                "upper_intermediate",
                Arrays.asList(" delayed ", "focus", "focus", "", "x".repeat(41), null, "meeting"),
                LearningLanguageProfile.of("Spanish", "English", "Spanish"));

        assertEquals("B2", result.json().get("level"));
        assertTrue(result.json().get("texts") instanceof List<?>);

        ArgumentCaptor<List<Map<String, String>>> messagesCaptor = ArgumentCaptor.forClass(List.class);
        verify(aiCompletionProvider).chatCompletionWithUsage(messagesCaptor.capture(), eq(true), eq(320), eq(0.8),
                nullable(String.class));
        String prompt = messagesCaptor.getValue().get(1).get("content");
        assertTrue(prompt.contains("Source/native language: Spanish"));
        assertTrue(prompt.contains("LEVEL: B2"));
        assertTrue(prompt.contains("14-22 words"));
        assertTrue(prompt.contains("FOCUS WORDS: delayed, focus, meeting"));
    }

    @Test
    void generatePronunciationTexts_ShouldFallbackWhenSchemaIsInvalid() {
        when(aiCompletionProvider.chatCompletionWithUsage(anyList(), eq(true), any(), any(), nullable(String.class)))
                .thenReturn(AiCompletionProvider.CompletionResult.of("{\"message\":\"ok\"}", 4, 2, 6));

        AiProxyService.AiJsonResult result = aiProxyService.generatePronunciationTexts(
                "A1",
                List.of("although"));

        assertTrue((Boolean) result.json().get("fallback"));
        assertEquals("B1", result.json().get("level"));
        assertEquals(List.of("although"), result.json().get("focusWords"));
        assertTrue(result.json().get("texts") instanceof List<?>);
    }

    @Test
    void generateWritingTopic_ShouldInjectRotatingTopicCategory_ByDayOfYear() {
        when(aiCompletionProvider.chatCompletionWithUsage(anyList(), eq(true), any(), any(), nullable(String.class)))
                .thenReturn(AiCompletionProvider.CompletionResult.of(
                        "{\"topic\":\"t\",\"description\":\"d\",\"level\":\"B1\",\"wordCount\":\"120-160\"}", 5, 2, 7));

        aiProxyService.generateWritingTopic("B1", "120-160", LearningLanguageProfile.defaultProfile(), 1);

        ArgumentCaptor<List<Map<String, String>>> messagesCaptor = ArgumentCaptor.forClass(List.class);
        verify(aiCompletionProvider).chatCompletionWithUsage(messagesCaptor.capture(), eq(true), any(), any(),
                nullable(String.class));
        String prompt = messagesCaptor.getValue().get(1).get("content");
        assertTrue(prompt.contains("TOPIC CATEGORY FOR TODAY: " + PromptCatalog.topicForDay(1)));
    }

    @Test
    void generateWritingTopic_ShouldVaryTopicCategory_AcrossDifferentDays() {
        when(aiCompletionProvider.chatCompletionWithUsage(anyList(), eq(true), any(), any(), nullable(String.class)))
                .thenReturn(AiCompletionProvider.CompletionResult.of(
                        "{\"topic\":\"t\",\"description\":\"d\",\"level\":\"B1\",\"wordCount\":\"120-160\"}", 5, 2, 7));

        aiProxyService.generateWritingTopic("B1", "120-160", 1);
        aiProxyService.generateWritingTopic("B1", "120-160", 2);

        ArgumentCaptor<List<Map<String, String>>> messagesCaptor = ArgumentCaptor.forClass(List.class);
        verify(aiCompletionProvider, org.mockito.Mockito.times(2)).chatCompletionWithUsage(
                messagesCaptor.capture(), eq(true), any(), any(), nullable(String.class));
        String firstPrompt = messagesCaptor.getAllValues().get(0).get(1).get("content");
        String secondPrompt = messagesCaptor.getAllValues().get(1).get(1).get("content");
        assertTrue(firstPrompt.contains("TOPIC CATEGORY FOR TODAY: " + PromptCatalog.topicForDay(1)));
        assertTrue(secondPrompt.contains("TOPIC CATEGORY FOR TODAY: " + PromptCatalog.topicForDay(2)));
        assertTrue(!firstPrompt.equals(secondPrompt));
    }

    @Test
    void generateWritingTopic_ShouldFallbackWhenSchemaIsInvalid() {
        when(aiCompletionProvider.chatCompletionWithUsage(anyList(), eq(true), any(), any(), nullable(String.class)))
                .thenReturn(AiCompletionProvider.CompletionResult.of("{\"topic\":\"Only title\"}", 5, 2, 7));

        AiProxyService.AiJsonResult result = aiProxyService.generateWritingTopic("C1", "200-260");

        assertTrue((Boolean) result.json().get("fallback"));
        assertEquals("A Day I Learned Something New", result.json().get("topic"));
        assertEquals("120-160", result.json().get("wordCount"));
    }

    @Test
    void evaluateWriting_ShouldFallbackWhenSchemaIsInvalid() {
        when(aiCompletionProvider.chatCompletionWithUsage(anyList(), eq(true), any(), any(), nullable(String.class)))
                .thenReturn(AiCompletionProvider.CompletionResult.of("{\"score\":60}", 5, 2, 7));

        AiProxyService.AiJsonResult result = aiProxyService.evaluateWriting("Short text", "B1", null);

        assertTrue((Boolean) result.json().get("fallback"));
        assertEquals(0, result.json().get("score"));
        assertEquals("Lutfen yazinizi tekrar degerlendirin.", result.json().get("overall"));
    }

    @Test
    void generateExamBundle_ShouldApplySafeDefaultsAndFallbackWhenSchemaIsInvalid() {
        when(aiCompletionProvider.chatCompletionWithUsage(anyList(), eq(true), any(), any(), nullable(String.class)))
                .thenReturn(AiCompletionProvider.CompletionResult.of("{\"meta\":{}}", 5, 2, 7));

        AiProxyService.AiJsonResult result = aiProxyService.generateExamBundle(Map.of(
                "questionCount", "not-a-number",
                "category", "  ",
                "examType", "  ",
                "userLevel", "  ",
                "targetScore", "  "));

        assertTrue((Boolean) result.json().get("fallback"));
        Map<?, ?> meta = (Map<?, ?>) result.json().get("meta");
        assertEquals("YDS/YOKDIL", meta.get("exam"));
        assertEquals("grammar", meta.get("category"));

        ArgumentCaptor<List<Map<String, String>>> messagesCaptor = ArgumentCaptor.forClass(List.class);
        verify(aiCompletionProvider).chatCompletionWithUsage(messagesCaptor.capture(), eq(true), eq(4000), eq(0.85),
                nullable(String.class));
        String prompt = messagesCaptor.getValue().get(1).get("content");
        assertTrue(prompt.contains("YDS/YÖKDİL Sınav Simülasyonu (10 Soru)."));
        assertTrue(prompt.contains("SADECE \"grammar\" kategorisinden 10 adet"));
    }

    @Test
    void dictionarySpecificSentenceAndExplain_ShouldReturnFallbacksWhenAiContentIsBlank() {
        when(aiCompletionProvider.chatCompletionWithUsage(anyList(), eq(true), any(), any(), nullable(String.class)))
                .thenReturn(AiCompletionProvider.CompletionResult.of(" ", 1, 1, 2))
                .thenReturn(AiCompletionProvider.CompletionResult.of(" ", 1, 1, 2));

        AiProxyService.AiJsonResult sentence = aiProxyService.dictionaryGenerateSpecificSentence(
                "focus",
                "odak",
                "attention");
        AiProxyService.AiJsonResult explanation = aiProxyService.dictionaryExplainWordInSentence(
                "focus",
                "Please focus on the first example.");

        assertTrue((Boolean) sentence.json().get("fallback"));
        assertEquals("This is a practice sentence with sentence.", sentence.json().get("sentence"));
        assertTrue((Boolean) explanation.json().get("fallback"));
        assertEquals("Anlam gecici olarak olusturulamadi.", explanation.json().get("definition"));
    }
}
