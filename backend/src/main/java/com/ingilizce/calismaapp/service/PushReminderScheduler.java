package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.config.PushNotificationProperties;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

@Service
public class PushReminderScheduler {

    private static final Logger logger = LoggerFactory.getLogger(PushReminderScheduler.class);

    private final PushNotificationProperties properties;
    private final PushNotificationService pushNotificationService;

    public PushReminderScheduler(
            PushNotificationProperties properties,
            PushNotificationService pushNotificationService) {
        this.properties = properties;
        this.pushNotificationService = pushNotificationService;
    }

    @Scheduled(
            cron = "${app.push.daily-reminders.cron:0 0 17 * * *}",
            zone = "${app.push.daily-reminders.zone:UTC}")
    public void sendDailyReminder() {
        if (!properties.getDailyReminders().isEnabled()) {
            return;
        }

        Map<String, Object> result = pushNotificationService.sendDailyReminderToActiveDevices();
        logger.info("Daily push reminder result={}", result);
    }
}
