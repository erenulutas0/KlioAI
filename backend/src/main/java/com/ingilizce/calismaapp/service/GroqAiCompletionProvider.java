package com.ingilizce.calismaapp.service;

import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Map;

@Service
public class GroqAiCompletionProvider implements AiCompletionProvider {
    private static final String PROVIDER_NAME = "groq";

    private final GroqService groqService;
    private final AiProviderMetricsService metricsService;

    public GroqAiCompletionProvider(GroqService groqService,
                                    @org.springframework.beans.factory.annotation.Autowired(required = false)
                                    AiProviderMetricsService metricsService) {
        this.groqService = groqService;
        this.metricsService = metricsService;
    }

    @Override
    public CompletionResult chatCompletionWithUsage(List<Map<String, String>> messages,
                                                    boolean jsonResponse,
                                                    Integer maxTokens,
                                                    Double temperature,
                                                    String modelOverride) {
        try {
            GroqService.ChatCompletionResult result = groqService.chatCompletionWithUsage(
                    messages,
                    jsonResponse,
                    maxTokens,
                    temperature,
                    modelOverride);
            if (result == null) {
                CompletionResult empty = CompletionResult.empty();
                recordSuccess(modelOverride, empty);
                return empty;
            }
            CompletionResult completion = CompletionResult.of(
                    result.content(),
                    result.promptTokens(),
                    result.completionTokens(),
                    result.totalTokens());
            recordSuccess(modelOverride, completion);
            return completion;
        } catch (RuntimeException ex) {
            recordError(modelOverride);
            throw ex;
        }
    }

    private void recordSuccess(String modelOverride, CompletionResult result) {
        if (metricsService != null) {
            metricsService.recordSuccess(PROVIDER_NAME, modelOverride, result);
        }
    }

    private void recordError(String modelOverride) {
        if (metricsService != null) {
            metricsService.recordError(PROVIDER_NAME, modelOverride);
        }
    }
}
