package com.ingilizce.calismaapp.service;

import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.FirebaseMessagingException;
import com.google.firebase.messaging.Message;
import com.google.firebase.messaging.Notification;
import com.ingilizce.calismaapp.config.PushNotificationProperties;
import com.ingilizce.calismaapp.entity.DevicePushToken;
import com.ingilizce.calismaapp.repository.DevicePushTokenRepository;
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
    private final PushNotificationProperties properties;

    public PushNotificationService(
            FirebaseMessagingProvider messagingProvider,
            DevicePushTokenRepository tokenRepository,
            PushNotificationProperties properties) {
        this.messagingProvider = messagingProvider;
        this.tokenRepository = tokenRepository;
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
            return response(false, tokens.size(), 0, 0, "firebase-disabled");
        }

        int sent = 0;
        int failed = 0;
        for (DevicePushToken token : tokens) {
            try {
                messaging.get().send(buildMessage(token.getToken(), title, body, data));
                sent++;
            } catch (FirebaseMessagingException ex) {
                failed++;
                handleSendFailure(token, ex);
            } catch (RuntimeException ex) {
                failed++;
                logger.warn("Push notification send failed for token id={}", token.getId(), ex);
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
        String code = ex.getMessagingErrorCode() == null
                ? ""
                : ex.getMessagingErrorCode().name();
        if ("UNREGISTERED".equals(code) || "INVALID_ARGUMENT".equals(code)) {
            token.setEnabled(false);
            tokenRepository.save(token);
            logger.info("Disabled invalid push token id={} errorCode={}", token.getId(), code);
            return;
        }
        logger.warn("Push notification send failed for token id={} errorCode={}", token.getId(), code, ex);
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

    private String safe(String value, String fallback) {
        return value == null || value.isBlank() ? fallback : value.trim();
    }
}
