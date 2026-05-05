package com.ingilizce.calismaapp.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * AI ile gramer kontrolü servisi.
 */
@Service
public class GrammarCheckService {

    private static final Logger logger = LoggerFactory.getLogger(GrammarCheckService.class);

    private final AiCompletionProvider aiCompletionProvider;
    private final ObjectMapper objectMapper;
    @Autowired(required = false)
    private AiModelRoutingService aiModelRoutingService;
    private boolean enabled = true;

    @Autowired
    public GrammarCheckService(AiCompletionProvider aiCompletionProvider) {
        this.aiCompletionProvider = aiCompletionProvider;
        this.objectMapper = new ObjectMapper();

        logger.info("============================================");
        logger.info("✅ GrammarCheckService Initialized");
        logger.info("✅ AiCompletionProvider status: {}", (aiCompletionProvider != null ? "CONNECTED" : "NULL"));
        logger.info("============================================");
    }

    /**
     * Bir cümlenin gramerini kontrol eder
     * 
     * @param sentence Kontrol edilecek cümle
     * @return Gramer hataları listesi
     */
    public Map<String, Object> checkGrammar(String sentence) {
        logger.info("📝 Check Grammar Request: '{}'", sentence);

        if (!enabled || sentence == null || sentence.trim().isEmpty()) {
            return createNoErrorResponse();
        }

        try {
            // Prompt hazırlama
            String prompt = String.format(
                    "You are an expert English grammar checker. Analyze the following sentence for grammar, spelling, punctuation, and style errors.\n\n"
                            +
                            "Sentence: \"%s\"\n\n" +
                            "Return ONLY a valid JSON object with this exact structure (no markdown, no explanations outside JSON):\n"
                            +
                            "{\n" +
                            "  \"hasErrors\": boolean,\n" +
                            "  \"errors\": [\n" +
                            "    {\n" +
                            "      \"message\": \"Detailed explanation of the error\",\n" +
                            "      \"shortMessage\": \"Short error name (e.g. 'Wrong Verb Form')\",\n" +
                            "      \"fromPos\": int (0-based start index of the error in the original sentence),\n" +
                            "      \"toPos\": int (0-based end index of the error),\n" +
                            "      \"suggestions\": [\"suggestion1\", \"suggestion2\"]\n" +
                            "    }\n" +
                            "  ],\n" +
                            "  \"errorCount\": int\n" +
                            "}\n\n" +
                            "If there are no errors, set hasErrors to false, errors to [], and errorCount to 0.\n" +
                            "Ensure fromPos and toPos are accurate character indices.",
                    sentence.replace("\"", "\\\""));

            List<Map<String, String>> messages = new ArrayList<>();
            Map<String, String> userMessage = new HashMap<>();
            userMessage.put("role", "user");
            userMessage.put("content", prompt);
            messages.add(userMessage);

            logger.info("🚀 Calling AI completion provider...");
            String jsonResponse = aiCompletionProvider.chatCompletion(messages, true, resolveModelForScope("check-grammar"));
            logger.info("📩 AI response received (Length: {})",
                    jsonResponse != null ? jsonResponse.length() : "NULL");

            if (jsonResponse != null) {
                return objectMapper.readValue(jsonResponse, Map.class);
            }

        } catch (Exception e) {
            logger.error("❌ Error checking grammar with AI provider: {}", e.getMessage(), e);
            throw new RuntimeException("Grammar Check Failed: " + e.getMessage());
        }

        return createNoErrorResponse();
    }

    /**
     * Birden fazla cümlenin gramerini kontrol eder
     */
    @SuppressWarnings("unchecked")
    public Map<String, List<Map<String, Object>>> checkMultipleSentences(List<String> sentences) {
        Map<String, List<Map<String, Object>>> results = new HashMap<>();

        for (String sentence : sentences) {
            Map<String, Object> checkResult = checkGrammar(sentence);
            Object errorsObj = checkResult.get("errors");
            if (errorsObj instanceof List) {
                List<Map<String, Object>> errors = (List<Map<String, Object>>) errorsObj;
                if (errors != null && !errors.isEmpty()) {
                    results.put(sentence, errors);
                }
            }
        }

        return results;
    }

    private Map<String, Object> createNoErrorResponse() {
        Map<String, Object> result = new HashMap<>();
        result.put("hasErrors", false);
        result.put("errors", new ArrayList<>());
        result.put("errorCount", 0);
        return result;
    }

    public void setEnabled(boolean enabled) {
        this.enabled = enabled;
    }

    public boolean isEnabled() {
        return enabled;
    }

    private String resolveModelForScope(String scope) {
        if (aiModelRoutingService == null) {
            return null;
        }
        return aiModelRoutingService.resolveModelForScope(scope);
    }
}
