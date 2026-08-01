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

    /**
     * Hourly, on the hour.
     *
     * <p>It used to be a single 17:00 UTC cron, which is one evening — someone else's. Waking
     * every hour and letting each device through when it is that device's own local reminder
     * hour is what makes one schedule serve every timezone. The run is cheap when it is
     * nobody's hour: the planner rejects on the clock before any query is made.
     */
    @Scheduled(
            cron = "${app.push.daily-reminders.cron:0 0 * * * *}",
            zone = "${app.push.daily-reminders.zone:UTC}")
    public void sendDailyReminder() {
        if (!properties.getDailyReminders().isEnabled()) {
            return;
        }

        Map<String, Object> result = pushNotificationService.sendDailyReminderToActiveDevices();
        logger.info("Daily push reminder result={}", result);
    }
}
