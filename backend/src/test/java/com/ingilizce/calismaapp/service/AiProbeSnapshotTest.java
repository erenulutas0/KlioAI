package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.config.AiModelRoutingProperties;
import com.ingilizce.calismaapp.config.SyntheticProbeProperties;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;

import java.time.Duration;
import java.time.Instant;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;

/**
 * The state an uptime monitor reads to decide whether to wake somebody.
 *
 * <p>This exists because the monitoring that was supposed to catch an AI outage
 * could not have caught anything: twenty-two Prometheus rules were written, the
 * stack was never deployed to the server, and its Alertmanager pointed at an
 * echo container that would have logged each alert to its own stdout. Every
 * alarm resolved to silence — indistinguishable from everything being fine.
 *
 * <p>So the one property that matters here is that silence means something.
 * UNKNOWN and UP are quiet; DOWN and STALE are not; and "I have not checked
 * recently" is never reported as health.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class AiProbeSnapshotTest {

    private static final Instant BOOT = Instant.parse("2026-09-04T10:00:00Z");

    @Mock
    private AiCompletionProvider aiCompletionProvider;

    @Mock
    private AiModelRoutingProperties modelRoutingProperties;

    private SyntheticProbeProperties properties;

    @BeforeEach
    void setUp() {
        properties = new SyntheticProbeProperties();
        properties.setEnabled(true);
        when(modelRoutingProperties.getUtilityModel()).thenReturn("utility-model");
    }

    private SyntheticProbeService service() {
        return new SyntheticProbeService(
                aiCompletionProvider, modelRoutingProperties, null, properties, BOOT);
    }

    private void providerAnswers(String reply) {
        when(aiCompletionProvider.chatCompletion(any(), anyBoolean(), anyString()))
                .thenReturn(reply);
    }

    @Test
    @DisplayName("a fresh start is quiet until a probe has had time to run")
    void freshStartIsUnknownNotDown() {
        // A restart must never page anyone. The first probe fires on the next
        // quarter hour, so there is always a gap where nothing is known.
        AiProbeSnapshot snapshot = service().snapshot(BOOT.plus(Duration.ofMinutes(5)));

        assertThat(snapshot.health()).isEqualTo(AiProbeSnapshot.Health.UNKNOWN);
        assertThat(snapshot.isAlerting()).isFalse();
        assertThat(snapshot.lastProbeAt()).isNull();
    }

    @Test
    @DisplayName("a scheduler that never fires is caught, not mistaken for health")
    void neverRunningIsStaleOnceOverdue() {
        // The trap this whole endpoint exists to avoid: a monitor that cannot
        // tell "checked, fine" from "never checked".
        AiProbeSnapshot snapshot = service().snapshot(BOOT.plus(Duration.ofMinutes(46)));

        assertThat(snapshot.health()).isEqualTo(AiProbeSnapshot.Health.STALE);
        assertThat(snapshot.isAlerting()).isTrue();
    }

    @Test
    @DisplayName("a successful probe reports up")
    void successfulProbeIsUp() {
        providerAnswers("OK");
        SyntheticProbeService service = service();

        service.runProbe();

        AiProbeSnapshot snapshot = service.snapshot(Instant.now());
        assertThat(snapshot.health()).isEqualTo(AiProbeSnapshot.Health.UP);
        assertThat(snapshot.isAlerting()).isFalse();
        assertThat(snapshot.lastProbeAt()).isNotNull();
    }

    @Test
    @DisplayName("one failure is not enough to wake anyone")
    void singleFailureStaysQuiet() {
        // Providers blip. Paging on the first one is how a monitor gets muted.
        providerAnswers(null);
        SyntheticProbeService service = service();

        service.runProbe();

        assertThat(service.snapshot(Instant.now()).health())
                .isEqualTo(AiProbeSnapshot.Health.UP);
    }

    @Test
    @DisplayName("two consecutive failures report down")
    void twoFailuresAreDown() {
        providerAnswers(null);
        SyntheticProbeService service = service();

        service.runProbe();
        service.runProbe();

        AiProbeSnapshot snapshot = service.snapshot(Instant.now());
        assertThat(snapshot.health()).isEqualTo(AiProbeSnapshot.Health.DOWN);
        assertThat(snapshot.isAlerting()).isTrue();
        assertThat(snapshot.consecutiveFailures()).isEqualTo(2);
    }

    @Test
    @DisplayName("a recovery clears the failure run")
    void successAfterFailuresRecovers() {
        SyntheticProbeService service = service();
        providerAnswers(null);
        service.runProbe();
        service.runProbe();
        assertThat(service.snapshot(Instant.now()).health())
                .isEqualTo(AiProbeSnapshot.Health.DOWN);

        providerAnswers("OK");
        service.runProbe();

        assertThat(service.snapshot(Instant.now()).health())
                .isEqualTo(AiProbeSnapshot.Health.UP);
        assertThat(service.snapshot(Instant.now()).consecutiveFailures()).isZero();
    }

    @Test
    @DisplayName("stale beats down, because old evidence is not current knowledge")
    void staleWinsOverDown() {
        // Probes failed twice and then stopped. Reporting DOWN would assert
        // something about now from evidence that is an hour old; STALE says
        // what is actually true, and alerts just the same.
        providerAnswers(null);
        SyntheticProbeService service = service();
        service.runProbe();
        service.runProbe();

        AiProbeSnapshot snapshot = service.snapshot(Instant.now().plus(Duration.ofHours(1)));

        assertThat(snapshot.health()).isEqualTo(AiProbeSnapshot.Health.STALE);
        assertThat(snapshot.isAlerting()).isTrue();
    }

    @Test
    @DisplayName("probing switched off never alerts")
    void disabledProbeIsUnknown() {
        // Non-production runs with the probe off. It must not page a developer
        // whose laptop has no AI provider configured.
        properties.setEnabled(false);

        AiProbeSnapshot snapshot = service().snapshot(BOOT.plus(Duration.ofDays(1)));

        assertThat(snapshot.health()).isEqualTo(AiProbeSnapshot.Health.UNKNOWN);
        assertThat(snapshot.isAlerting()).isFalse();
    }

    @Test
    @DisplayName("the alerting states are exactly DOWN and STALE")
    void onlyDownAndStaleAlert() {
        // The endpoint turns this into 503 vs 200, and an uptime monitor reads
        // nothing else, so the mapping is the entire contract.
        assertThat(AiProbeSnapshot.Health.DOWN.isAlerting()).isTrue();
        assertThat(AiProbeSnapshot.Health.STALE.isAlerting()).isTrue();
        assertThat(AiProbeSnapshot.Health.UP.isAlerting()).isFalse();
        assertThat(AiProbeSnapshot.Health.UNKNOWN.isAlerting()).isFalse();
    }
}
