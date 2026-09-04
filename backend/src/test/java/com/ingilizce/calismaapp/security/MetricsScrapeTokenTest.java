package com.ingilizce.calismaapp.security;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The gate in front of /actuator/prometheus.
 *
 * <p>Enabling the metrics endpoint in production was not enough to make the
 * alerts work: SecurityConfig permitted only /actuator/health, so every scrape
 * got 401 and nineteen alert rules evaluated against no data. This is what lets
 * Prometheus through, so it has to be exactly as narrow as it looks.
 */
class MetricsScrapeTokenTest {

    private static final String SECRET = "s3cr3t-scrape-token";

    @Test
    @DisplayName("the configured token, as Prometheus sends it, is accepted")
    void acceptsTheConfiguredBearerToken() {
        MetricsScrapeToken token = new MetricsScrapeToken(SECRET);

        assertThat(token.isConfigured()).isTrue();
        assertThat(token.matches("Bearer " + SECRET)).isTrue();
    }

    @Test
    @DisplayName("an unset token fails closed rather than opening the endpoint")
    void unsetTokenRejectsEverything() {
        // The default. A missing configuration must leave metrics behind
        // normal authentication, never expose them to the internet.
        for (String unset : new String[] { null, "", "   " }) {
            MetricsScrapeToken token = new MetricsScrapeToken(unset);

            assertThat(token.isConfigured()).isFalse();
            assertThat(token.matches("Bearer " + SECRET)).isFalse();
            assertThat(token.matches("Bearer ")).isFalse();
            assertThat(token.matches(null)).isFalse();
        }
    }

    @Test
    @DisplayName("a wrong, partial or differently-cased token is rejected")
    void rejectsAnythingButAnExactMatch() {
        MetricsScrapeToken token = new MetricsScrapeToken(SECRET);

        assertThat(token.matches("Bearer wrong")).isFalse();
        assertThat(token.matches("Bearer " + SECRET + "x")).isFalse();
        assertThat(token.matches("Bearer " + SECRET.substring(0, 5))).isFalse();
        assertThat(token.matches("Bearer " + SECRET.toUpperCase())).isFalse();
    }

    @Test
    @DisplayName("only the Bearer scheme is read")
    void requiresTheBearerScheme() {
        MetricsScrapeToken token = new MetricsScrapeToken(SECRET);

        assertThat(token.matches(SECRET)).isFalse();
        assertThat(token.matches("Basic " + SECRET)).isFalse();
        assertThat(token.matches("bearer " + SECRET)).isFalse();
        assertThat(token.matches(null)).isFalse();
    }

    @Test
    @DisplayName("surrounding whitespace in the header does not break the scrape")
    void toleratesPaddingAroundTheToken() {
        // credentials_file content picks up a trailing newline more often than
        // not, and a scrape failing over an invisible character would be a
        // miserable thing to debug.
        MetricsScrapeToken token = new MetricsScrapeToken(SECRET);

        assertThat(token.matches("Bearer  " + SECRET + "  ")).isTrue();
        assertThat(token.matches("Bearer " + SECRET + "\n")).isTrue();
    }
}
