package com.ingilizce.calismaapp.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "app.subscription.google-play.rtdn")
public class GooglePlayRtdnProperties {

    private boolean enabled = false;
    private String sharedSecret = "";

    public boolean isEnabled() {
        return enabled;
    }

    public void setEnabled(boolean enabled) {
        this.enabled = enabled;
    }

    public String getSharedSecret() {
        return sharedSecret;
    }

    public void setSharedSecret(String sharedSecret) {
        this.sharedSecret = sharedSecret != null ? sharedSecret.trim() : "";
    }

    public boolean hasSharedSecret() {
        return !sharedSecret.isBlank();
    }
}
