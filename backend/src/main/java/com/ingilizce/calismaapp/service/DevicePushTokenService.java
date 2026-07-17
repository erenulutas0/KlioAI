package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.entity.DevicePushToken;
import com.ingilizce.calismaapp.entity.NotificationPreference;
import com.ingilizce.calismaapp.repository.DevicePushTokenRepository;
import com.ingilizce.calismaapp.repository.NotificationPreferenceRepository;
import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class DevicePushTokenService {

    private static final int MAX_TOKEN_LENGTH = 4096;

    private final DevicePushTokenRepository repository;
    private final NotificationPreferenceRepository preferenceRepository;

    public DevicePushTokenService(
            DevicePushTokenRepository repository,
            NotificationPreferenceRepository preferenceRepository) {
        this.repository = repository;
        this.preferenceRepository = preferenceRepository;
    }

    @Transactional
    public Map<String, Object> registerToken(Long userId, Map<String, String> payload) {
        if (userId == null || userId <= 0) {
            throw new IllegalArgumentException("Missing user context");
        }
        if (payload == null) {
            throw new IllegalArgumentException("Missing push token payload");
        }

        String token = clean(payload.get("token"), MAX_TOKEN_LENGTH);
        if (token == null || token.isBlank()) {
            throw new IllegalArgumentException("Missing push token");
        }

        DevicePushToken deviceToken = repository.findByToken(token)
                .orElseGet(DevicePushToken::new);
        deviceToken.setUserId(userId);
        deviceToken.setToken(token);
        deviceToken.setPlatform(clean(payload.get("platform"), 32));
        deviceToken.setDeviceId(clean(payload.get("deviceId"), 128));
        deviceToken.setAppVersion(clean(payload.get("appVersion"), 64));
        deviceToken.setLocale(clean(payload.get("locale"), 32));
        deviceToken.setTimezone(clean(payload.get("timezone"), 64));
        deviceToken.setEnabled(true);
        boolean dailyRemindersEnabled = Boolean.parseBoolean(
                clean(payload.get("dailyRemindersEnabled"), 8));
        deviceToken.setDailyRemindersEnabled(dailyRemindersEnabled);
        deviceToken.setLastSeenAt(LocalDateTime.now());

        DevicePushToken saved = repository.save(deviceToken);
        upsertPreferences(userId, saved, dailyRemindersEnabled);

        Map<String, Object> response = new LinkedHashMap<>();
        response.put("registered", true);
        response.put("id", saved.getId());
        response.put("lastSeenAt", saved.getLastSeenAt());
        return response;
    }

    private void upsertPreferences(Long userId, DevicePushToken token, boolean dailyRemindersEnabled) {
        NotificationPreference preference = preferenceRepository.findByUserId(userId)
                .orElseGet(NotificationPreference::new);
        preference.setUserId(userId);
        preference.setDailyRemindersEnabled(dailyRemindersEnabled);
        String timezone = clean(token.getTimezone(), 64);
        if (timezone != null) {
            preference.setTimezone(timezone);
        }
        preferenceRepository.save(preference);
    }

    @Transactional(readOnly = true)
    public Map<String, Object> getPreferences(Long userId) {
        if (userId == null || userId <= 0) {
            throw new IllegalArgumentException("Missing user context");
        }
        NotificationPreference preference = preferenceRepository.findByUserId(userId)
                .orElseGet(() -> defaultPreference(userId));
        return preferencePayload(preference);
    }

    @Transactional
    public Map<String, Object> updatePreferences(Long userId, Map<String, Object> payload) {
        if (userId == null || userId <= 0) {
            throw new IllegalArgumentException("Missing user context");
        }
        if (payload == null) {
            throw new IllegalArgumentException("Missing notification preference payload");
        }

        NotificationPreference preference = preferenceRepository.findByUserId(userId)
                .orElseGet(() -> defaultPreference(userId));
        applyBoolean(payload, "dailyRemindersEnabled", preference::setDailyRemindersEnabled);
        applyBoolean(payload, "streakGuardEnabled", preference::setStreakGuardEnabled);
        applyBoolean(payload, "productUpdatesEnabled", preference::setProductUpdatesEnabled);
        applyBoolean(payload, "subscriptionAlertsEnabled", preference::setSubscriptionAlertsEnabled);
        applyBoolean(payload, "socialEnabled", preference::setSocialEnabled);
        applyBoolean(payload, "quietHoursEnabled", preference::setQuietHoursEnabled);

        String timezone = clean(asString(payload.get("timezone")), 64);
        if (timezone != null) {
            preference.setTimezone(timezone);
        }
        String quietStart = clean(asString(payload.get("quietHoursStartLocal")), 5);
        if (quietStart != null) {
            preference.setQuietHoursStartLocal(quietStart);
        }
        String quietEnd = clean(asString(payload.get("quietHoursEndLocal")), 5);
        if (quietEnd != null) {
            preference.setQuietHoursEndLocal(quietEnd);
        }

        NotificationPreference saved = preferenceRepository.save(preference);
        return preferencePayload(saved);
    }

    private NotificationPreference defaultPreference(Long userId) {
        NotificationPreference preference = new NotificationPreference();
        preference.setUserId(userId);
        return preference;
    }

    private void applyBoolean(Map<String, Object> payload, String key, java.util.function.Consumer<Boolean> setter) {
        if (!payload.containsKey(key)) {
            return;
        }
        Object value = payload.get(key);
        if (value instanceof Boolean bool) {
            setter.accept(bool);
            return;
        }
        if (value != null) {
            setter.accept(Boolean.parseBoolean(value.toString()));
        }
    }

    private String asString(Object value) {
        return value == null ? null : value.toString();
    }

    private Map<String, Object> preferencePayload(NotificationPreference preference) {
        Map<String, Object> response = new LinkedHashMap<>();
        response.put("dailyRemindersEnabled", preference.isDailyRemindersEnabled());
        response.put("streakGuardEnabled", preference.isStreakGuardEnabled());
        response.put("productUpdatesEnabled", preference.isProductUpdatesEnabled());
        response.put("subscriptionAlertsEnabled", preference.isSubscriptionAlertsEnabled());
        response.put("socialEnabled", preference.isSocialEnabled());
        response.put("quietHoursEnabled", preference.isQuietHoursEnabled());
        response.put("quietHoursStartLocal", preference.getQuietHoursStartLocal());
        response.put("quietHoursEndLocal", preference.getQuietHoursEndLocal());
        response.put("timezone", preference.getTimezone());
        return response;
    }

    @Transactional
    public Map<String, Object> disableToken(Long userId, String token) {
        if (userId == null || userId <= 0 || token == null || token.isBlank()) {
            throw new IllegalArgumentException("Missing push token context");
        }

        boolean disabled = repository.findByUserIdAndToken(userId, token)
                .map(existing -> {
                    existing.setEnabled(false);
                    existing.setLastSeenAt(LocalDateTime.now());
                    repository.save(existing);
                    return true;
                })
                .orElse(false);

        Map<String, Object> response = new LinkedHashMap<>();
        response.put("disabled", disabled);
        return response;
    }

    private String clean(String value, int maxLength) {
        if (value == null) {
            return null;
        }
        String trimmed = value.trim();
        if (trimmed.isEmpty()) {
            return null;
        }
        return trimmed.length() <= maxLength ? trimmed : trimmed.substring(0, maxLength);
    }
}
