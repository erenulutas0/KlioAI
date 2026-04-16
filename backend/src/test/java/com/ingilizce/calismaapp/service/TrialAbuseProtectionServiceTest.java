package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.config.TrialAbuseProtectionProperties;
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
        properties.setMaxTrialAccountsPerIp(3);
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
    void evaluate_ShouldBlock_WhenIpLimitReachedWithoutStableDeviceId() {
        service.recordTrialGrant("unknown-device", "10.0.0.1");
        service.recordTrialGrant("unknown-device", "10.0.0.1");
        service.recordTrialGrant("unknown-device", "10.0.0.1");

        TrialAbuseProtectionService.TrialDecision decision = service.evaluate("unknown-device", "10.0.0.1");

        assertFalse(decision.trialEligible());
        assertEquals("ip-limit", decision.reason());
    }
}
