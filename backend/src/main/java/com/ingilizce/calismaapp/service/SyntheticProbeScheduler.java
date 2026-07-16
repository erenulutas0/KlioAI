package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.config.SyntheticProbeProperties;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

@Service
public class SyntheticProbeScheduler {

    private final SyntheticProbeProperties properties;
    private final SyntheticProbeService syntheticProbeService;

    public SyntheticProbeScheduler(
            SyntheticProbeProperties properties,
            SyntheticProbeService syntheticProbeService) {
        this.properties = properties;
        this.syntheticProbeService = syntheticProbeService;
    }

    @Scheduled(
            cron = "${app.ops.synthetic-probe.cron:0 */15 * * * *}",
            zone = "${app.ops.synthetic-probe.zone:UTC}")
    public void runScheduledProbe() {
        if (!properties.isEnabled()) {
            return;
        }
        syntheticProbeService.runProbe();
    }
}
