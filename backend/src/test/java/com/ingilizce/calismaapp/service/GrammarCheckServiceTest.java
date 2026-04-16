package com.ingilizce.calismaapp.service;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class GrammarCheckServiceTest {

    @Mock
    private GroqService groqService;

    // We don't need to mock ObjectMapper, it's a real object initialized in
    // constructor.
    // But since it is instantiated inside constructor of Service, we can't easily
    // replace it if we wanted to.
    // However, InjectMocks will try to constructor inject GroqService.
    // The real ObjectMapper will be created. That is fine.

    // NOTE: InjectMocks uses the constructor that takes GroqService.
    @InjectMocks
    private GrammarCheckService grammarCheckService;

    @Test
    void checkGrammar_ShouldReturnErrors_WhenGrammarIsIncorrect() {
        // Mock Response JSON String
        String jsonResponse = "{" +
                "\"hasErrors\": true," +
                "\"errorCount\": 1," +
                "\"errors\": [{" +
                "  \"message\": \"Bad grammar\"," +
                "  \"shortMessage\": \"Grammar\"," +
                "  \"fromPos\": 0," +
                "  \"toPos\": 5," +
                "  \"suggestions\": [\"Good\"]" +
                "}]" +
                "}";

        when(groqService.chatCompletion(anyList(), eq(true), nullable(String.class))).thenReturn(jsonResponse);

        Map<String, Object> result = grammarCheckService.checkGrammar("Bad sentence");

        assertTrue((Boolean) result.get("hasErrors"));
        assertEquals(1, result.get("errorCount"));
        verify(groqService).chatCompletion(anyList(), eq(true), nullable(String.class));
    }

    @Test
    void checkGrammar_ShouldReturnSuccess_WhenGrammarIsCorrect() {
        String jsonResponse = "{" +
                "\"hasErrors\": false," +
                "\"errorCount\": 0," +
                "\"errors\": []" +
                "}";

        when(groqService.chatCompletion(anyList(), eq(true), nullable(String.class))).thenReturn(jsonResponse);

        Map<String, Object> result = grammarCheckService.checkGrammar("Good sentence");

        assertFalse((Boolean) result.get("hasErrors"));
    }

    @Test
    void checkGrammar_ShouldHandleException_AndReturnEmptyResult() {
        when(groqService.chatCompletion(anyList(), eq(true), nullable(String.class))).thenThrow(new RuntimeException("API Error"));

        // The service catches exception and throws RuntimeException in catch block?
        // Let's check source code...
        // catch (Exception e) { throw new RuntimeException("Grammar Check Failed: " +
        // e.getMessage()); }

        assertThrows(RuntimeException.class, () -> grammarCheckService.checkGrammar("Test"));
    }

    @Test
    void checkGrammar_ShouldReturnNoErrorResponse_WhenDisabled() {
        grammarCheckService.setEnabled(false);

        Map<String, Object> result = grammarCheckService.checkGrammar("Any sentence");

        assertFalse((Boolean) result.get("hasErrors"));
        assertEquals(0, result.get("errorCount"));
        verifyNoInteractions(groqService);
    }

    @Test
    void checkGrammar_ShouldReturnNoErrorResponse_WhenSentenceBlank() {
        Map<String, Object> result = grammarCheckService.checkGrammar("   ");

        assertFalse((Boolean) result.get("hasErrors"));
        assertEquals(0, result.get("errorCount"));
        verifyNoInteractions(groqService);
    }

    @Test
    void checkGrammar_ShouldReturnNoErrorResponse_WhenGroqReturnsNull() {
        when(groqService.chatCompletion(anyList(), eq(true), nullable(String.class))).thenReturn(null);

        Map<String, Object> result = grammarCheckService.checkGrammar("Hello");

        assertFalse((Boolean) result.get("hasErrors"));
        assertEquals(0, result.get("errorCount"));
        verify(groqService).chatCompletion(anyList(), eq(true), nullable(String.class));
    }

    @Test
    void checkMultipleSentences_ShouldAggregateErrors() {
        String errorJson = "{" +
                "\"hasErrors\": true," +
                "\"errorCount\": 1," +
                "\"errors\": [{\"message\": \"Error\"}]" +
                "}";

        when(groqService.chatCompletion(anyList(), eq(true), nullable(String.class))).thenReturn(errorJson);

        List<String> sentences = new ArrayList<>();
        sentences.add("S1");
        sentences.add("S2");

        Map<String, List<Map<String, Object>>> results = grammarCheckService.checkMultipleSentences(sentences);

        assertEquals(2, results.size());
    }

    @Test
    void checkMultipleSentences_ShouldIgnoreNoErrorAndInvalidErrorShape() {
        String noErrorJson = "{\"hasErrors\":false,\"errorCount\":0,\"errors\":[]}";
        String invalidErrorsJson = "{\"hasErrors\":true,\"errorCount\":1,\"errors\":\"oops\"}";
        when(groqService.chatCompletion(anyList(), eq(true), nullable(String.class)))
                .thenReturn(noErrorJson)
                .thenReturn(invalidErrorsJson);

        List<String> sentences = List.of("S1", "S2");
        Map<String, List<Map<String, Object>>> results = grammarCheckService.checkMultipleSentences(sentences);

        assertTrue(results.isEmpty());
    }

    @Test
    void isEnabled_ShouldReflectSetEnabledValue() {
        grammarCheckService.setEnabled(true);
        assertTrue(grammarCheckService.isEnabled());

        grammarCheckService.setEnabled(false);
        assertFalse(grammarCheckService.isEnabled());
    }
}

