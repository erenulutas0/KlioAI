package com.ingilizce.calismaapp.service;

import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Map;

@Service
public class GroqAiCompletionProvider implements AiCompletionProvider {
    private final GroqService groqService;

    public GroqAiCompletionProvider(GroqService groqService) {
        this.groqService = groqService;
    }

    @Override
    public CompletionResult chatCompletionWithUsage(List<Map<String, String>> messages,
                                                    boolean jsonResponse,
                                                    Integer maxTokens,
                                                    Double temperature,
                                                    String modelOverride) {
        GroqService.ChatCompletionResult result = groqService.chatCompletionWithUsage(
                messages,
                jsonResponse,
                maxTokens,
                temperature,
                modelOverride);
        if (result == null) {
            return CompletionResult.empty();
        }
        return CompletionResult.of(
                result.content(),
                result.promptTokens(),
                result.completionTokens(),
                result.totalTokens());
    }
}
