package com.ingilizce.calismaapp.service;

import java.time.Instant;

/**
 * What the synthetic AI probe currently knows, and how sure it is.
 *
 * <p>Four states rather than a boolean, because the failure this whole
 * arrangement exists to avoid is monitoring that cannot tell "fine" from "not
 * looking". The alert stack it replaces had exactly that shape: rules written,
 * Prometheus never deployed, and an Alertmanager pointed at an echo container,
 * so every alarm resolved to silence — the same silence as everything working.
 *
 * <ul>
 *   <li>{@link #UP} — the last probe reached the AI provider and got the
 *       expected answer.</li>
 *   <li>{@link #DOWN} — consecutive probes failed. Reported to an uptime
 *       monitor as 503, which is the thing that reaches a phone.</li>
 *   <li>{@link #STALE} — probes have stopped running. Also 503: not knowing
 *       is a problem in its own right, and claiming health on hours-old data
 *       would be a lie.</li>
 *   <li>{@link #UNKNOWN} — no probe has run yet and the process has not been
 *       up long enough for that to be suspicious, or probing is switched off.
 *       Reported as 200 so a restart never pages anyone.</li>
 * </ul>
 */
public record AiProbeSnapshot(
        AiProbeSnapshot.Health health,
        Instant lastProbeAt,
        int consecutiveFailures) {

    public enum Health {
        UP,
        DOWN,
        STALE,
        UNKNOWN;

        /** Whether an uptime monitor should treat this as a failure. */
        public boolean isAlerting() {
            return this == DOWN || this == STALE;
        }
    }

    public boolean isAlerting() {
        return health.isAlerting();
    }
}
