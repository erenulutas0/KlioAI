package com.ingilizce.calismaapp.service;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class ChatbotServiceTest {

    @Mock
    private GroqService groqService;

    private ChatbotService chatbotService;

    @BeforeEach
    void setUp() {
        chatbotService = new ChatbotService(groqService);
    }

    @Test
    void generateSentences_ShouldNormalizeArrayFromCodeFence() {
        when(groqService.chatCompletionWithUsage(anyList(), anyBoolean(), any(), any()))
                .thenReturn(GroqService.ChatCompletionResult.of("```json\n[{\"englishSentence\":\"A\"}]\n```", 10, 20, 30));

        ChatbotService.AiCallResult response = chatbotService.generateSentences("apple");

        assertEquals("[{\"englishSentence\":\"A\"}]", response.content());

        ArgumentCaptor<List<Map<String, String>>> messagesCaptor = ArgumentCaptor.forClass(List.class);
        verify(groqService).chatCompletionWithUsage(messagesCaptor.capture(), eq(false), any(), any());
        List<Map<String, String>> messages = messagesCaptor.getValue();
        assertEquals(2, messages.size());
        assertEquals("system", messages.get(0).get("role"));
        assertEquals("user", messages.get(1).get("role"));
        assertNotNull(messages.get(0).get("content"));
        assertEquals("Target word: 'apple'. Return ONLY pure, minified JSON. No other text.", messages.get(1).get("content"));
    }

    @Test
    void checkEnglishTranslation_ShouldNormalizeJsonObjectFromCodeFence() {
        when(groqService.chatCompletionWithUsage(anyList(), anyBoolean(), any(), any()))
                .thenReturn(GroqService.ChatCompletionResult.of("```json\n{\"isCorrect\":true}\n```", 1, 2, 3));

        ChatbotService.AiCallResult response = chatbotService.checkEnglishTranslation("Merhaba");

        assertEquals("{\"isCorrect\":true}", response.content());
        verify(groqService).chatCompletionWithUsage(anyList(), eq(true), any(), any());
    }

    @Test
    void chat_ShouldUseTextModeAndReturnRaw() {
        when(groqService.chatCompletionWithUsage(anyList(), anyBoolean(), any(), any()))
                .thenReturn(GroqService.ChatCompletionResult.of("Hello human", 1, 1, 2));

        ChatbotService.AiCallResult response = chatbotService.chat("hi");

        assertEquals("Hello human", response.content());
        verify(groqService).chatCompletionWithUsage(anyList(), eq(false), any(), any());
    }

    @Test
    void generateSentences_ShouldAcceptObjectWithSentencesList_WhenOutputIsArray() {
        String raw = "{\"sentences\":[{\"englishSentence\":\"A\"}]}";
        when(groqService.chatCompletionWithUsage(anyList(), anyBoolean(), any(), any()))
                .thenReturn(GroqService.ChatCompletionResult.of(raw, 1, 1, 2));

        ChatbotService.AiCallResult response = chatbotService.generateSentences("apple");

        assertEquals(raw, response.content());
    }

    @Test
    void generateSentences_ShouldReturnRaw_WhenArrayValidationFails() {
        String raw = "{\"foo\":1}";
        when(groqService.chatCompletionWithUsage(anyList(), anyBoolean(), any(), any()))
                .thenReturn(GroqService.ChatCompletionResult.of(raw, 1, 1, 2));

        ChatbotService.AiCallResult response = chatbotService.generateSentences("apple");

        assertEquals(raw, response.content());
    }

    @Test
    void generateSpeakingTestQuestions_ShouldReturnRaw_WhenObjectValidationFails() {
        String raw = "[\"q1\",\"q2\"]";
        when(groqService.chatCompletionWithUsage(anyList(), anyBoolean(), any(), any()))
                .thenReturn(GroqService.ChatCompletionResult.of(raw, 1, 1, 2));

        ChatbotService.AiCallResult response = chatbotService.generateSpeakingTestQuestions("IELTS Part 1");

        assertEquals(raw, response.content());
    }

    @Test
    void checkTranslation_ShouldReturnNullContent_WhenGroqReturnsNull() {
        when(groqService.chatCompletionWithUsage(anyList(), anyBoolean(), any(), any()))
                .thenReturn(GroqService.ChatCompletionResult.of(null, 0, 0, 0));

        ChatbotService.AiCallResult response = chatbotService.checkTranslation("text");

        assertNull(response.content());
    }

    @Test
    void evaluateSpeakingTest_ShouldAppendJsonInstructionToUserMessage() {
        when(groqService.chatCompletionWithUsage(anyList(), anyBoolean(), any(), any()))
                .thenReturn(GroqService.ChatCompletionResult.of("{\"overallScore\":7}", 10, 20, 30));

        ChatbotService.AiCallResult response = chatbotService.evaluateSpeakingTest("my answer");

        assertEquals("{\"overallScore\":7}", response.content());

        ArgumentCaptor<List<Map<String, String>>> messagesCaptor = ArgumentCaptor.forClass(List.class);
        verify(groqService).chatCompletionWithUsage(messagesCaptor.capture(), eq(true), any(), any());
        List<Map<String, String>> messages = messagesCaptor.getValue();
        assertEquals("my answer Return ONLY JSON.", messages.get(1).get("content"));
    }
}
