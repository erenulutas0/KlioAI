package com.ingilizce.calismaapp.service;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/** Which engine speaks, and what happens when the first one cannot. */
class SpeechServiceTest {

    private final KokoroTtsService kokoro = mock(KokoroTtsService.class);
    private final PiperTtsService piper = mock(PiperTtsService.class);
    private final SpeechService service = new SpeechService(kokoro, piper);

    @Test
    @DisplayName("Kokoro speaks when it is configured")
    void kokoroFirst() {
        when(kokoro.isEnabled()).thenReturn(true);
        when(kokoro.synthesize("Hello", "amy")).thenReturn("a2Vrbw==");

        assertEquals("a2Vrbw==", service.synthesizeSpeech("Hello", "amy"));
        verify(piper, never()).synthesizeSpeech(anyString(), anyString());
    }

    @Test
    @DisplayName("a Kokoro that is down costs a better voice, not the voice")
    void piperCatchesTheFall() {
        // Mid-conversation, a worse voice is a far smaller thing than a silent tutor.
        when(kokoro.isEnabled()).thenReturn(true);
        when(kokoro.synthesize("Hello", "amy")).thenReturn(null);
        when(piper.isAvailable()).thenReturn(true);
        when(piper.synthesizeSpeech("Hello", "amy")).thenReturn("cGlwZXI=");

        assertEquals("cGlwZXI=", service.synthesizeSpeech("Hello", "amy"));
    }

    @Test
    @DisplayName("Piper alone is enough when Kokoro is not configured")
    void piperOnly() {
        when(kokoro.isEnabled()).thenReturn(false);
        when(piper.isAvailable()).thenReturn(true);
        when(piper.synthesizeSpeech("Hello", "amy")).thenReturn("cGlwZXI=");

        assertTrue(service.isAvailable());
        assertEquals("cGlwZXI=", service.synthesizeSpeech("Hello", "amy"));
        verify(kokoro, never()).synthesize(anyString(), anyString());
    }

    @Test
    @DisplayName("neither engine is no audio, and never an exception")
    void neitherEngine() {
        when(kokoro.isEnabled()).thenReturn(false);
        when(piper.isAvailable()).thenReturn(false);

        assertFalse(service.isAvailable());
        assertNull(service.synthesizeSpeech("Hello", "amy"));
    }

    @Test
    @DisplayName("a Piper that throws is still not an exception for the caller")
    void piperThrowing() {
        when(kokoro.isEnabled()).thenReturn(false);
        when(piper.isAvailable()).thenReturn(true);
        when(piper.synthesizeSpeech("Hello", "amy")).thenThrow(new RuntimeException("piper gone"));

        assertNull(service.synthesizeSpeech("Hello", "amy"));
    }

    @Test
    @DisplayName("Kokoro configured is speech available, even with no Piper installed")
    void availabilityFollowsEitherEngine() {
        when(kokoro.isEnabled()).thenReturn(true);
        assertTrue(service.isAvailable());
        verify(piper, never()).isAvailable();
    }
}
