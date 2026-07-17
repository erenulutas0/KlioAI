package com.ingilizce.calismaapp.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ingilizce.calismaapp.config.GooglePlaySubscriptionProperties;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.Map;

@Service
public class GooglePlayRtdnService {
    private static final Logger log = LoggerFactory.getLogger(GooglePlayRtdnService.class);

    private final ObjectMapper objectMapper;
    private final GooglePlaySubscriptionProperties googleProperties;
    private final GooglePlaySubscriptionReconciliationService reconciliationService;

    public GooglePlayRtdnService(
            ObjectMapper objectMapper,
            GooglePlaySubscriptionProperties googleProperties,
            GooglePlaySubscriptionReconciliationService reconciliationService) {
        this.objectMapper = objectMapper;
        this.googleProperties = googleProperties;
        this.reconciliationService = reconciliationService;
    }

    public RtdnProcessResult processPubSubPush(Map<String, Object> envelope) {
        try {
            JsonNode root = objectMapper.valueToTree(envelope);
            String encodedData = root.path("message").path("data").asText("");
            if (encodedData.isBlank()) {
                return RtdnProcessResult.ignored("missing-data");
            }

            String decodedData = new String(Base64.getDecoder().decode(encodedData), StandardCharsets.UTF_8);
            JsonNode notification = objectMapper.readTree(decodedData);

            String packageName = notification.path("packageName").asText("");
            if (!isExpectedPackage(packageName)) {
                log.warn("Ignoring Google RTDN for unexpected packageName={}", packageName);
                return RtdnProcessResult.ignored("package-mismatch");
            }

            JsonNode subscriptionNotification = notification.path("subscriptionNotification");
            if (!subscriptionNotification.isMissingNode() && !subscriptionNotification.isNull()) {
                return reconcilePurchaseToken(
                        subscriptionNotification.path("purchaseToken").asText(""),
                        subscriptionNotification.path("notificationType").asText(""));
            }

            JsonNode voidedPurchaseNotification = notification.path("voidedPurchaseNotification");
            if (!voidedPurchaseNotification.isMissingNode() && !voidedPurchaseNotification.isNull()) {
                return reconcilePurchaseToken(
                        voidedPurchaseNotification.path("purchaseToken").asText(""),
                        "voidedPurchaseNotification");
            }

            if (!notification.path("testNotification").isMissingNode()) {
                log.info("Received Google RTDN test notification");
                return RtdnProcessResult.ignored("test-notification");
            }

            return RtdnProcessResult.ignored("unsupported-notification");
        } catch (IllegalArgumentException ex) {
            log.warn("Invalid Google RTDN base64 payload", ex);
            return RtdnProcessResult.ignored("invalid-base64");
        } catch (Exception ex) {
            log.warn("Failed to process Google RTDN payload", ex);
            return RtdnProcessResult.ignored("invalid-payload");
        }
    }

    private RtdnProcessResult reconcilePurchaseToken(String purchaseToken, String notificationType) {
        if (purchaseToken == null || purchaseToken.isBlank()) {
            return RtdnProcessResult.ignored("missing-purchase-token");
        }

        boolean reconciled = reconciliationService.reconcilePurchaseToken(purchaseToken);
        log.info("Google RTDN processed notificationType={}, reconciled={}", notificationType, reconciled);
        return reconciled
                ? RtdnProcessResult.triggered("reconciled")
                : RtdnProcessResult.ignored("transaction-not-found-or-reconcile-failed");
    }

    private boolean isExpectedPackage(String packageName) {
        String expectedPackage = googleProperties.getPackageName();
        return expectedPackage == null
                || expectedPackage.isBlank()
                || expectedPackage.equals(packageName);
    }

    public record RtdnProcessResult(boolean triggered, String reason) {
        static RtdnProcessResult triggered(String reason) {
            return new RtdnProcessResult(true, reason);
        }

        static RtdnProcessResult ignored(String reason) {
            return new RtdnProcessResult(false, reason);
        }
    }
}
