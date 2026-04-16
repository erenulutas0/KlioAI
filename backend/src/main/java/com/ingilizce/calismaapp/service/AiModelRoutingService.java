package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.config.AiModelRoutingProperties;
import org.springframework.stereotype.Service;

import java.util.Locale;
import java.util.Set;
import java.util.stream.Collectors;

@Service
public class AiModelRoutingService {

    private final AiModelRoutingProperties properties;

    public AiModelRoutingService(AiModelRoutingProperties properties) {
        this.properties = properties;
    }

    public String resolveModelForScope(String scope) {
        if (!properties.isEnabled()) {
            return null;
        }

        String normalizedScope = normalize(scope);
        Set<String> speechScopes = properties.getSpeechScopes().stream()
                .map(this::normalize)
                .collect(Collectors.toSet());

        if (speechScopes.contains(normalizedScope)) {
            return sanitize(properties.getSpeechModel());
        }
        return sanitize(properties.getUtilityModel());
    }

    public String defaultModel() {
        return sanitize(properties.getDefaultModel());
    }

    private String sanitize(String value) {
        if (value == null) {
            return null;
        }
        String trimmed = value.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }

    private String normalize(String scope) {
        if (scope == null) {
            return "";
        }
        return scope.trim().toLowerCase(Locale.ROOT);
    }
}
