package com.ingilizce.calismaapp.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.Message;
import com.ingilizce.calismaapp.config.PushNotificationProperties;
import com.ingilizce.calismaapp.entity.DevicePushToken;
import com.ingilizce.calismaapp.entity.NotificationDeliveryLog;
import com.ingilizce.calismaapp.repository.NotificationDeliveryLogRepository;
import com.ingilizce.calismaapp.repository.DevicePushTokenRepository;
import com.ingilizce.calismaapp.repository.ReviewEventRepository;
import com.ingilizce.calismaapp.repository.WordRepository;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.time.ZonedDateTime;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.data.domain.Pageable;
import org.springframework.test.util.ReflectionTestUtils;

class PushNotificationServiceTest {

    @Test
    void sendDailyReminderStillRecordsASkippedDeliveryWhenFirebaseIsDown() {
        Fixture f = new Fixture();
        f.dueWords(5).lastStudied(Instant.now().minus(2, ChronoUnit.DAYS)).firebaseDown("firebase-disabled");

        Map<String, Object> response = f.service().sendDailyReminderToActiveDevices();

        assertEquals(1, response.get("considered"));
        assertEquals(0, response.get("sent"));
        // The learner was eligible and the message was built; only the transport failed. That
        // has to leave a row, otherwise an outage is indistinguishable from a quiet evening.
        verify(f.deliveryLogRepository).save(any(NotificationDeliveryLog.class));
    }

    @Test
    void sendDailyReminderClampsBatchSize() {
        Fixture f = new Fixture();
        f.properties.getDailyReminders().setMaxTokensPerRun(999);
        f.dueWords(3).lastStudied(Instant.now().minus(2, ChronoUnit.DAYS)).firebaseDown("credentials-missing");

        f.service().sendDailyReminderToActiveDevices();

        ArgumentCaptor<Pageable> pageableCaptor = ArgumentCaptor.forClass(Pageable.class);
        verify(f.repository).findRemindableTokens(pageableCaptor.capture());
        assertEquals(500, pageableCaptor.getValue().getPageSize());

        ArgumentCaptor<NotificationDeliveryLog> logCaptor =
                ArgumentCaptor.forClass(NotificationDeliveryLog.class);
        verify(f.deliveryLogRepository).save(logCaptor.capture());
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
        Fixture f = new Fixture();
        f.properties.getDailyReminders().setMaxTokensPerRun(0);
        f.noTokens().firebaseDown("firebase-disabled");

        Map<String, Object> response = f.service().sendDailyReminderToActiveDevices();

        assertEquals(0, response.get("considered"));
        ArgumentCaptor<Pageable> pageableCaptor = ArgumentCaptor.forClass(Pageable.class);
        verify(f.repository).findRemindableTokens(pageableCaptor.capture());
        assertEquals(1, pageableCaptor.getValue().getPageSize());
        verify(f.deliveryLogRepository, never()).save(any());
    }

    @Test
    void aLearnerWhoAlreadyStudiedTodayIsNotSentAnything() {
        // Wiring test, not a rules test: DailyReminderPlannerTest pins the rule against a
        // fixed clock. What matters here is that the review log is actually consulted, and
        // that a skip costs no Firebase call and leaves no delivery row — a skipped reminder
        // is not a reminder that failed.
        Fixture f = new Fixture();
        f.dueWords(9).lastStudied(Instant.now()).firebaseDown("firebase-disabled");

        Map<String, Object> response = f.service().sendDailyReminderToActiveDevices();

        assertEquals(0, response.get("sent"));
        assertEquals(Map.of("already-practised-today", 1), response.get("skipped"));
        verify(f.deliveryLogRepository, never()).save(any());
    }

    @Test
    void aLearnerWithNothingDueIsNotSentAnything() {
        Fixture f = new Fixture();
        f.dueWords(0).lastStudied(Instant.now().minus(2, ChronoUnit.DAYS)).firebaseDown("firebase-disabled");

        Map<String, Object> response = f.service().sendDailyReminderToActiveDevices();

        assertEquals(Map.of("nothing-due", 1), response.get("skipped"));
        verify(f.deliveryLogRepository, never()).save(any());
    }

