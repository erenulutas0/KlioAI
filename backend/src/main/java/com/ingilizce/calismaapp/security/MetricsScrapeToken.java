package com.ingilizce.calismaapp.security;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

/**
 * The shared secret Prometheus presents to read {@code /actuator/prometheus}.
 *
 * <p>Exists because the metrics endpoint was switched on in production while
 * {@link SecurityConfig} permitted only {@code /actuator/health}: every scrape
 * came back 401, {@code up} stayed 0, and every rule under
 * {@code monitoring/prometheus/alerts} evaluated against no data. The alerting
 * looked configured and saw nothing.
 *
 * <p>A token rather than an IP allowlist because Prometheus reaches the backend
 * over the Docker network while Caddy reaches it from the host, and both arrive
 * from private addresses that cannot be told apart. A token rather than a
 * separate management port because the public {@code /actuator/health} is
 * load-bearing: the deploy's own smoke test, the rollout verification and the
 * readiness scripts all call it.
 *
 * <p>An unset token leaves the endpoint behind normal authentication rather
 * than opening it, so a missing configuration fails closed.
 */
public final class MetricsScrapeToken {

    private static final String BEARER = "Bearer ";

    private final byte[] expected;

    public MetricsScrapeToken(String configured) {
        this.expected = (configured == null || configured.isBlank())
                ? null
                : configured.getBytes(StandardCharsets.UTF_8);
    }

    /** Whether a token is configured at all. */
    public boolean isConfigured() {
        return expected != null;
    }

    /**
     * Whether {@code authorizationHeader} carries the configured token.
     *
     * <p>Reads {@code Authorization: Bearer <token>}, which is what
     * Prometheus's own {@code authorization} block sends, so the scrape config
     * needs no custom header. Compared with
     * {@link MessageDigest#isEqual(byte[], byte[])} so a wrong guess takes the
     * same time as a right one.
     */
    public boolean matches(String authorizationHeader) {
        if (expected == null || authorizationHeader == null) {
            return false;
        }
        if (!authorizationHeader.startsWith(BEARER)) {
            return false;
        }
        byte[] presented = authorizationHeader.substring(BEARER.length())
                .trim()
                .getBytes(StandardCharsets.UTF_8);
        return MessageDigest.isEqual(presented, expected);
    }
}
