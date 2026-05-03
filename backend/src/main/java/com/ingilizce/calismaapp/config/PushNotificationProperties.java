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
        private String title = "KlioAI";
        private String body = "A quick practice session is ready for today.";
        private int maxTokensPerRun = 500;

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
    }
}
