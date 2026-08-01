package com.ingilizce.calismaapp.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "app.push")
public class PushNotificationProperties {

    private Firebase firebase = new Firebase();
    private DailyReminders dailyReminders = new DailyReminders();

    public Firebase getFirebase() {
        return firebase;
    }

    public void setFirebase(Firebase firebase) {
        this.firebase = firebase;
    }

    public DailyReminders getDailyReminders() {
        return dailyReminders;
    }

    public void setDailyReminders(DailyReminders dailyReminders) {
        this.dailyReminders = dailyReminders;
    }

    public static class Firebase {
        private boolean enabled;
        private String serviceAccountFile = "";
        private String serviceAccountJson = "";

        public boolean isEnabled() {
            return enabled;
        }

        public void setEnabled(boolean enabled) {
            this.enabled = enabled;
        }

        public String getServiceAccountFile() {
            return serviceAccountFile;
        }

        public void setServiceAccountFile(String serviceAccountFile) {
            this.serviceAccountFile = serviceAccountFile;
        }

        public String getServiceAccountJson() {
            return serviceAccountJson;
        }

        public void setServiceAccountJson(String serviceAccountJson) {
            this.serviceAccountJson = serviceAccountJson;
        }
    }

    public static class DailyReminders {
        private boolean enabled;

        /**
         * @deprecated The copy is built per learner now — see {@link
         *     com.ingilizce.calismaapp.service.DailyReminderPlanner} — because a fixed string
         *     cannot name how many words are waiting and cannot be in the reader's language.
         *     Kept so existing deployment configuration still binds instead of failing to
         *     start.
         */
        @Deprecated
        private String title = "KlioAI";

        /** @deprecated See {@link #title}. */
        @Deprecated
        private String body = "A quick practice session is ready for today.";

        private int maxTokensPerRun = 500;

        /**
         * The hour, in each learner's own timezone, that the reminder belongs at.
         *
         * <p>Not a UTC cron hour. The scheduler wakes hourly and each device is let through
         * on its own local hour, so this is 20:00 for a learner in Istanbul and 20:00 for one
         * in Berlin without either of them being configured separately.
         */
        private int localHour = 20;

        public boolean isEnabled() {
            return enabled;
        }

        public void setEnabled(boolean enabled) {
            this.enabled = enabled;
        }

        public String getTitle() {
            return title;
        }

        public void setTitle(String title) {
            this.title = title;
        }

        public String getBody() {
            return body;
        }

        public void setBody(String body) {
            this.body = body;
        }

        public int getMaxTokensPerRun() {
            return maxTokensPerRun;
        }

        public void setMaxTokensPerRun(int maxTokensPerRun) {
            this.maxTokensPerRun = maxTokensPerRun;
        }

        public int getLocalHour() {
            return localHour;
        }

        public void setLocalHour(int localHour) {
            // Clamped rather than validated: a bad value here would otherwise mean the
            // reminder silently never matches any hour and nobody is ever notified.
            this.localHour = Math.max(0, Math.min(23, localHour));
        }
    }
}
