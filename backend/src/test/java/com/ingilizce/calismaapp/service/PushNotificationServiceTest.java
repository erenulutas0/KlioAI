package com.ingilizce.calismaapp.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.ingilizce.calismaapp.config.PushNotificationProperties;
import com.ingilizce.calismaapp.entity.DevicePushToken;
import com.ingilizce.calismaapp.repository.DevicePushTokenRepository;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.springframework.data.domain.Pageable;

class PushNotificationServiceTest {

    @Test
    void sendDailyReminderIsNoopWhenFirebaseIsDisabled() {
        FirebaseMessagingProvider messagingProvider = mock(FirebaseMessagingProvider.class);
        DevicePushTokenRepository repository = mock(DevicePushTokenRepository.class);
        PushNotificationProperties properties = new PushNotificationProperties();
        properties.getDailyReminders().setMaxTokensPerRun(100);

        DevicePushToken token = new DevicePushToken();
        token.setUserId(4L);
        token.setToken("fcm-token");
        token.setEnabled(true);
        token.setDailyRemindersEnabled(true);

        when(repository.findByEnabledTrueAndDailyRemindersEnabledTrue(any(Pageable.class)))
                .thenReturn(List.of(token));
        when(messagingProvider.getMessaging()).thenReturn(Optional.empty());

        PushNotificationService service = new PushNotificationService(
                messagingProvider,
                repository,
                properties);
        Map<String, Object> response = service.sendDailyReminderToActiveDevices();

        assertFalse((Boolean) response.get("attempted"));
        assertEquals(1, response.get("target"));
        assertEquals(0, response.get("sent"));
        assertEquals("firebase-disabled", response.get("reason"));
    }
}
