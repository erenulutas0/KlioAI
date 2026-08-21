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
        // 320 of answer room plus the 1600-token reasoning allowance callJson adds, because
        // the gpt-oss models spend part of the completion budget thinking before emitting
        // any content at all.
        verify(aiCompletionProvider).chatCompletionWithUsage(messagesCaptor.capture(), eq(true), eq(320 + 1600), eq(0.8),
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

    // ---------------------------------------------------------- generated-content repair

    private static String quizJson(String... optionSets) {
        StringBuilder json = new StringBuilder("{\"topic\":\"past simple\",\"questions\":[");
        for (int i = 0; i < optionSets.length; i++) {
            if (i > 0) {
                json.append(',');
            }
            json.append("{\"question\":\"Q").append(i + 1)
                    .append(" ---- gap.\",\"options\":").append(optionSets[i])
                    .append(",\"correctAnswer\":\"a\",\"targetWord\":\"\"}");
        }
        return json.append("]}").toString();
    }

    @Test
    void grammarQuiz_ShouldDropQuestionsWhoseOptionsAreNotFourDistinctChoices() {
        // Shipped to learners as four identical buttons; the client only checks that the
        // correct answer is among the options, which duplicates satisfy.
        String payload = quizJson(
                "[\"a\",\"b\",\"c\",\"d\"]",
                "[\"a\",\"a\",\"a\",\"a\"]",
                "[\"a\",\"b\",\"c\",\"d\"]",
                "[\"a\",\"b\",\"c\",\"d\"]");
        when(aiCompletionProvider.chatCompletionWithUsage(anyList(), eq(true), any(), any(), nullable(String.class)))
                .thenReturn(AiCompletionProvider.CompletionResult.of(payload, 10, 5, 15));

        AiProxyService.AiJsonResult result = aiProxyService.generateGrammarQuiz(
                "past simple", "B1", LearningLanguageProfile.defaultProfile(), 0, List.of());

        assertEquals(3, ((List<?>) result.json().get("questions")).size());
    }

    @Test
    void grammarQuiz_ShouldRetryRatherThanServeAnEmptyQuiz() {
        // The guard turned a past-simple quiz where every question had duplicate options
        // into an empty one: a learner taps Practice and gets nothing, which is worse than
        // the broken questions it replaced.
        String allBroken = quizJson(
                "[\"read\",\"read\",\"read\",\"read\"]",
                "[\"read\",\"read\",\"read\",\"read\"]",
                "[\"read\",\"read\",\"read\",\"read\"]");
        String good = quizJson(
                "[\"a\",\"b\",\"c\",\"d\"]",
                "[\"a\",\"b\",\"c\",\"d\"]",
                "[\"a\",\"b\",\"c\",\"d\"]");
        when(aiCompletionProvider.chatCompletionWithUsage(anyList(), eq(true), any(), any(), nullable(String.class)))
                .thenReturn(AiCompletionProvider.CompletionResult.of(allBroken, 10, 5, 15))
                .thenReturn(AiCompletionProvider.CompletionResult.of(good, 10, 5, 15));

        AiProxyService.AiJsonResult result = aiProxyService.generateGrammarQuiz(
                "past simple", "B1", LearningLanguageProfile.defaultProfile(), 0, List.of());

        assertEquals(3, ((List<?>) result.json().get("questions")).size());
    }

    @Test
    void grammarQuiz_ShouldNotRetryWhenEnoughQuestionsSurvive() {
        // The retry costs a call. It is for the empty-quiz case, not for every blemish.
        String payload = quizJson(
                "[\"a\",\"b\",\"c\",\"d\"]",
                "[\"a\",\"a\",\"a\",\"a\"]",
                "[\"a\",\"b\",\"c\",\"d\"]",
                "[\"a\",\"b\",\"c\",\"d\"]");
        when(aiCompletionProvider.chatCompletionWithUsage(anyList(), eq(true), any(), any(), nullable(String.class)))
                .thenReturn(AiCompletionProvider.CompletionResult.of(payload, 10, 5, 15));

        aiProxyService.generateGrammarQuiz(
                "past simple", "B1", LearningLanguageProfile.defaultProfile(), 0, List.of());

        verify(aiCompletionProvider, org.mockito.Mockito.times(1))
                .chatCompletionWithUsage(anyList(), eq(true), any(), any(), nullable(String.class));
    }

    @Test
    void readingPassage_ShouldDropAQuoteThatIsNotInThePassage() {
        // The quote is shown as the evidence for the right answer. A paraphrase sends the
        // learner back to hunt for a sentence the passage does not contain.
        String payload = "{\"title\":\"T\",\"text\":\"Buses run on electricity in the city centre.\","
                + "\"questions\":[{\"question\":\"Q1?\",\"options\":[\"a\",\"b\"],\"correctAnswer\":\"A\","
                + "\"correctAnswerQuote\":\"They also help reduce pollution.\"},"
                + "{\"question\":\"Q2?\",\"options\":[\"a\",\"b\"],\"correctAnswer\":\"B\","
                + "\"correctAnswerQuote\":\"Buses run on electricity\"}]}";
        when(aiCompletionProvider.chatCompletionWithUsage(anyList(), eq(true), any(), any(), nullable(String.class)))
                .thenReturn(AiCompletionProvider.CompletionResult.of(payload, 10, 5, 15));

        AiProxyService.AiJsonResult result = aiProxyService.generateReadingPassage(
                "B1", LearningLanguageProfile.defaultProfile(), 200, 0);

        List<?> questions = (List<?>) result.json().get("questions");
        assertFalse(((Map<?, ?>) questions.get(0)).containsKey("correctAnswerQuote"));
        // The question survives; only the unverifiable claim goes.
        assertEquals("Q1?", ((Map<?, ?>) questions.get(0)).get("question"));
        // A quote that really is in the passage is left alone.
        assertEquals("Buses run on electricity", ((Map<?, ?>) questions.get(1)).get("correctAnswerQuote"));
    }

    @Test
    void grammarQuiz_ShouldClearATargetWordTheQuestionDoesNotUse() {
        // The eval caught "mitigate" attached to a question whose answer was "included".
        // A targetWord is what lets an answer reach the review scheduler, so a false one
        // credits the learner's saved word for a question that tested a different one.
        String payload = "{\"topic\":\"present perfect\",\"questions\":["
                + "{\"question\":\"The project has ---- many changes.\","
                + "\"options\":[\"included\",\"include\",\"includes\",\"including\"],"
                + "\"correctAnswer\":\"included\",\"targetWord\":\"mitigate\"},"
                + "{\"question\":\"They have ---- the risk.\","
                + "\"options\":[\"mitigated\",\"mitigate\",\"mitigates\",\"mitigating\"],"
                + "\"correctAnswer\":\"mitigated\",\"targetWord\":\"mitigate\"},"
                + "{\"question\":\"She has ---- it.\",\"options\":[\"a\",\"b\",\"c\",\"d\"],"
                + "\"correctAnswer\":\"a\",\"targetWord\":\"\"}]}";
        when(aiCompletionProvider.chatCompletionWithUsage(anyList(), eq(true), any(), any(), nullable(String.class)))
                .thenReturn(AiCompletionProvider.CompletionResult.of(payload, 10, 5, 15));

        AiProxyService.AiJsonResult result = aiProxyService.generateGrammarQuiz(
                "present perfect", "B1", LearningLanguageProfile.defaultProfile(), 0, List.of("mitigate"));

        List<?> questions = (List<?>) result.json().get("questions");
        // The question survives; only the false label goes.
        assertEquals(3, questions.size());
        assertEquals("", ((Map<?, ?>) questions.get(0)).get("targetWord"));
        // The word really is in the answer here, so the credit is genuine and stays.
        assertEquals("mitigate", ((Map<?, ?>) questions.get(1)).get("targetWord"));
    }

    @Test
    void grammarQuiz_ShouldDropAQuestionWhoseAnswerIsNotOffered() {
        // The learner cannot pick what is not there. The quiz screen already discards these;
        // doing it here means the retry can compensate instead of the quiz quietly shrinking
        // on the device.
        String payload = "{\"topic\":\"past simple\",\"questions\":["
                + "{\"question\":\"Q1 ---- gap.\",\"options\":[\"insights\",\"insighted\",\"insight\",\"insightfully\"],"
                + "\"correctAnswer\":\"insightful\",\"targetWord\":\"\"},"
                + "{\"question\":\"Q2 ---- gap.\",\"options\":[\"a\",\"b\",\"c\",\"d\"],"
                + "\"correctAnswer\":\"a\",\"targetWord\":\"\"},"
                + "{\"question\":\"Q3 ---- gap.\",\"options\":[\"a\",\"b\",\"c\",\"d\"],"
                + "\"correctAnswer\":\"b\",\"targetWord\":\"\"},"
                + "{\"question\":\"Q4 ---- gap.\",\"options\":[\"a\",\"b\",\"c\",\"d\"],"
                + "\"correctAnswer\":\"c\",\"targetWord\":\"\"}]}";
        when(aiCompletionProvider.chatCompletionWithUsage(anyList(), eq(true), any(), any(), nullable(String.class)))
                .thenReturn(AiCompletionProvider.CompletionResult.of(payload, 10, 5, 15));

        AiProxyService.AiJsonResult result = aiProxyService.generateGrammarQuiz(
                "past simple", "B1", LearningLanguageProfile.defaultProfile(), 0, List.of());

        List<?> questions = (List<?>) result.json().get("questions");
        assertEquals(3, questions.size());
        assertEquals("Q2 ---- gap.", ((Map<?, ?>) questions.get(0)).get("question"));
    }

    @Test
    void grammarQuiz_ShouldAbandonTheVocabularyRatherThanServeNothing() {
        // A past-simple drill built on "insight" and "resilient" has to invent a verb, and
        // every question it produces is unanswerable. Twice in a row the eval got an empty
        // quiz. Giving up the vocabulary integration keeps the lesson; an empty practice
        // screen teaches nothing at all.
        String unusable = quizJson("[\"insighted\",\"insighted\",\"insighted\",\"insighted\"]");
        String plain = quizJson(
                "[\"a\",\"b\",\"c\",\"d\"]",
                "[\"a\",\"b\",\"c\",\"d\"]",
                "[\"a\",\"b\",\"c\",\"d\"]");
        when(aiCompletionProvider.chatCompletionWithUsage(anyList(), eq(true), any(), any(), nullable(String.class)))
                .thenReturn(AiCompletionProvider.CompletionResult.of(unusable, 10, 5, 15))
                .thenReturn(AiCompletionProvider.CompletionResult.of(unusable, 10, 5, 15))
                .thenReturn(AiCompletionProvider.CompletionResult.of(plain, 10, 5, 15));

        AiProxyService.AiJsonResult result = aiProxyService.generateGrammarQuiz(
                "past simple", "B1", LearningLanguageProfile.defaultProfile(), 0,
                List.of("insight", "resilient"));

        assertEquals(3, ((List<?>) result.json().get("questions")).size());
    }
}
