package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.config.AiModelRoutingProperties;
import io.micrometer.core.instrument.MeterRegistry;
import java.time.Duration;
import java.util.List;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

// Calls the AI provider directly with a fixed, cheap prompt so it never touches
// per-user quota/rate-limit accounting - this is meant to catch "the AI pipeline
// itself is down" independently of any real user's activity.
@Service
public class SyntheticProbeService {

    private static final Logger logger = LoggerFactory.getLogger(SyntheticProbeService.class);
    private static final String PROBE_PROMPT = "Reply with exactly the single word: OK";
    private static final String EXPECTED_SUBSTRING = "OK";

    private final AiCompletionProvider aiCompletionProvider;
    private final AiModelRoutingProperties modelRoutingProperties;
    private final MeterRegistry meterRegistry;

    public SyntheticProbeService(
            AiCompletionProvider aiCompletionProvider,
            AiModelRoutingProperties modelRoutingProperties,
            @Autowired(required = false) MeterRegistry meterRegistry) {
        this.aiCompletionProvider = aiCompletionProvider;
        this.modelRoutingProperties = modelRoutingProperties;
        this.meterRegistry = meterRegistry;
    }

    public boolean runProbe() {
        long startNanos = System.nanoTime();
        try {
            String response = aiCompletionProvider.chatCompletion(
                    List.of(Map.of("role", "user", "content", PROBE_PROMPT)),
                    false,
                    modelRoutingProperties.getUtilityModel());
            long elapsedMs = elapsedMs(startNanos);
            boolean healthy = response != null && response.toUpperCase(java.util.Locale.ROOT)
                    .contains(EXPECTED_SUBSTRING);
            recordResult(healthy, elapsedMs);
            if (healthy) {
                logger.info("Synthetic AI probe OK elapsedMs={}", elapsedMs);
            } else {
                logger.error("SYNTHETIC_PROBE_FAILURE reason=unexpected-response elapsedMs={} response={}",
                        elapsedMs, response);
            }
            return healthy;
        } catch (Exception e) {
            long elapsedMs = elapsedMs(startNanos);
            recordResult(false, elapsedMs);
            logger.error("SYNTHETIC_PROBE_FAILURE reason=exception elapsedMs={} error={}",
                    elapsedMs, e.getMessage());
            return false;
        }
    }

    private long elapsedMs(long startNanos) {
        return (System.nanoTime() - startNanos) / 1_000_000;
    }

    private void recordResult(boolean healthy, long elapsedMs) {
        if (meterRegistry == null) {
            return;
        }
        meterRegistry.counter("app.synthetic.probe.total", "outcome", healthy ? "success" : "failure")
                .increment();
        meterRegistry.timer("app.synthetic.probe.latency", "outcome", healthy ? "success" : "failure")
                .record(Duration.ofMillis(elapsedMs));
    }
}
