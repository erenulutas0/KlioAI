package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.entity.DevicePushToken;
import com.ingilizce.calismaapp.repository.DevicePushTokenRepository;
import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class DevicePushTokenService {

    private static final int MAX_TOKEN_LENGTH = 4096;

    private final DevicePushTokenRepository repository;

    public DevicePushTokenService(DevicePushTokenRepository repository) {
        this.repository = repository;
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
        deviceToken.setEnabled(true);
        deviceToken.setDailyRemindersEnabled(Boolean.parseBoolean(
                clean(payload.get("dailyRemindersEnabled"), 8)));
        deviceToken.setLastSeenAt(LocalDateTime.now());

        DevicePushToken saved = repository.save(deviceToken);

        Map<String, Object> response = new LinkedHashMap<>();
        response.put("registered", true);
        response.put("id", saved.getId());
        response.put("lastSeenAt", saved.getLastSeenAt());
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
