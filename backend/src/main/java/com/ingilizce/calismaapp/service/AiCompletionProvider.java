package com.ingilizce.calismaapp.service;

import java.util.List;
import java.util.Map;

public interface AiCompletionProvider {
    record CompletionResult(String content, int promptTokens, int completionTokens, int totalTokens) {
        public static CompletionResult of(String content, int promptTokens, int completionTokens, int totalTokens) {
            return new CompletionResult(content, promptTokens, completionTokens, totalTokens);
        }

        public static CompletionResult empty() {
            return new CompletionResult(null, 0, 0, 0);
        }
    }

    CompletionResult chatCompletionWithUsage(List<Map<String, String>> messages,
                                             boolean jsonResponse,
                                             Integer maxTokens,
                                             Double temperature,
                                             String modelOverride);

    default String chatCompletion(List<Map<String, String>> messages,
                                  boolean jsonResponse,
                                  String modelOverride) {
        CompletionResult result = chatCompletionWithUsage(messages, jsonResponse, null, null, modelOverride);
        return result != null ? result.content() : null;
    }
}
