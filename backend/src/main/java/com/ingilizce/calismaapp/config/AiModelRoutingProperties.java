package com.ingilizce.calismaapp.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

import java.util.LinkedHashSet;
import java.util.Set;

@Component
@ConfigurationProperties(prefix = "app.ai.model-routing")
public class AiModelRoutingProperties {
    private boolean enabled = true;
    private String defaultModel = "openai/gpt-oss-20b";
    private String speechModel = "llama-3.3-70b-versatile";
    private String utilityModel = "openai/gpt-oss-20b";
    private Set<String> speechScopes = new LinkedHashSet<>(Set.of(
            "speaking-generate",
            "speaking-evaluate"));

    public boolean isEnabled() {
        return enabled;
    }

    public void setEnabled(boolean enabled) {
        this.enabled = enabled;
    }

    public String getDefaultModel() {
        return defaultModel;
    }

    public void setDefaultModel(String defaultModel) {
        this.defaultModel = defaultModel;
    }

    public String getSpeechModel() {
        return speechModel;
    }

    public void setSpeechModel(String speechModel) {
        this.speechModel = speechModel;
    }

    public String getUtilityModel() {
        return utilityModel;
    }

    public void setUtilityModel(String utilityModel) {
        this.utilityModel = utilityModel;
    }

    public Set<String> getSpeechScopes() {
        return speechScopes;
    }

    public void setSpeechScopes(Set<String> speechScopes) {
        this.speechScopes = speechScopes != null ? speechScopes : new LinkedHashSet<>();
    }
}
