package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.config.AiModelRoutingProperties;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class SyntheticProbeServiceTest {

    @Mock
    private AiCompletionProvider aiCompletionProvider;

    private final AiModelRoutingProperties modelRoutingProperties = new AiModelRoutingProperties();

    @Test
    void runProbeReturnsTrueWhenProviderRespondsOk() {
        when(aiCompletionProvider.chatCompletion(any(), anyBoolean(), anyString()))
                .thenReturn("OK");

        SyntheticProbeService service =
                new SyntheticProbeService(aiCompletionProvider, modelRoutingProperties, null);

        assertTrue(service.runProbe());
    }

    @Test
    void runProbeReturnsFalseWhenProviderReturnsNull() {
        when(aiCompletionProvider.chatCompletion(any(), anyBoolean(), anyString()))
                .thenReturn(null);

        SyntheticProbeService service =
                new SyntheticProbeService(aiCompletionProvider, modelRoutingProperties, null);

        assertFalse(service.runProbe());
    }

    @Test
    void runProbeReturnsFalseWhenProviderReturnsUnexpectedContent() {
        when(aiCompletionProvider.chatCompletion(any(), anyBoolean(), anyString()))
                .thenReturn("I refuse to answer");

        SyntheticProbeService service =
                new SyntheticProbeService(aiCompletionProvider, modelRoutingProperties, null);

        assertFalse(service.runProbe());
    }

    @Test
    void runProbeReturnsFalseWhenProviderThrows() {
        when(aiCompletionProvider.chatCompletion(any(), anyBoolean(), anyString()))
                .thenThrow(new RuntimeException("provider down"));

        SyntheticProbeService service =
                new SyntheticProbeService(aiCompletionProvider, modelRoutingProperties, null);

        assertFalse(service.runProbe());
    }
}
