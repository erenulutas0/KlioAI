package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.config.SyntheticProbeProperties;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class SyntheticProbeSchedulerTest {

    @Mock
    private SyntheticProbeService syntheticProbeService;

    @Test
    void runScheduledProbeSkipsWhenDisabled() {
        SyntheticProbeProperties properties = new SyntheticProbeProperties();
        properties.setEnabled(false);
        SyntheticProbeScheduler scheduler = new SyntheticProbeScheduler(properties, syntheticProbeService);

        scheduler.runScheduledProbe();

        verify(syntheticProbeService, never()).runProbe();
    }

    @Test
    void runScheduledProbeRunsWhenEnabled() {
        SyntheticProbeProperties properties = new SyntheticProbeProperties();
        properties.setEnabled(true);
        when(syntheticProbeService.runProbe()).thenReturn(true);
        SyntheticProbeScheduler scheduler = new SyntheticProbeScheduler(properties, syntheticProbeService);

        scheduler.runScheduledProbe();

        verify(syntheticProbeService).runProbe();
    }
}
