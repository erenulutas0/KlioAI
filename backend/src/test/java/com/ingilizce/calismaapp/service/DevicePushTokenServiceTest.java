package com.ingilizce.calismaapp.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.when;

import com.ingilizce.calismaapp.entity.DevicePushToken;
import com.ingilizce.calismaapp.entity.NotificationPreference;
import com.ingilizce.calismaapp.repository.DevicePushTokenRepository;
import com.ingilizce.calismaapp.repository.NotificationPreferenceRepository;
import java.util.Map;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

class DevicePushTokenServiceTest {

    @Test
    void registerTokenCreatesEnabledTokenForUser() {
        DevicePushTokenRepository repository = mock(DevicePushTokenRepository.class);
        NotificationPreferenceRepository preferenceRepository = mock(NotificationPreferenceRepository.class);
        when(repository.findByToken("token-123")).thenReturn(Optional.empty());
        when(repository.save(any(DevicePushToken.class))).thenAnswer(invocation -> invocation.getArgument(0));
        when(preferenceRepository.findByUserId(7L)).thenReturn(Optional.empty());
        when(preferenceRepository.save(any(NotificationPreference.class))).thenAnswer(invocation -> invocation.getArgument(0));

        DevicePushTokenService service = new DevicePushTokenService(repository, preferenceRepository);
        Map<String, Object> response = service.registerToken(7L, Map.of(
                "token", "token-123",
                "platform", "android",
                "deviceId", "device-1",
                "locale", "en",
                "timezone", "Europe/Istanbul",
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
        assertEquals("Europe/Istanbul", saved.getTimezone());
        assertTrue(saved.isEnabled());
        assertTrue(saved.isDailyRemindersEnabled());

        ArgumentCaptor<NotificationPreference> preferenceCaptor = ArgumentCaptor.forClass(NotificationPreference.class);
        verify(preferenceRepository).save(preferenceCaptor.capture());
        assertEquals(7L, preferenceCaptor.getValue().getUserId());
        assertTrue(preferenceCaptor.getValue().isDailyRemindersEnabled());
        assertEquals("Europe/Istanbul", preferenceCaptor.getValue().getTimezone());
    }

    @Test
    void registerTokenRejectsMissingToken() {
        DevicePushTokenRepository repository = mock(DevicePushTokenRepository.class);
        NotificationPreferenceRepository preferenceRepository = mock(NotificationPreferenceRepository.class);
        DevicePushTokenService service = new DevicePushTokenService(repository, preferenceRepository);

        assertThrows(
                IllegalArgumentException.class,
                () -> service.registerToken(7L, Map.of()));
    }

    @Test
    void registerTokenUpdatesExistingTokenAndTrimsOversizedMetadata() {
        DevicePushTokenRepository repository = mock(DevicePushTokenRepository.class);
        NotificationPreferenceRepository preferenceRepository = mock(NotificationPreferenceRepository.class);
        DevicePushToken existing = new DevicePushToken();
        when(repository.findByToken("token-123")).thenReturn(Optional.of(existing));
        when(repository.save(any(DevicePushToken.class))).thenAnswer(invocation -> invocation.getArgument(0));
        when(preferenceRepository.findByUserId(7L)).thenReturn(Optional.empty());
        when(preferenceRepository.save(any(NotificationPreference.class))).thenAnswer(invocation -> invocation.getArgument(0));

        DevicePushTokenService service = new DevicePushTokenService(repository, preferenceRepository);
        String longPlatform = "x".repeat(40);
        service.registerToken(7L, Map.of(
                "token", "  token-123  ",
                "platform", longPlatform,
                "timezone", "  ",
                "dailyRemindersEnabled", "false"));

        ArgumentCaptor<DevicePushToken> captor = ArgumentCaptor.forClass(DevicePushToken.class);
        verify(repository).save(captor.capture());
        assertEquals(existing, captor.getValue());
        assertEquals(7L, existing.getUserId());
        assertEquals("token-123", existing.getToken());
        assertEquals(32, existing.getPlatform().length());
        assertFalse(existing.isDailyRemindersEnabled());

        ArgumentCaptor<NotificationPreference> preferenceCaptor = ArgumentCaptor.forClass(NotificationPreference.class);
        verify(preferenceRepository).save(preferenceCaptor.capture());
        assertEquals("Europe/Istanbul", preferenceCaptor.getValue().getTimezone());
    }

    @Test
    void updatePreferencesPersistsCategoryToggles() {
        DevicePushTokenRepository repository = mock(DevicePushTokenRepository.class);
        NotificationPreferenceRepository preferenceRepository = mock(NotificationPreferenceRepository.class);
        NotificationPreference existing = new NotificationPreference();
        existing.setUserId(7L);
        existing.setDailyRemindersEnabled(false);
        when(preferenceRepository.findByUserId(7L)).thenReturn(Optional.of(existing));
        when(preferenceRepository.save(any(NotificationPreference.class))).thenAnswer(invocation -> invocation.getArgument(0));

        DevicePushTokenService service = new DevicePushTokenService(repository, preferenceRepository);
        Map<String, Object> response = service.updatePreferences(7L, Map.of(
                "dailyRemindersEnabled", true,
                "streakGuardEnabled", false,
                "productUpdatesEnabled", true,
                "subscriptionAlertsEnabled", true,
                "socialEnabled", false,
                "timezone", "Europe/Istanbul"));

        verify(preferenceRepository).findByUserId(eq(7L));
        ArgumentCaptor<NotificationPreference> preferenceCaptor = ArgumentCaptor.forClass(NotificationPreference.class);
        verify(preferenceRepository).save(preferenceCaptor.capture());
        NotificationPreference saved = preferenceCaptor.getValue();
        assertTrue(saved.isDailyRemindersEnabled());
        assertEquals(false, saved.isStreakGuardEnabled());
        assertTrue(saved.isProductUpdatesEnabled());
        assertEquals(false, saved.isSocialEnabled());
        assertEquals("Europe/Istanbul", saved.getTimezone());
        assertEquals(true, response.get("dailyRemindersEnabled"));
        assertEquals(false, response.get("streakGuardEnabled"));
    }

    @Test
    void getPreferencesReturnsExistingOrDefaultPayload() {
        DevicePushTokenRepository repository = mock(DevicePushTokenRepository.class);
        NotificationPreferenceRepository preferenceRepository = mock(NotificationPreferenceRepository.class);
        NotificationPreference existing = new NotificationPreference();
        existing.setUserId(7L);
        existing.setDailyRemindersEnabled(true);
        existing.setTimezone("Europe/London");
        when(preferenceRepository.findByUserId(7L)).thenReturn(Optional.of(existing));
        when(preferenceRepository.findByUserId(8L)).thenReturn(Optional.empty());

        DevicePushTokenService service = new DevicePushTokenService(repository, preferenceRepository);

        assertEquals("Europe/London", service.getPreferences(7L).get("timezone"));
        assertEquals("Europe/Istanbul", service.getPreferences(8L).get("timezone"));
        assertThrows(IllegalArgumentException.class, () -> service.getPreferences(0L));
    }

    @Test
    void updatePreferencesAcceptsStringBooleansAndQuietHours() {
        DevicePushTokenRepository repository = mock(DevicePushTokenRepository.class);
        NotificationPreferenceRepository preferenceRepository = mock(NotificationPreferenceRepository.class);
        when(preferenceRepository.findByUserId(7L)).thenReturn(Optional.empty());
        when(preferenceRepository.save(any(NotificationPreference.class))).thenAnswer(invocation -> invocation.getArgument(0));

        DevicePushTokenService service = new DevicePushTokenService(repository, preferenceRepository);
        Map<String, Object> response = service.updatePreferences(7L, Map.of(
                "quietHoursEnabled", "false",
                "quietHoursStartLocal", "23:00",
                "quietHoursEndLocal", "07:30",
                "timezone", "America/New_York"));

        assertEquals(false, response.get("quietHoursEnabled"));
        assertEquals("23:00", response.get("quietHoursStartLocal"));
        assertEquals("07:30", response.get("quietHoursEndLocal"));
        assertEquals("America/New_York", response.get("timezone"));
    }

    @Test
    void disableTokenDisablesMatchingTokenOnly() {
        DevicePushTokenRepository repository = mock(DevicePushTokenRepository.class);
        NotificationPreferenceRepository preferenceRepository = mock(NotificationPreferenceRepository.class);
        DevicePushToken existing = new DevicePushToken();
        existing.setEnabled(true);
        when(repository.findByUserIdAndToken(7L, "token-123")).thenReturn(Optional.of(existing));
        when(repository.save(any(DevicePushToken.class))).thenAnswer(invocation -> invocation.getArgument(0));

        DevicePushTokenService service = new DevicePushTokenService(repository, preferenceRepository);
        Map<String, Object> response = service.disableToken(7L, "token-123");

        assertEquals(true, response.get("disabled"));
        assertFalse(existing.isEnabled());
        verify(repository).save(existing);
    }

    @Test
    void disableTokenReturnsFalseWhenTokenIsUnknown() {
        DevicePushTokenRepository repository = mock(DevicePushTokenRepository.class);
        NotificationPreferenceRepository preferenceRepository = mock(NotificationPreferenceRepository.class);
        when(repository.findByUserIdAndToken(7L, "missing-token")).thenReturn(Optional.empty());

        DevicePushTokenService service = new DevicePushTokenService(repository, preferenceRepository);
        Map<String, Object> response = service.disableToken(7L, "missing-token");

        assertEquals(false, response.get("disabled"));
        verify(repository, never()).save(any());
        assertThrows(IllegalArgumentException.class, () -> service.disableToken(7L, " "));
    }
}
