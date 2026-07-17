package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.config.TrialAbuseProtectionProperties;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class TrialAbuseProtectionServiceTest {

    private TrialAbuseProtectionService service;

    @BeforeEach
    void setUp() {
        TrialAbuseProtectionProperties properties = new TrialAbuseProtectionProperties();
        properties.setWindowHours(24);
        properties.setMaxTrialAccountsPerDevice(2);
        properties.setMaxTrialAccountsPerIp(4);
        service = new TrialAbuseProtectionService(properties);
    }

    @Test
    void evaluate_ShouldAllow_WhenNoRecentTrialGrantsExist() {
        TrialAbuseProtectionService.TrialDecision decision = service.evaluate("device-a", "10.0.0.1");

        assertTrue(decision.trialEligible());
        assertEquals("allowed", decision.reason());
    }

    @Test
    void evaluate_ShouldBlock_WhenDeviceLimitReached() {
        service.recordTrialGrant("device-a", "10.0.0.1");
        service.recordTrialGrant("device-a", "10.0.0.2");

        TrialAbuseProtectionService.TrialDecision decision = service.evaluate("device-a", "10.0.0.3");

        assertFalse(decision.trialEligible());
        assertEquals("device-limit", decision.reason());
    }

    @Test
    void evaluate_ShouldAllowFourTrialGrantsPerIpAndBlockFifthDeviceOnSameIp() {
        String sharedIp = "10.0.0.1";
        for (int i = 1; i <= 4; i++) {
            String deviceId = "device-" + i;
            TrialAbuseProtectionService.TrialDecision decision = service.evaluate(deviceId, sharedIp);
            assertTrue(decision.trialEligible(), "trial grant " + i + " should be allowed for shared IP");
            assertEquals("allowed", decision.reason());
            service.recordTrialGrant(deviceId, sharedIp);
        }

        TrialAbuseProtectionService.TrialDecision decision = service.evaluate("device-5", sharedIp);

        assertFalse(decision.trialEligible());
        assertEquals("ip-limit", decision.reason());
    }

    @Test
    void evaluate_ShouldRecordMetric_WhenIpLimitBlocksTrial() {
        TrialAbuseProtectionProperties properties = new TrialAbuseProtectionProperties();
        properties.setWindowHours(24);
        properties.setMaxTrialAccountsPerDevice(10);
        properties.setMaxTrialAccountsPerIp(1);
        SimpleMeterRegistry meterRegistry = new SimpleMeterRegistry();
        TrialAbuseProtectionService meteredService =
                new TrialAbuseProtectionService(properties, null, meterRegistry);

        meteredService.recordTrialGrant("device-a", "10.0.0.1");
        TrialAbuseProtectionService.TrialDecision decision =
                meteredService.evaluate("device-b", "10.0.0.1");

        assertFalse(decision.trialEligible());
        assertEquals("ip-limit", decision.reason());
        assertEquals(1.0, meterRegistry.counter(
                "auth.trial.abuse.block.total",
                "reason",
                "ip-limit").count());
    }
}
