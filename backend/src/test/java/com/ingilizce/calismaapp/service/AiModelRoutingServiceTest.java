package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.config.AiModelRoutingProperties;
import org.junit.jupiter.api.Test;

import java.util.Set;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

class AiModelRoutingServiceTest {

    @Test
    void resolveModelForScope_ShouldRouteSpeechScopesToSpeechModel() {
        AiModelRoutingProperties properties = new AiModelRoutingProperties();
        properties.setEnabled(true);
        properties.setSpeechModel("llama-3.3-70b-versatile");
        properties.setUtilityModel("openai/gpt-oss-20b");
        properties.setSpeechScopes(Set.of("chat", "speaking-generate"));

        AiModelRoutingService service = new AiModelRoutingService(properties);

        assertEquals("llama-3.3-70b-versatile", service.resolveModelForScope("chat"));
        assertEquals("llama-3.3-70b-versatile", service.resolveModelForScope("speaking-generate"));
        assertEquals("openai/gpt-oss-20b", service.resolveModelForScope("dictionary-lookup"));
    }

    @Test
    void resolveModelForScope_ShouldReturnNullWhenRoutingDisabled() {
        AiModelRoutingProperties properties = new AiModelRoutingProperties();
        properties.setEnabled(false);

        AiModelRoutingService service = new AiModelRoutingService(properties);

        assertNull(service.resolveModelForScope("chat"));
    }
}
