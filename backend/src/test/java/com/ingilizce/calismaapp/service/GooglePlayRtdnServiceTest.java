package com.ingilizce.calismaapp.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ingilizce.calismaapp.config.GooglePlaySubscriptionProperties;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class GooglePlayRtdnServiceTest {

    @Mock
    private GooglePlaySubscriptionReconciliationService reconciliationService;

    private GooglePlayRtdnService rtdnService;

    @BeforeEach
    void setUp() {
        GooglePlaySubscriptionProperties googleProps = new GooglePlaySubscriptionProperties();
        googleProps.setPackageName("com.VocabMaster");
        rtdnService = new GooglePlayRtdnService(new ObjectMapper(), googleProps, reconciliationService);
    }

    @Test
    void processPubSubPush_shouldReconcileSubscriptionPurchaseToken() {
        when(reconciliationService.reconcilePurchaseToken("purchase-token-1")).thenReturn(true);

        GooglePlayRtdnService.RtdnProcessResult result = rtdnService.processPubSubPush(envelope("""
                {
                  "version": "1.0",
                  "packageName": "com.VocabMaster",
                  "eventTimeMillis": "1770000000000",
                  "subscriptionNotification": {
                    "version": "1.0",
                    "notificationType": 3,
                    "purchaseToken": "purchase-token-1",
                    "subscriptionId": "pro_monthly_subscription"
                  }
                }
                """));

        assertTrue(result.triggered());
        verify(reconciliationService).reconcilePurchaseToken("purchase-token-1");
    }

    @Test
    void processPubSubPush_shouldIgnoreUnexpectedPackage() {
        GooglePlayRtdnService.RtdnProcessResult result = rtdnService.processPubSubPush(envelope("""
                {
                  "version": "1.0",
                  "packageName": "com.other.app",
                  "subscriptionNotification": {
                    "purchaseToken": "purchase-token-1"
                  }
                }
                """));

        assertFalse(result.triggered());
        verifyNoInteractions(reconciliationService);
    }

    @Test
    void processPubSubPush_shouldAckTestNotificationWithoutReconcile() {
        GooglePlayRtdnService.RtdnProcessResult result = rtdnService.processPubSubPush(envelope("""
                {
                  "version": "1.0",
                  "packageName": "com.VocabMaster",
                  "testNotification": {
                    "version": "1.0"
                  }
                }
                """));

        assertFalse(result.triggered());
        verifyNoInteractions(reconciliationService);
    }

    private Map<String, Object> envelope(String notificationJson) {
        String encoded = Base64.getEncoder()
                .encodeToString(notificationJson.getBytes(StandardCharsets.UTF_8));
        return Map.of("message", Map.of("data", encoded, "messageId", "msg-1"));
    }
}
