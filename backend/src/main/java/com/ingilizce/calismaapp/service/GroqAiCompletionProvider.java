package com.ingilizce.calismaapp.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Map;

@Service
public class GroqAiCompletionProvider implements AiCompletionProvider {
    private static final Logger logger = LoggerFactory.getLogger(GroqAiCompletionProvider.class);
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
                recordEmpty(modelOverride, "null-result");
                return CompletionResult.empty();
            }
            CompletionResult completion = CompletionResult.of(
                    result.content(),
                    result.promptTokens(),
                    result.completionTokens(),
                    result.totalTokens());
            // A response that arrived carrying nothing is not a success. It used to be
            // counted as one — which is how the provider metric read 100% healthy for three
            // months while learners were being served hardcoded template sentences by the
            // fallback path downstream. The request really had worked; it just came back
            // empty, and nothing in the system was willing to say that out loud.
            if (completion.content() == null || completion.content().isBlank()) {
                recordEmpty(modelOverride, "blank-content");
                return completion;
            }
            recordSuccess(modelOverride, completion);
            return completion;
        } catch (RuntimeException ex) {
            recordError(modelOverride);
            throw ex;
        }
    }

    private void recordEmpty(String modelOverride, String reason) {
        // WARN, not DEBUG: an empty generation is invisible to the learner-facing flow,
        // which substitutes a fallback and carries on looking normal.
        logger.warn("AI completion returned nothing usable. model={} reason={}",
                modelOverride == null ? "default" : modelOverride, reason);
        if (metricsService != null) {
            metricsService.recordEmpty(PROVIDER_NAME, modelOverride);
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
