package com.ingilizce.calismaapp.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

import java.util.HashMap;
import java.util.Map;

@Component
@ConfigurationProperties(prefix = "app.subscription.google-play")
public class GooglePlaySubscriptionProperties {

    private boolean enabled = false;
    private String packageName = "";
    private String serviceAccountFile = "";
    private String tokenUri = "https://oauth2.googleapis.com/token";
    private String publisherApiBaseUrl = "https://androidpublisher.googleapis.com";
    private boolean acceptGracePeriod = true;
    private boolean acceptOnHold = false;
    private long accessTokenSkewSeconds = 60;
    private Map<String, String> productPlanMap = new HashMap<>();

    public boolean isEnabled() {
        return enabled;
    }

    public void setEnabled(boolean enabled) {
        this.enabled = enabled;
    }

    public String getPackageName() {
        return packageName;
    }

    public void setPackageName(String packageName) {
        this.packageName = packageName != null ? packageName.trim() : "";
    }

    public String getServiceAccountFile() {
        return serviceAccountFile;
    }

    public void setServiceAccountFile(String serviceAccountFile) {
        this.serviceAccountFile = serviceAccountFile != null ? serviceAccountFile.trim() : "";
    }

    public String getTokenUri() {
        return tokenUri;
    }

    public void setTokenUri(String tokenUri) {
        this.tokenUri = tokenUri != null ? tokenUri.trim() : "";
    }

    public String getPublisherApiBaseUrl() {
        return publisherApiBaseUrl;
    }

    public void setPublisherApiBaseUrl(String publisherApiBaseUrl) {
        this.publisherApiBaseUrl = publisherApiBaseUrl != null ? publisherApiBaseUrl.trim() : "";
    }

    public boolean isAcceptGracePeriod() {
        return acceptGracePeriod;
    }

    public void setAcceptGracePeriod(boolean acceptGracePeriod) {
        this.acceptGracePeriod = acceptGracePeriod;
    }

    public boolean isAcceptOnHold() {
        return acceptOnHold;
    }

    public void setAcceptOnHold(boolean acceptOnHold) {
        this.acceptOnHold = acceptOnHold;
    }

    public long getAccessTokenSkewSeconds() {
        return accessTokenSkewSeconds;
    }

    public void setAccessTokenSkewSeconds(long accessTokenSkewSeconds) {
        this.accessTokenSkewSeconds = Math.max(0L, accessTokenSkewSeconds);
    }

    public Map<String, String> getProductPlanMap() {
        return productPlanMap;
    }

    public void setProductPlanMap(Map<String, String> productPlanMap) {
        this.productPlanMap = productPlanMap != null ? productPlanMap : new HashMap<>();
    }
}

