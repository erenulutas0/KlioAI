package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.config.PushNotificationProperties;
import org.junit.jupiter.api.Test;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;

class FirebaseMessagingProviderTest {

    @Test
    void getMessagingShouldReturnEmptyWhenFirebaseIsDisabled() {
        PushNotificationProperties properties = new PushNotificationProperties();
        properties.getFirebase().setEnabled(false);
        FirebaseMessagingProvider provider = new FirebaseMessagingProvider(properties);

        assertFalse(provider.getMessaging().isPresent());

        Map<String, Object> status = provider.getStatus();
        assertEquals(false, status.get("enabled"));
        assertEquals(true, status.get("initializationAttempted"));
        assertEquals(false, status.get("initialized"));
        assertEquals("firebase-disabled", status.get("reason"));
        assertEquals("firebase-disabled", provider.getUnavailableReason());
    }

    @Test
    void getMessagingShouldReturnEmptyWhenCredentialsAreMissing() {
        PushNotificationProperties properties = new PushNotificationProperties();
        properties.getFirebase().setEnabled(true);
        FirebaseMessagingProvider provider = new FirebaseMessagingProvider(properties);

        assertFalse(provider.getMessaging().isPresent());
        assertEquals("credentials-missing", provider.getUnavailableReason());

        Map<String, Object> status = provider.getStatus();
        assertEquals(true, status.get("enabled"));
        assertEquals(false, status.get("serviceAccountFileConfigured"));
        assertEquals(false, status.get("serviceAccountJsonConfigured"));
        assertEquals(true, status.get("initializationAttempted"));
        assertEquals(false, status.get("initialized"));
    }

    @Test
    void getMessagingShouldReturnCachedEmptyAfterFailedInitializationAttempt() {
        PushNotificationProperties properties = new PushNotificationProperties();
        properties.getFirebase().setEnabled(true);
        FirebaseMessagingProvider provider = new FirebaseMessagingProvider(properties);

        assertFalse(provider.getMessaging().isPresent());
        properties.getFirebase().setServiceAccountJson("{not-valid-json");
        assertFalse(provider.getMessaging().isPresent());

        assertEquals("credentials-missing", provider.getUnavailableReason());
    }

    @Test
    void getMessagingShouldReportInitializationFailedForInvalidJsonCredentials() {
        PushNotificationProperties properties = new PushNotificationProperties();
        properties.getFirebase().setEnabled(true);
        properties.getFirebase().setServiceAccountJson("{not-valid-json");
        FirebaseMessagingProvider provider = new FirebaseMessagingProvider(properties);

        assertFalse(provider.getMessaging().isPresent());

        Map<String, Object> status = provider.getStatus();
        assertEquals(true, status.get("serviceAccountJsonConfigured"));
        assertEquals("initialization-failed", status.get("reason"));
    }

    @Test
    void getMessagingShouldReportInitializationFailedForUnreadableFileCredentials() {
        PushNotificationProperties properties = new PushNotificationProperties();
        properties.getFirebase().setEnabled(true);
        properties.getFirebase().setServiceAccountFile("C:/definitely/missing/klioai-service-account.json");
        FirebaseMessagingProvider provider = new FirebaseMessagingProvider(properties);

        assertFalse(provider.getMessaging().isPresent());

        Map<String, Object> status = provider.getStatus();
        assertEquals(true, status.get("serviceAccountFileConfigured"));
        assertEquals("initialization-failed", status.get("reason"));
    }
}
