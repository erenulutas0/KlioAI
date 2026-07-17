package com.ingilizce.calismaapp.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.ingilizce.calismaapp.config.PushNotificationProperties;
import com.ingilizce.calismaapp.entity.DevicePushToken;
import com.ingilizce.calismaapp.entity.NotificationDeliveryLog;
import com.ingilizce.calismaapp.repository.NotificationDeliveryLogRepository;
import com.ingilizce.calismaapp.repository.DevicePushTokenRepository;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.data.domain.Pageable;
import org.springframework.test.util.ReflectionTestUtils;

class PushNotificationServiceTest {

    @Test
    void sendDailyReminderIsNoopWhenFirebaseIsDisabled() {
        FirebaseMessagingProvider messagingProvider = mock(FirebaseMessagingProvider.class);
        DevicePushTokenRepository repository = mock(DevicePushTokenRepository.class);
        NotificationDeliveryLogRepository deliveryLogRepository = mock(NotificationDeliveryLogRepository.class);
        PushNotificationProperties properties = new PushNotificationProperties();
        properties.getDailyReminders().setMaxTokensPerRun(100);

        DevicePushToken token = new DevicePushToken();
        ReflectionTestUtils.setField(token, "id", 19L);
        token.setUserId(4L);
        token.setToken("fcm-token");
        token.setEnabled(true);
        token.setDailyRemindersEnabled(true);

        when(repository.findByEnabledTrueAndDailyRemindersEnabledTrue(any(Pageable.class)))
                .thenReturn(List.of(token));
        when(messagingProvider.getMessaging()).thenReturn(Optional.empty());
        when(messagingProvider.getUnavailableReason()).thenReturn("firebase-disabled");

        PushNotificationService service = new PushNotificationService(
                messagingProvider,
                repository,
                deliveryLogRepository,
                properties);
        Map<String, Object> response = service.sendDailyReminderToActiveDevices();

        assertFalse((Boolean) response.get("attempted"));
        assertEquals(1, response.get("target"));
        assertEquals(0, response.get("sent"));
        assertEquals("firebase-disabled", response.get("reason"));
        verify(deliveryLogRepository).save(any(NotificationDeliveryLog.class));
    }

    @Test
    void sendDailyReminderClampsBatchSizeAndUsesSafeReminderText() {
        FirebaseMessagingProvider messagingProvider = mock(FirebaseMessagingProvider.class);
        DevicePushTokenRepository repository = mock(DevicePushTokenRepository.class);
        NotificationDeliveryLogRepository deliveryLogRepository = mock(NotificationDeliveryLogRepository.class);
        PushNotificationProperties properties = new PushNotificationProperties();
        properties.getDailyReminders().setMaxTokensPerRun(999);
        properties.getDailyReminders().setTitle("  ");
        properties.getDailyReminders().setBody(null);

        DevicePushToken token = token(31L, 8L, "daily-token");
        when(repository.findByEnabledTrueAndDailyRemindersEnabledTrue(any(Pageable.class)))
                .thenReturn(List.of(token));
        when(messagingProvider.getMessaging()).thenReturn(Optional.empty());
        when(messagingProvider.getUnavailableReason()).thenReturn("credentials-missing");

        PushNotificationService service = new PushNotificationService(
                messagingProvider,
                repository,
                deliveryLogRepository,
                properties);
        Map<String, Object> response = service.sendDailyReminderToActiveDevices();

        assertFalse((Boolean) response.get("attempted"));
        assertEquals(1, response.get("target"));
        assertEquals("credentials-missing", response.get("reason"));

        ArgumentCaptor<Pageable> pageableCaptor = ArgumentCaptor.forClass(Pageable.class);
        verify(repository).findByEnabledTrueAndDailyRemindersEnabledTrue(pageableCaptor.capture());
        assertEquals(500, pageableCaptor.getValue().getPageSize());

        ArgumentCaptor<NotificationDeliveryLog> logCaptor =
                ArgumentCaptor.forClass(NotificationDeliveryLog.class);
        verify(deliveryLogRepository).save(logCaptor.capture());
        NotificationDeliveryLog log = logCaptor.getValue();
        assertEquals(8L, log.getUserId());
        assertEquals(31L, log.getDevicePushTokenId());
        assertEquals("daily_reminder", log.getType());
        assertEquals("SKIPPED", log.getStatus());
        assertEquals("credentials-missing", log.getProviderErrorCode());
        assertNotNull(log.getTitleHash());
        assertNotNull(log.getBodyHash());
    }

