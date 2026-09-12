package com.ingilizce.calismaapp.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.mockito.ArgumentCaptor;
import org.springframework.http.HttpEntity;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.client.RestTemplate;

import java.nio.file.Path;
import java.util.Base64;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * The engine the tutor speaks through.
 *
 * <p>Kokoro is Apache 2.0 and may be sold; the two Piper voices it replaces may not. What is
 * pinned here is the wire (the app's voice ids reach Kokoro as Kokoro voices), the cache (a
 * repeated line is not synthesised twice), and that nothing about Kokoro can take the
 * learner's voice away entirely -- a failure is a null, and SpeechService then asks Piper.
 */
class KokoroTtsServiceTest {

    private RestTemplate restTemplate;
    private KokoroTtsService service;

    @BeforeEach
    void setUp(@TempDir Path cacheDir) {
        restTemplate = mock(RestTemplate.class);
        service = new KokoroTtsService(restTemplate);
        ReflectionTestUtils.setField(service, "baseUrl", "http://kokoro:8880");
        ReflectionTestUtils.setField(service, "model", "kokoro");
        ReflectionTestUtils.setField(service, "voiceMapping",
                "amy=af_heart,ryan=am_michael,lessac=af_bella,cori=bf_emma,jenny=bf_isabella,alan=bm_george");
        ReflectionTestUtils.setField(service, "defaultVoice", "af_heart");
        ReflectionTestUtils.setField(service, "cacheEnabled", true);
        ReflectionTestUtils.setField(service, "configuredCacheDir", cacheDir.toString());
        ReflectionTestUtils.setField(service, "cacheMaxEntries", 100);
    }

    /**
     * The first request of the day is the backend's, not a learner's.
     *
     * <p>Measured after a restart: 8.4 s to speak a 127-character reply, against 2.3 s for the
     * same length once Kokoro had loaded its voice. Somebody has to pay that, and it should not
     * be the person mid-conversation.
     */
    @Test
    @DisplayName("startup speaks one throwaway line so the model is loaded")
    void theWarmUpIsTheFirstRequest() {
        service.warmUp();

        verify(restTemplate).postForObject(
                eq("http://kokoro:8880/v1/audio/speech"), any(), eq(byte[].class));
    }

    @Test
    @DisplayName("a backend without Kokoro warms nothing up")
    void nothingIsWarmedUpWhenKokoroIsOff() {
        ReflectionTestUtils.setField(service, "baseUrl", "");

        service.warmUpInBackground();

        verifyNoInteractions(restTemplate);
    }

    @Test
    @DisplayName("the app's voice ids reach Kokoro as Kokoro's own")
    void voicesAreMapped() {
        // The app still says "ryan" -- saved conversations and the scene catalog do too --
        // and what it gets is a Kokoro voice of the same gender, not the model whose licence
        // forbids selling it.
        assertEquals("am_michael", service.voiceFor("ryan"));
        assertEquals("af_bella", service.voiceFor("lessac"));
        assertEquals("af_heart", service.voiceFor("amy"));
        assertEquals("bm_george", service.voiceFor("alan"));
        assertEquals("bf_emma", service.voiceFor("CORI"), "the id arrives in whatever case the app sent");
        assertEquals("af_heart", service.voiceFor("nobody"), "an unknown voice still speaks");
        assertEquals("af_heart", service.voiceFor(null));
    }

    @Test
    @DisplayName("a reply is asked for as WAV, in the mapped voice, and comes back as Base64")
    void synthesizeSendsTheRequestAndEncodesTheAnswer() throws Exception {
        when(restTemplate.postForObject(anyString(), any(HttpEntity.class), eq(byte[].class)))
                .thenReturn(new byte[] { 1, 2, 3, 4 });

        String audio = service.synthesize("Good evening!", "ryan");

        assertEquals(Base64.getEncoder().encodeToString(new byte[] { 1, 2, 3, 4 }), audio);
        ArgumentCaptor<String> url = ArgumentCaptor.forClass(String.class);
        ArgumentCaptor<HttpEntity> request = ArgumentCaptor.forClass(HttpEntity.class);
        verify(restTemplate).postForObject(url.capture(), request.capture(), eq(byte[].class));
        assertEquals("http://kokoro:8880/v1/audio/speech", url.getValue());
        Map<?, ?> body = new ObjectMapper().readValue(request.getValue().getBody().toString(), Map.class);
        assertEquals("kokoro", body.get("model"));
        assertEquals("Good evening!", body.get("input"));
        assertEquals("am_michael", body.get("voice"));
        assertEquals("wav", body.get("response_format"));
    }

    @Test
    @DisplayName("the same line in the same voice is synthesised once")
    void repeatedLinesComeFromTheCache() {
        // Two and a half seconds on the server, every time, without this.
        when(restTemplate.postForObject(anyString(), any(HttpEntity.class), eq(byte[].class)))
                .thenReturn(new byte[] { 9, 9, 9 });

        String first = service.synthesize("Here is your bill.", "amy");
        String second = service.synthesize("Here is your bill.", "amy");

        assertEquals(first, second);
        verify(restTemplate, times(1)).postForObject(anyString(), any(HttpEntity.class), eq(byte[].class));
    }

    @Test
    @DisplayName("the same line in another voice is another recording")
    void theVoiceIsPartOfTheKey() {
        when(restTemplate.postForObject(anyString(), any(HttpEntity.class), eq(byte[].class)))
                .thenReturn(new byte[] { 1 }, new byte[] { 2 });

        service.synthesize("Anything else?", "amy");
        service.synthesize("Anything else?", "alan");

        verify(restTemplate, times(2)).postForObject(anyString(), any(HttpEntity.class), eq(byte[].class));
    }

    @Test
    @DisplayName("a Kokoro that cannot answer costs the audio, never the reply")
    void failuresAreNull() {
        when(restTemplate.postForObject(anyString(), any(HttpEntity.class), eq(byte[].class)))
                .thenThrow(new RuntimeException("connection refused"));
        assertNull(service.synthesize("Hello there", "amy"));

        when(restTemplate.postForObject(anyString(), any(HttpEntity.class), eq(byte[].class)))
                .thenReturn(new byte[0]);
        assertNull(service.synthesize("Hello again", "amy"));
    }

    @Test
    @DisplayName("no base URL is no Kokoro, and not a single call")
    void disabledByDefault() {
        ReflectionTestUtils.setField(service, "baseUrl", "");

        assertFalse(service.isEnabled());
        assertNull(service.synthesize("Hello there", "amy"));
        verify(restTemplate, never()).postForObject(anyString(), any(HttpEntity.class), eq(byte[].class));
    }

    @Test
    @DisplayName("a blank line is not worth a request")
    void blankTextIsNotSpoken() {
        assertTrue(service.isEnabled());
        assertNull(service.synthesize("   ", "amy"));
        verify(restTemplate, never()).postForObject(anyString(), any(HttpEntity.class), eq(byte[].class));
    }
}
