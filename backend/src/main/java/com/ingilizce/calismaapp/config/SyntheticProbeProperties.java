package com.ingilizce.calismaapp.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

import java.time.Duration;

@Component
@ConfigurationProperties(prefix = "app.ops.synthetic-probe")
public class SyntheticProbeProperties {
    private boolean enabled = false;

    /**
     * How long the probe may go without running before its last answer stops
     * counting as current.
     *
     * <p>The schedule is every 15 minutes, so 45 lets two firings be missed
     * before anyone is woken. Tightening it below one interval would page on
     * every ordinary restart.
     */
    private Duration staleAfter = Duration.ofMinutes(45);

    /**
     * Consecutive failures before the AI is reported down.
     *
     * <p>Two, so a single blip from the provider -- which happens -- does not
     * reach a phone, but a real outage does within half an hour.
     */
    private int failuresBeforeDown = 2;

    public boolean isEnabled() {
        return enabled;
    }

    public void setEnabled(boolean enabled) {
        this.enabled = enabled;
    }

    public Duration getStaleAfter() {
        return staleAfter;
    }

    public void setStaleAfter(Duration staleAfter) {
        this.staleAfter = staleAfter;
    }

    public int getFailuresBeforeDown() {
        return failuresBeforeDown;
    }

    public void setFailuresBeforeDown(int failuresBeforeDown) {
        this.failuresBeforeDown = failuresBeforeDown;
    }
}
