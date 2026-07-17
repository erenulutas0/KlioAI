package com.ingilizce.calismaapp.service;

import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.FirebaseMessagingException;
import com.google.firebase.messaging.Message;
import com.google.firebase.messaging.Notification;
import com.ingilizce.calismaapp.config.PushNotificationProperties;
import com.ingilizce.calismaapp.entity.DevicePushToken;
import com.ingilizce.calismaapp.entity.NotificationDeliveryLog;
import com.ingilizce.calismaapp.repository.NotificationDeliveryLogRepository;
import com.ingilizce.calismaapp.repository.DevicePushTokenRepository;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class PushNotificationService {

    private static final Logger logger = LoggerFactory.getLogger(PushNotificationService.class);

    private final FirebaseMessagingProvider messagingProvider;
    private final DevicePushTokenRepository tokenRepository;
    private final NotificationDeliveryLogRepository deliveryLogRepository;
    private final PushNotificationProperties properties;

    public PushNotificationService(
            FirebaseMessagingProvider messagingProvider,
            DevicePushTokenRepository tokenRepository,
            NotificationDeliveryLogRepository deliveryLogRepository,
            PushNotificationProperties properties) {
        this.messagingProvider = messagingProvider;
        this.tokenRepository = tokenRepository;
        this.deliveryLogRepository = deliveryLogRepository;
        this.properties = properties;
    }

    @Transactional
    public Map<String, Object> sendDailyReminderToActiveDevices() {
        PushNotificationProperties.DailyReminders reminder = properties.getDailyReminders();
        int limit = Math.max(1, Math.min(reminder.getMaxTokensPerRun(), 500));
        List<DevicePushToken> tokens =
                tokenRepository.findByEnabledTrueAndDailyRemindersEnabledTrue(PageRequest.of(0, limit));

        return sendToTokens(
                tokens,
                safe(reminder.getTitle(), "KlioAI"),
                safe(reminder.getBody(), "A quick practice session is ready for today."),
                Map.of("type", "daily_reminder"));
    }

    @Transactional
    public Map<String, Object> sendToUser(
            Long userId,
            String title,
            String body,
            Map<String, String> data) {
        if (userId == null || userId <= 0) {
            throw new IllegalArgumentException("Missing user context");
        }
        List<DevicePushToken> tokens = tokenRepository.findByUserIdAndEnabledTrue(userId);
        return sendToTokens(tokens, title, body, data);
    }

    private Map<String, Object> sendToTokens(
            List<DevicePushToken> tokens,
            String title,
            String body,
            Map<String, String> data) {
        Optional<FirebaseMessaging> messaging = messagingProvider.getMessaging();
        if (messaging.isEmpty()) {
            String reason = messagingProvider.getUnavailableReason();
            for (DevicePushToken token : tokens) {
                saveDeliveryLog(token, title, body, data, "SKIPPED", null, reason);
            }
            return response(false, tokens.size(), 0, 0, reason);
        }

        int sent = 0;
        int failed = 0;
        for (DevicePushToken token : tokens) {
            try {
                String providerMessageId = messaging.get().send(buildMessage(token.getToken(), title, body, data));
                saveDeliveryLog(token, title, body, data, "SENT", providerMessageId, null);
                sent++;
            } catch (FirebaseMessagingException ex) {
                failed++;
                handleSendFailure(token, ex);
                saveDeliveryLog(token, title, body, data, "FAILED", null, providerErrorCode(ex));
            } catch (RuntimeException ex) {
                failed++;
                logger.warn("Push notification send failed for token id={}", token.getId(), ex);
                saveDeliveryLog(token, title, body, data, "FAILED", null, ex.getClass().getSimpleName());
            }
        }

        logger.info("Push notification batch completed: target={} sent={} failed={}", tokens.size(), sent, failed);
        return response(true, tokens.size(), sent, failed, null);
    }

    private Message buildMessage(
            String token,
            String title,
            String body,
            Map<String, String> data) {
        Message.Builder builder = Message.builder()
                .setToken(token)
                .setNotification(Notification.builder()
                        .setTitle(title)
                        .setBody(body)
                        .build());

        if (data != null) {
            data.forEach((key, value) -> {
                if (key != null && value != null && !key.isBlank() && !value.isBlank()) {
                    builder.putData(key, value);
                }
            });
        }
        builder.putData("click_action", "FLUTTER_NOTIFICATION_CLICK");
        return builder.build();
    }

    private void handleSendFailure(DevicePushToken token, FirebaseMessagingException ex) {
        String code = providerErrorCode(ex);
        if ("UNREGISTERED".equals(code) || "INVALID_ARGUMENT".equals(code)) {
            token.setEnabled(false);
            tokenRepository.save(token);
            logger.info("Disabled invalid push token id={} errorCode={}", token.getId(), code);
            return;
        }
        logger.warn("Push notification send failed for token id={} errorCode={}", token.getId(), code, ex);
    }

    private void saveDeliveryLog(
            DevicePushToken token,
            String title,
            String body,
            Map<String, String> data,
            String status,
            String providerMessageId,
            String providerErrorCode) {
        try {
            NotificationDeliveryLog log = new NotificationDeliveryLog();
            log.setUserId(token.getUserId());
            log.setDevicePushTokenId(token.getId());
            log.setType(notificationType(data));
            log.setTitleHash(sha256(title));
            log.setBodyHash(sha256(body));
            log.setStatus(status);
            log.setProviderMessageId(providerMessageId);
            log.setProviderErrorCode(providerErrorCode);
            deliveryLogRepository.save(log);
        } catch (RuntimeException ex) {
            logger.warn("Unable to record push delivery log for token id={}", token.getId(), ex);
        }
    }

    private String notificationType(Map<String, String> data) {
        if (data == null) {
            return "UNKNOWN";
        }
        String type = data.get("type");
        if (type == null || type.isBlank()) {
            return "UNKNOWN";
        }
        return type.trim().length() <= 64 ? type.trim() : type.trim().substring(0, 64);
    }

    private String providerErrorCode(FirebaseMessagingException ex) {
        return ex.getMessagingErrorCode() == null
                ? ex.getClass().getSimpleName()
                : ex.getMessagingErrorCode().name();
    }

    private String sha256(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] hash = digest.digest(value.trim().getBytes(StandardCharsets.UTF_8));
            StringBuilder hex = new StringBuilder(hash.length * 2);
            for (byte b : hash) {
                hex.append(String.format("%02x", b));
            }
            return hex.toString();
        } catch (NoSuchAlgorithmException ex) {
            throw new IllegalStateException("SHA-256 unavailable", ex);
        }
    }

    private Map<String, Object> response(boolean attempted, int target, int sent, int failed, String reason) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("attempted", attempted);
        payload.put("target", target);
        payload.put("sent", sent);
        payload.put("failed", failed);
        if (reason != null) {
            payload.put("reason", reason);
        }
        return payload;
    }

    public Map<String, Object> getPushStatus() {
        return messagingProvider.getStatus();
    }

    private String safe(String value, String fallback) {
        return value == null || value.isBlank() ? fallback : value.trim();
    }
}
