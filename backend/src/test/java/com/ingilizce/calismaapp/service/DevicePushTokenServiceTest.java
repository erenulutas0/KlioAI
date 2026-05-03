package com.ingilizce.calismaapp.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.ingilizce.calismaapp.entity.DevicePushToken;
import com.ingilizce.calismaapp.repository.DevicePushTokenRepository;
import java.util.Map;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

class DevicePushTokenServiceTest {

    @Test
    void registerTokenCreatesEnabledTokenForUser() {
        DevicePushTokenRepository repository = mock(DevicePushTokenRepository.class);
        when(repository.findByToken("token-123")).thenReturn(Optional.empty());
        when(repository.save(any(DevicePushToken.class))).thenAnswer(invocation -> invocation.getArgument(0));

        DevicePushTokenService service = new DevicePushTokenService(repository);
        Map<String, Object> response = service.registerToken(7L, Map.of(
                "token", "token-123",
                "platform", "android",
                "deviceId", "device-1",
                "locale", "en",
                "dailyRemindersEnabled", "true"));

        ArgumentCaptor<DevicePushToken> captor = ArgumentCaptor.forClass(DevicePushToken.class);
        verify(repository).save(captor.capture());
        DevicePushToken saved = captor.getValue();

        assertTrue((Boolean) response.get("registered"));
        assertEquals(7L, saved.getUserId());
        assertEquals("token-123", saved.getToken());
        assertEquals("android", saved.getPlatform());
        assertEquals("device-1", saved.getDeviceId());
        assertEquals("en", saved.getLocale());
        assertTrue(saved.isEnabled());
        assertTrue(saved.isDailyRemindersEnabled());
    }

    @Test
    void registerTokenRejectsMissingToken() {
        DevicePushTokenRepository repository = mock(DevicePushTokenRepository.class);
        DevicePushTokenService service = new DevicePushTokenService(repository);

        assertThrows(
                IllegalArgumentException.class,
                () -> service.registerToken(7L, Map.of()));
    }
}