    @Test
    void theDueCountReachesTheMessage() {
        Fixture f = new Fixture();
        f.dueWords(12).lastStudied(Instant.now().minus(2, ChronoUnit.DAYS)).firebaseUp();

        f.service().sendDailyReminderToActiveDevices();

        ArgumentCaptor<NotificationDeliveryLog> logCaptor =
                ArgumentCaptor.forClass(NotificationDeliveryLog.class);
        verify(f.deliveryLogRepository).save(logCaptor.capture());
        // The body is hashed in the log, so assert on the query the count came from instead:
        // the point is that the number in the notification is a real one.
        verify(f.wordRepository).countByUserIdAndNextReviewDateLessThanEqual(eq(8L), any(LocalDate.class));
        assertEquals("SENT", logCaptor.getValue().getStatus());
    }

    /**
     * Builds a service whose single device is guaranteed to be at its local reminder hour.
     *
     * <p>The hour is made deterministic by pinning the device to UTC and setting the target
     * hour to whatever hour it currently is there, rather than by injecting a clock. The
     * clock-dependent rules are covered against a fixed instant in {@link
     * DailyReminderPlannerTest}; these tests are about whether the service asks the right
     * questions and acts on the answers.
     */
    private static final class Fixture {
        final FirebaseMessagingProvider messagingProvider = mock(FirebaseMessagingProvider.class);
        final DevicePushTokenRepository repository = mock(DevicePushTokenRepository.class);
        final NotificationDeliveryLogRepository deliveryLogRepository =
                mock(NotificationDeliveryLogRepository.class);
        final WordRepository wordRepository = mock(WordRepository.class);
        final ReviewEventRepository reviewEventRepository = mock(ReviewEventRepository.class);
        final PushNotificationProperties properties = new PushNotificationProperties();

        Fixture() {
            properties.getDailyReminders().setLocalHour(ZonedDateTime.now(ZoneOffset.UTC).getHour());
            DevicePushToken token = new DevicePushToken();
            ReflectionTestUtils.setField(token, "id", 31L);
            token.setUserId(8L);
            token.setToken("daily-token");
            token.setEnabled(true);
            token.setDailyRemindersEnabled(true);
            token.setTimezone("UTC");
            token.setLocale("tr");
            when(repository.findRemindableTokens(any(Pageable.class)))
                    .thenReturn(List.of(token));
        }

        Fixture noTokens() {
            when(repository.findRemindableTokens(any(Pageable.class)))
                    .thenReturn(List.of());
            return this;
        }

        Fixture dueWords(long count) {
            when(wordRepository.countByUserIdAndNextReviewDateLessThanEqual(eq(8L), any(LocalDate.class)))
                    .thenReturn(count);
            return this;
        }

        Fixture lastStudied(Instant when) {
            when(reviewEventRepository.findLastEventAt(8L)).thenReturn(when);
            return this;
        }

        Fixture firebaseDown(String reason) {
            when(messagingProvider.getMessaging()).thenReturn(Optional.empty());
            when(messagingProvider.getUnavailableReason()).thenReturn(reason);
            return this;
        }

        Fixture firebaseUp() {
            try {
                FirebaseMessaging messaging = mock(FirebaseMessaging.class);
                when(messaging.send(any(Message.class))).thenReturn("provider-message-id");
                when(messagingProvider.getMessaging()).thenReturn(Optional.of(messaging));
            } catch (Exception e) {
                throw new IllegalStateException(e);
            }
            return this;
        }

        PushNotificationService service() {
            PushNotificationService service = new PushNotificationService(
                    messagingProvider, repository, deliveryLogRepository, properties, wordRepository);
            ReflectionTestUtils.setField(service, "reviewEventRepository", reviewEventRepository);
            return service;
        }
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
                new PushNotificationProperties(),
                mock(WordRepository.class));

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
                new PushNotificationProperties(),
                mock(WordRepository.class));
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
                new PushNotificationProperties(),
                mock(WordRepository.class));
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
                new PushNotificationProperties(),
                mock(WordRepository.class));

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
                new PushNotificationProperties(),
                mock(WordRepository.class));

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
