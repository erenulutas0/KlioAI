package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.config.AiModelRoutingProperties;
import com.ingilizce.calismaapp.config.SyntheticProbeProperties;
import io.micrometer.core.instrument.MeterRegistry;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;
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
    private final SyntheticProbeProperties probeProperties;

    // The probe used to write its result to a log line and a counter and
    // forget it. Both need something already collecting them to be worth
    // anything, and nothing was: Prometheus was never deployed and the
    // Alertmanager receiver is an echo container. Keeping the last outcome in
    // memory lets a plain uptime monitor -- the kind that reaches a phone --
    // ask the question directly.
    private final AtomicInteger consecutiveFailures = new AtomicInteger();
    private volatile Instant lastProbeAt;
    private final Instant startedAt;

    // Marked explicitly: the test constructor below is a second candidate, and
    // without this Spring refuses to choose between them.
    @Autowired
    public SyntheticProbeService(
            AiCompletionProvider aiCompletionProvider,
            AiModelRoutingProperties modelRoutingProperties,
            @Autowired(required = false) MeterRegistry meterRegistry,
            SyntheticProbeProperties probeProperties) {
        this(aiCompletionProvider, modelRoutingProperties, meterRegistry,
                probeProperties, Instant.now());
    }

    // Visible for tests, which need to say when the process started so that
    // "up long enough that a missing probe is suspicious" is reachable without
    // waiting three quarters of an hour.
    SyntheticProbeService(
            AiCompletionProvider aiCompletionProvider,
            AiModelRoutingProperties modelRoutingProperties,
            MeterRegistry meterRegistry,
            SyntheticProbeProperties probeProperties,
            Instant startedAt) {
        this.aiCompletionProvider = aiCompletionProvider;
        this.modelRoutingProperties = modelRoutingProperties;
        this.meterRegistry = meterRegistry;
        this.probeProperties = probeProperties;
        this.startedAt = startedAt;
    }

    /**
     * What the probe currently knows, as of {@code now}.
     *
     * <p>Staleness is decided before failure on purpose. If probing stopped an
     * hour ago after two failures, both are true, and "I have not checked
     * recently" is the honest answer -- reporting DOWN would be asserting
     * something current from evidence that is not.
     */
    public AiProbeSnapshot snapshot(Instant now) {
        int failures = consecutiveFailures.get();
        if (!probeProperties.isEnabled()) {
            return new AiProbeSnapshot(AiProbeSnapshot.Health.UNKNOWN, lastProbeAt, failures);
        }

        Instant since = lastProbeAt != null ? lastProbeAt : startedAt;
        boolean overdue = since.plus(probeProperties.getStaleAfter()).isBefore(now);

        if (lastProbeAt == null) {
            // Nothing has run yet. Harmless just after a restart; a sign the
            // scheduler is not firing at all once the process has been up
            // longer than a probe interval allows for.
            return new AiProbeSnapshot(
                    overdue ? AiProbeSnapshot.Health.STALE : AiProbeSnapshot.Health.UNKNOWN,
                    null,
                    failures);
        }
        if (overdue) {
            return new AiProbeSnapshot(AiProbeSnapshot.Health.STALE, lastProbeAt, failures);
        }
        if (failures >= probeProperties.getFailuresBeforeDown()) {
            return new AiProbeSnapshot(AiProbeSnapshot.Health.DOWN, lastProbeAt, failures);
        }
        return new AiProbeSnapshot(AiProbeSnapshot.Health.UP, lastProbeAt, failures);
    }

    public AiProbeSnapshot snapshot() {
        return snapshot(Instant.now());
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
        lastProbeAt = Instant.now();
        if (healthy) {
            consecutiveFailures.set(0);
        } else {
            consecutiveFailures.incrementAndGet();
        }
        if (meterRegistry == null) {
            return;
        }
        meterRegistry.counter("app.synthetic.probe.total", "outcome", healthy ? "success" : "failure")
                .increment();
        meterRegistry.timer("app.synthetic.probe.latency", "outcome", healthy ? "success" : "failure")
                .record(Duration.ofMillis(elapsedMs));
    }
}
