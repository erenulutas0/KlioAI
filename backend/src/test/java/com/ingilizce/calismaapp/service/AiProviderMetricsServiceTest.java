package com.ingilizce.calismaapp.service;

import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

class AiProviderMetricsServiceTest {

    @Test
    void recordSuccess_shouldNormalizeLabelsAndAggregateTokens() {
        SimpleMeterRegistry meterRegistry = new SimpleMeterRegistry();
        AiProviderMetricsService service = new AiProviderMetricsService(meterRegistry);

        service.recordSuccess(" Groq ", " LLaMA-3.3 ", new AiCompletionProvider.CompletionResult("ok", 10, 5, 15));
        service.recordSuccess("groq", "llama-3.3", new AiCompletionProvider.CompletionResult("ok", -1, 4, 3));

        AiProviderMetricsService.Snapshot snapshot = service.snapshot();

        assertEquals(2, snapshot.requestCount());
        assertEquals(2, snapshot.successCount());
        assertEquals(0, snapshot.errorCount());
        assertEquals(10, snapshot.promptTokens());
        assertEquals(9, snapshot.completionTokens());
        assertEquals(18, snapshot.totalTokens());
        assertEquals(1, snapshot.providers().size());

        AiProviderMetricsService.ProviderMetric metric = snapshot.providers().get(0);
        assertEquals("groq", metric.provider());
        assertEquals("llama-3.3", metric.model());
        assertEquals(2, metric.requestCount());
        assertEquals(2, metric.successCount());

        assertNotNull(meterRegistry.find("ai.provider.request.total")
                .tag("provider", "groq")
                .tag("model", "llama-3.3")
                .tag("outcome", "success")
                .counter());
        assertEquals(2.0, meterRegistry.find("ai.provider.request.total")
                .tag("provider", "groq")
                .tag("model", "llama-3.3")
                .tag("outcome", "success")
                .counter()
                .count());
    }

    @Test
    void recordError_shouldUseFallbackLabelsAndWorkWithoutMeterRegistry() {
        AiProviderMetricsService service = new AiProviderMetricsService(null);

        service.recordError(" ", null);

        AiProviderMetricsService.Snapshot snapshot = service.snapshot();

        assertEquals(1, snapshot.requestCount());
        assertEquals(0, snapshot.successCount());
        assertEquals(1, snapshot.errorCount());
        assertEquals(1, snapshot.providers().size());
        assertEquals("unknown", snapshot.providers().get(0).provider());
        assertEquals("default", snapshot.providers().get(0).model());
    }

    @Test
    void snapshot_shouldSortProviderMetricsByProviderThenModel() {
        AiProviderMetricsService service = new AiProviderMetricsService(null);

        service.recordError("zeta", "b");
        service.recordError("alpha", "c");
        service.recordError("alpha", "a");

        AiProviderMetricsService.Snapshot snapshot = service.snapshot();

        assertEquals("alpha", snapshot.providers().get(0).provider());
        assertEquals("a", snapshot.providers().get(0).model());
        assertEquals("alpha", snapshot.providers().get(1).provider());
        assertEquals("c", snapshot.providers().get(1).model());
        assertEquals("zeta", snapshot.providers().get(2).provider());
    }
}