    @Test
    void sendDailyReminderUsesAtLeastOneTokenWhenConfiguredLimitIsInvalid() {
        FirebaseMessagingProvider messagingProvider = mock(FirebaseMessagingProvider.class);
        DevicePushTokenRepository repository = mock(DevicePushTokenRepository.class);
        NotificationDeliveryLogRepository deliveryLogRepository = mock(NotificationDeliveryLogRepository.class);
        PushNotificationProperties properties = new PushNotificationProperties();
        properties.getDailyReminders().setMaxTokensPerRun(0);

        when(repository.findByEnabledTrueAndDailyRemindersEnabledTrue(any(Pageable.class)))
                .thenReturn(List.of());
        when(messagingProvider.getMessaging()).thenReturn(Optional.empty());
        when(messagingProvider.getUnavailableReason()).thenReturn("firebase-disabled");

        PushNotificationService service = new PushNotificationService(
                messagingProvider,
                repository,
                deliveryLogRepository,
                properties);
        Map<String, Object> response = service.sendDailyReminderToActiveDevices();

        assertEquals(0, response.get("target"));
        ArgumentCaptor<Pageable> pageableCaptor = ArgumentCaptor.forClass(Pageable.class);
        verify(repository).findByEnabledTrueAndDailyRemindersEnabledTrue(pageableCaptor.capture());
        assertEquals(1, pageableCaptor.getValue().getPageSize());
        verify(deliveryLogRepository, never()).save(any());
    }

    @Test
    void sendToUserRejectsMissingUserContext() {
        FirebaseMessagingProvider messagingProvider = mock(FirebaseMessagingProvider.class);
        DevicePushTokenRepository repository = mock(DevicePushTokenRepository.class);
        NotificationDeliveryLogRepository deliveryLogRepository = mock(NotificationDeliveryLogRepository.class);

        PushNotificationService service = new PushNotificationService(
                messagingProvider,
                repository,
                deliveryLogRepository,
                new PushNotificationProperties());

        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class,
                () -> service.sendToUser(0L, "Title", "Body", Map.of()));

