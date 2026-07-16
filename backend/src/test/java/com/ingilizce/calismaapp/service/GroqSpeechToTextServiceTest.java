package com.ingilizce.calismaapp.service;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.core.io.Resource;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestTemplate;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertInstanceOf;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class GroqSpeechToTextServiceTest {

    private GroqSpeechToTextService service;
    private RestTemplate restTemplate;

    @BeforeEach
    void setUp() {
        service = new GroqSpeechToTextService();
        restTemplate = mock(RestTemplate.class);
        ReflectionTestUtils.setField(service, "restTemplate", restTemplate);
        ReflectionTestUtils.setField(service, "apiKey", "test-groq-key");
        ReflectionTestUtils.setField(service, "transcriptionUrl", "https://groq.test/audio/transcriptions");
        ReflectionTestUtils.setField(service, "model", "whisper-large-v3-turbo");
        ReflectionTestUtils.setField(service, "language", "en");
        ReflectionTestUtils.setField(service, "prompt", "  Speak clearly in English.  ");
    }

    @Test
    void transcribeShouldBuildMultipartRequestAndReturnText() {
        when(restTemplate.postForEntity(eq("https://groq.test/audio/transcriptions"),
                org.mockito.ArgumentMatchers.any(HttpEntity.class),
                eq(String.class)))
                .thenReturn(new ResponseEntity<>("{\"text\":\"  I want to practice speaking.  \"}", HttpStatus.OK));

        GroqSpeechToTextService.TranscriptionResult result = service.transcribe(
                new byte[]{1, 2, 3},
                "my speech!.wav",
                "",
                "en_US");

        assertEquals("I want to practice speaking.", result.text());
        assertEquals("whisper-large-v3-turbo", result.model());

        ArgumentCaptor<HttpEntity> entityCaptor = ArgumentCaptor.forClass(HttpEntity.class);
        verify(restTemplate).postForEntity(
                eq("https://groq.test/audio/transcriptions"),
                entityCaptor.capture(),
                eq(String.class));

        HttpEntity<?> request = entityCaptor.getValue();
        HttpHeaders headers = request.getHeaders();
        assertEquals("Bearer test-groq-key", headers.getFirst(HttpHeaders.AUTHORIZATION));
        assertEquals("multipart/form-data", headers.getContentType().toString());

        MultiValueMap<String, Object> body = multipartBody(request);
        assertEquals("whisper-large-v3-turbo", body.getFirst("model"));
        assertEquals("en", body.getFirst("language"));
        assertEquals("0", body.getFirst("temperature"));
        assertEquals("verbose_json", body.getFirst("response_format"));
        assertEquals("word", body.getFirst("timestamp_granularities[]"));
        assertEquals("Speak clearly in English.", body.getFirst("prompt"));

        HttpEntity<?> filePart = assertInstanceOf(HttpEntity.class, body.getFirst("file"));
        Resource fileResource = assertInstanceOf(Resource.class, filePart.getBody());
        assertEquals("my_speech_.wav", fileResource.getFilename());
        assertEquals("audio/wav", filePart.getHeaders().getContentType().toString());
    }

    @Test
    void transcribeShouldParseMeasuredDurationAndWordTimings() {
        when(restTemplate.postForEntity(eq("https://groq.test/audio/transcriptions"),
                org.mockito.ArgumentMatchers.any(HttpEntity.class),
                eq(String.class)))
                .thenReturn(new ResponseEntity<>(
                        "{\"text\":\"good morning\",\"duration\":2.35,"
                                + "\"words\":[{\"word\":\"good\",\"start\":0.1,\"end\":0.5},"
                                + "{\"word\":\"morning\",\"start\":0.6,\"end\":1.2},"
                                + "{\"word\":\"\",\"start\":1.3,\"end\":1.4}]}",
                        HttpStatus.OK));

        GroqSpeechToTextService.TranscriptionResult result = service.transcribe(
                new byte[]{1}, "a.wav", "audio/wav", "en_US");

        assertEquals(2.35, result.durationSeconds());
        assertEquals(2, result.words().size(), "Blank-word entries must be skipped");
        assertEquals("good", result.words().get(0).word());
        assertEquals(0.1, result.words().get(0).start());
        assertEquals(1.2, result.words().get(1).end());
    }

    @Test
    void transcribeShouldTolerateMissingDurationAndWords() {
        when(restTemplate.postForEntity(eq("https://groq.test/audio/transcriptions"),
                org.mockito.ArgumentMatchers.any(HttpEntity.class),
                eq(String.class)))
                .thenReturn(new ResponseEntity<>("{\"text\":\"hello\"}", HttpStatus.OK));

        GroqSpeechToTextService.TranscriptionResult result = service.transcribe(
                new byte[]{1}, "a.wav", "audio/wav", "en_US");

        assertEquals("hello", result.text());
        assertEquals(null, result.durationSeconds());
        assertTrue(result.words().isEmpty());
    }

    @Test
    void transcribeShouldFallbackToConfiguredLanguageForNonEnglishLocaleAndMp3Filename() {
        ReflectionTestUtils.setField(service, "language", "tr");
        ReflectionTestUtils.setField(service, "prompt", " ");
        when(restTemplate.postForEntity(eq("https://groq.test/audio/transcriptions"),
                org.mockito.ArgumentMatchers.any(HttpEntity.class),
                eq(String.class)))
                .thenReturn(new ResponseEntity<>("{\"text\":\"Merhaba\"}", HttpStatus.OK));

        service.transcribe(new byte[]{1}, "voice.mp3", "not-a-media-type", "tr_TR");

        ArgumentCaptor<HttpEntity> entityCaptor = ArgumentCaptor.forClass(HttpEntity.class);
        verify(restTemplate).postForEntity(
                eq("https://groq.test/audio/transcriptions"),
                entityCaptor.capture(),
                eq(String.class));

        MultiValueMap<String, Object> body = multipartBody(entityCaptor.getValue());
        assertEquals("tr", body.getFirst("language"));
        assertTrue(!body.containsKey("prompt"));

        HttpEntity<?> filePart = assertInstanceOf(HttpEntity.class, body.getFirst("file"));
        assertEquals("audio/mpeg", filePart.getHeaders().getContentType().toString());
    }

    @Test
    void transcribeShouldUseSafeDefaultsForBlankFilenameAndUnknownContentType() {
        when(restTemplate.postForEntity(eq("https://groq.test/audio/transcriptions"),
                org.mockito.ArgumentMatchers.any(HttpEntity.class),
                eq(String.class)))
                .thenReturn(new ResponseEntity<>("{\"text\":null}", HttpStatus.OK));

        GroqSpeechToTextService.TranscriptionResult result = service.transcribe(
                new byte[]{1},
                " ",
                "not-a-media-type",
                null);

        assertEquals("", result.text());

        ArgumentCaptor<HttpEntity> entityCaptor = ArgumentCaptor.forClass(HttpEntity.class);
        verify(restTemplate).postForEntity(
                eq("https://groq.test/audio/transcriptions"),
                entityCaptor.capture(),
                eq(String.class));
        MultiValueMap<String, Object> body = multipartBody(entityCaptor.getValue());
        HttpEntity<?> filePart = assertInstanceOf(HttpEntity.class, body.getFirst("file"));
        Resource fileResource = assertInstanceOf(Resource.class, filePart.getBody());
        assertEquals("speech.m4a", fileResource.getFilename());
        assertEquals("audio/mp4", filePart.getHeaders().getContentType().toString());
    }

    @Test
    void transcribeShouldRejectMissingApiKeyAndEmptyAudio() {
        ReflectionTestUtils.setField(service, "apiKey", " ");
        IllegalStateException missingKey = assertThrows(IllegalStateException.class,
                () -> service.transcribe(new byte[]{1}, "speech.m4a", "audio/mp4", "en"));
        assertEquals("Groq API key is not configured", missingKey.getMessage());

        ReflectionTestUtils.setField(service, "apiKey", "test-groq-key");
        IllegalArgumentException emptyAudio = assertThrows(IllegalArgumentException.class,
                () -> service.transcribe(new byte[0], "speech.m4a", "audio/mp4", "en"));
        assertEquals("Audio file is empty", emptyAudio.getMessage());
    }

    @Test
    void transcribeShouldWrapProviderHttpErrors() {
        when(restTemplate.postForEntity(eq("https://groq.test/audio/transcriptions"),
                org.mockito.ArgumentMatchers.any(HttpEntity.class),
                eq(String.class)))
                .thenThrow(HttpClientErrorException.create(
                        HttpStatus.UNAUTHORIZED,
                        "Unauthorized",
                        HttpHeaders.EMPTY,
                        "{\"error\":\"bad key\"}".getBytes(),
                        null));

        RuntimeException ex = assertThrows(RuntimeException.class,
                () -> service.transcribe(new byte[]{1}, "speech.m4a", "audio/mp4", "en"));

        assertTrue(ex.getMessage().contains("Groq speech transcription failed: 401"));
    }

    @Test
    void transcribeShouldWrapMalformedJsonResponses() {
        when(restTemplate.postForEntity(eq("https://groq.test/audio/transcriptions"),
                org.mockito.ArgumentMatchers.any(HttpEntity.class),
                eq(String.class)))
                .thenReturn(new ResponseEntity<>("not-json", HttpStatus.OK));

        RuntimeException ex = assertThrows(RuntimeException.class,
                () -> service.transcribe(new byte[]{1}, "speech.m4a", "audio/mp4", "en"));

        assertEquals("Groq speech transcription failed", ex.getMessage());
    }

    @SuppressWarnings("unchecked")
    private MultiValueMap<String, Object> multipartBody(HttpEntity<?> request) {
        return (MultiValueMap<String, Object>) assertInstanceOf(MultiValueMap.class, request.getBody());
    }
}
