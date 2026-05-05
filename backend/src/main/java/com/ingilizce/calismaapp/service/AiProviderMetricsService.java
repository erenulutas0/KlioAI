package com.ingilizce.calismaapp.service;

import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;

@Service
public class AiProviderMetricsService {

    public record ProviderMetric(String dateUtc,
                                 String provider,
                                 String model,
                                 long requestCount,
                                 long successCount,
                                 long errorCount,
                                 long promptTokens,
                                 long completionTokens,
                                 long totalTokens) {
    }

    public record Snapshot(String dateUtc,
                           long requestCount,
                           long successCount,
                           long errorCount,
                           long promptTokens,
                           long completionTokens,
                           long totalTokens,
                           List<ProviderMetric> providers) {
    }

    private final MeterRegistry meterRegistry;
    private final Map<String, MutableMetric> metrics = new ConcurrentHashMap<>();

    @Autowired
    public AiProviderMetricsService(@Autowired(required = false) MeterRegistry meterRegistry) {
        this.meterRegistry = meterRegistry;
    }

    public void recordSuccess(String provider,
                              String model,
                              AiCompletionProvider.CompletionResult result) {
        String normalizedProvider = normalize(provider, "unknown");
        String normalizedModel = normalize(model, "default");
        MutableMetric metric = metricFor(normalizedProvider, normalizedModel);
        metric.requestCount.incrementAndGet();
        metric.successCount.incrementAndGet();
        if (result != null) {
            metric.promptTokens.addAndGet(Math.max(0, result.promptTokens()));
            metric.completionTokens.addAndGet(Math.max(0, result.completionTokens()));
            metric.totalTokens.addAndGet(Math.max(0, result.totalTokens()));
        }
        incrementCounter("ai.provider.request.total", normalizedProvider, normalizedModel, "success", 1);
    }

    public void recordError(String provider, String model) {
        String normalizedProvider = normalize(provider, "unknown");
        String normalizedModel = normalize(model, "default");
        MutableMetric metric = metricFor(normalizedProvider, normalizedModel);
        metric.requestCount.incrementAndGet();
        metric.errorCount.incrementAndGet();
        incrementCounter("ai.provider.request.total", normalizedProvider, normalizedModel, "error", 1);
    }

    public Snapshot snapshot() {
        String dateUtc = LocalDate.now(ZoneOffset.UTC).toString();
        List<ProviderMetric> providerMetrics = metrics.entrySet().stream()
                .filter(entry -> entry.getKey().startsWith(dateUtc + "|"))
                .map(entry -> entry.getValue().toRecord())
                .sorted(Comparator.comparing(ProviderMetric::provider).thenComparing(ProviderMetric::model))
                .toList();

        long requestCount = providerMetrics.stream().mapToLong(ProviderMetric::requestCount).sum();
        long successCount = providerMetrics.stream().mapToLong(ProviderMetric::successCount).sum();
        long errorCount = providerMetrics.stream().mapToLong(ProviderMetric::errorCount).sum();
        long promptTokens = providerMetrics.stream().mapToLong(ProviderMetric::promptTokens).sum();
        long completionTokens = providerMetrics.stream().mapToLong(ProviderMetric::completionTokens).sum();
        long totalTokens = providerMetrics.stream().mapToLong(ProviderMetric::totalTokens).sum();

        return new Snapshot(
                dateUtc,
                requestCount,
                successCount,
                errorCount,
                promptTokens,
                completionTokens,
                totalTokens,
                providerMetrics);
    }

    private MutableMetric metricFor(String provider, String model) {
        String dateUtc = LocalDate.now(ZoneOffset.UTC).toString();
        String key = dateUtc + "|" + provider + "|" + model;
        return metrics.computeIfAbsent(key, ignored -> new MutableMetric(dateUtc, provider, model));
    }

    private String normalize(String value, String fallback) {
        if (value == null || value.isBlank()) {
            return fallback;
        }
        return value.trim().toLowerCase();
    }

    private void incrementCounter(String name, String provider, String model, String outcome, double amount) {
        if (meterRegistry == null) {
            return;
        }
        meterRegistry.counter(name, "provider", provider, "model", model, "outcome", outcome).increment(amount);
    }

    private static class MutableMetric {
        private final String dateUtc;
        private final String provider;
        private final String model;
        private final AtomicLong requestCount = new AtomicLong();
        private final AtomicLong successCount = new AtomicLong();
        private final AtomicLong errorCount = new AtomicLong();
        private final AtomicLong promptTokens = new AtomicLong();
        private final AtomicLong completionTokens = new AtomicLong();
        private final AtomicLong totalTokens = new AtomicLong();

        private MutableMetric(String dateUtc, String provider, String model) {
            this.dateUtc = dateUtc;
            this.provider = provider;
            this.model = model;
        }

        private ProviderMetric toRecord() {
            return new ProviderMetric(
                    dateUtc,
                    provider,
                    model,
                    requestCount.get(),
                    successCount.get(),
                    errorCount.get(),
                    promptTokens.get(),
                    completionTokens.get(),
                    totalTokens.get());
        }
    }
}