        assertEquals("Missing user context", ex.getMessage());
        verify(repository, never()).findByUserIdAndEnabledTrue(any());
    }

    @Test
    void sendToUserWhenFirebaseUnavailableShouldLogSkippedWithSanitizedType() {
        FirebaseMessagingProvider messagingProvider = mock(FirebaseMessagingProvider.class);
        DevicePushTokenRepository repository = mock(DevicePushTokenRepository.class);
        NotificationDeliveryLogRepository deliveryLogRepository = mock(NotificationDeliveryLogRepository.class);
        DevicePushToken token = token(44L, 9L, "user-token");

        when(repository.findByUserIdAndEnabledTrue(9L)).thenReturn(List.of(token));
        when(messagingProvider.getMessaging()).thenReturn(Optional.empty());
        when(messagingProvider.getUnavailableReason()).thenReturn("initialization-failed");

        PushNotificationService service = new PushNotificationService(
                messagingProvider,
                repository,
                deliveryLogRepository,
                new PushNotificationProperties());
        String longType = "  " + "x".repeat(80) + "  ";
        Map<String, Object> response = service.sendToUser(
                9L,
                " ",
                null,
                Map.of("type", longType, "ignored", ""));

        assertFalse((Boolean) response.get("attempted"));
        assertEquals(1, response.get("target"));
        assertEquals("initialization-failed", response.get("reason"));

        ArgumentCaptor<NotificationDeliveryLog> logCaptor =
                ArgumentCaptor.forClass(NotificationDeliveryLog.class);
        verify(deliveryLogRepository).save(logCaptor.capture());
        NotificationDeliveryLog log = logCaptor.getValue();
        assertEquals("x".repeat(64), log.getType());
        assertNull(log.getTitleHash());
        assertNull(log.getBodyHash());
        assertEquals("SKIPPED", log.getStatus());
    }

    @Test
    void sendToUserWhenFirebaseUnavailableShouldUseUnknownTypeForMissingData() {
        FirebaseMessagingProvider messagingProvider = mock(FirebaseMessagingProvider.class);
        DevicePushTokenRepository repository = mock(DevicePushTokenRepository.class);
        NotificationDeliveryLogRepository deliveryLogRepository = mock(NotificationDeliveryLogRepository.class);
        DevicePushToken token = token(45L, 10L, "user-token-two");

        when(repository.findByUserIdAndEnabledTrue(10L)).thenReturn(List.of(token));
        when(messagingProvider.getMessaging()).thenReturn(Optional.empty());
        when(messagingProvider.getUnavailableReason()).thenReturn("firebase-disabled");

        PushNotificationService service = new PushNotificationService(
                messagingProvider,
                repository,
                deliveryLogRepository,
                new PushNotificationProperties());
        service.sendToUser(10L, "Title", "Body", null);

        ArgumentCaptor<NotificationDeliveryLog> logCaptor =
                ArgumentCaptor.forClass(NotificationDeliveryLog.class);
        verify(deliveryLogRepository).save(logCaptor.capture());
        assertEquals("UNKNOWN", logCaptor.getValue().getType());
    }

    @Test
    void sendToUserShouldStillReturnWhenDeliveryLogSaveFails() {
        FirebaseMessagingProvider messagingProvider = mock(FirebaseMessagingProvider.class);
        DevicePushTokenRepository repository = mock(DevicePushTokenRepository.class);
        NotificationDeliveryLogRepository deliveryLogRepository = mock(NotificationDeliveryLogRepository.class);
        DevicePushToken token = token(46L, 11L, "user-token-three");

        when(repository.findByUserIdAndEnabledTrue(11L)).thenReturn(List.of(token));
        when(messagingProvider.getMessaging()).thenReturn(Optional.empty());
        when(messagingProvider.getUnavailableReason()).thenReturn("firebase-disabled");
        doThrow(new RuntimeException("db temporarily unavailable"))
                .when(deliveryLogRepository)
                .save(any(NotificationDeliveryLog.class));

        PushNotificationService service = new PushNotificationService(
                messagingProvider,
                repository,
                deliveryLogRepository,
                new PushNotificationProperties());

        Map<String, Object> response = service.sendToUser(11L, "Title", "Body", Map.of("type", "manual_test"));

        assertFalse((Boolean) response.get("attempted"));
        assertEquals(1, response.get("target"));
        assertEquals("firebase-disabled", response.get("reason"));
    }

    @Test
    void getPushStatusDelegatesToProvider() {
        FirebaseMessagingProvider messagingProvider = mock(FirebaseMessagingProvider.class);
        DevicePushTokenRepository repository = mock(DevicePushTokenRepository.class);
        NotificationDeliveryLogRepository deliveryLogRepository = mock(NotificationDeliveryLogRepository.class);
        when(messagingProvider.getStatus()).thenReturn(Map.of("initialized", false, "reason", "firebase-disabled"));

        PushNotificationService service = new PushNotificationService(
                messagingProvider,
                repository,
                deliveryLogRepository,
                new PushNotificationProperties());

        Map<String, Object> status = service.getPushStatus();

        assertEquals(false, status.get("initialized"));
        assertEquals("firebase-disabled", status.get("reason"));
    }

    private DevicePushToken token(Long id, Long userId, String value) {
        DevicePushToken token = new DevicePushToken();
        ReflectionTestUtils.setField(token, "id", id);
        token.setUserId(userId);
        token.setToken(value);
        token.setEnabled(true);
        token.setDailyRemindersEnabled(true);
        return token;
    }
}
