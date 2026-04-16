package com.ingilizce.calismaapp.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "app.subscription.google-play.reconciliation")
public class GooglePlaySubscriptionReconciliationProperties {

    private boolean enabled = false;
    private int maxUsersPerRun = 200;

    public boolean isEnabled() {
        return enabled;
    }

    public void setEnabled(boolean enabled) {
        this.enabled = enabled;
    }

    public int getMaxUsersPerRun() {
        return maxUsersPerRun;
    }

    public void setMaxUsersPerRun(int maxUsersPerRun) {
        this.maxUsersPerRun = Math.max(1, maxUsersPerRun);
    }
}

