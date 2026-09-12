package com.ingilizce.calismaapp.service;

import java.util.List;

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
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertInstanceOf;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
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

    /**
     * The learner's own words go on the wire as a comma-separated hint, and nothing else.
     *
     * <p>This is the use the {@code prompt} field's comment has described since the
     * hallucination bug and nobody had implemented: vocabulary, not instructions. "I am agree
     * with you" was heard as "I am angry with you" on a real device, and "agree" was in that
     * learner's deck the whole time.
     */
    @Test
    void transcribeShouldSendTheLearnersOwnWordsAsTheWhisperPrompt() {
        ReflectionTestUtils.setField(service, "prompt", "");
        when(restTemplate.postForEntity(eq("https://groq.test/audio/transcriptions"),
                org.mockito.ArgumentMatchers.any(HttpEntity.class),
                eq(String.class)))
                .thenReturn(new ResponseEntity<>("{\"text\":\"I am agree with you.\"}", HttpStatus.OK));

        service.transcribe(new byte[]{1}, "a.wav", "audio/wav", "en_US",
                java.util.List.of("agree", "married", "teacher"));

        String sentPrompt = (String) capturedBody().getFirst("prompt");
        assertEquals("agree, married, teacher", sentPrompt);
        assertTrue(!sentPrompt.matches(".*[.!?].*"),
                "Prose in this field is prepended as prior transcript text and gets continued");
    }

    /**
     * A learner with an empty deck must get byte-for-byte the request that ships today.
     *
     * <p>The safe prompt is no prompt: the field's whole history is of a non-empty one
     * writing the first half of a hallucination.
     */
    @Test
    void transcribeShouldSendNoPromptForALearnerWithNoSavedWords() {
        ReflectionTestUtils.setField(service, "prompt", "");
        when(restTemplate.postForEntity(eq("https://groq.test/audio/transcriptions"),
                org.mockito.ArgumentMatchers.any(HttpEntity.class),
                eq(String.class)))
                .thenReturn(new ResponseEntity<>("{\"text\":\"hello\"}", HttpStatus.OK));

        GroqSpeechToTextService.TranscriptionResult result =
                service.transcribe(new byte[]{1}, "a.wav", "audio/wav", "en_US", java.util.List.of());

        assertEquals("hello", result.text());
        assertTrue(!capturedBody().containsKey("prompt"), "No words means no prompt part at all");
    }

    /** The escape hatch: an operator can still pin an exact prompt without a deploy. */
    @Test
    void transcribeShouldLetTheConfiguredPromptOverrideTheLearnersVocabulary() {
        ReflectionTestUtils.setField(service, "prompt", "  KlioAI, Piper, Groq  ");
        when(restTemplate.postForEntity(eq("https://groq.test/audio/transcriptions"),
                org.mockito.ArgumentMatchers.any(HttpEntity.class),
                eq(String.class)))
                .thenReturn(new ResponseEntity<>("{\"text\":\"hello\"}", HttpStatus.OK));

        service.transcribe(new byte[]{1}, "a.wav", "audio/wav", "en_US",
                java.util.List.of("agree", "married", "teacher"));

        assertEquals("KlioAI, Piper, Groq", capturedBody().getFirst("prompt"));
    }

    /** The four-argument call still exists and still sends nothing extra. */
    @Test
    void transcribeWithoutAVocabularyArgumentIsUnchanged() {
        ReflectionTestUtils.setField(service, "prompt", "");
        when(restTemplate.postForEntity(eq("https://groq.test/audio/transcriptions"),
                org.mockito.ArgumentMatchers.any(HttpEntity.class),
                eq(String.class)))
                .thenReturn(new ResponseEntity<>("{\"text\":\"hello\"}", HttpStatus.OK));

        GroqSpeechToTextService.TranscriptionResult result =
                service.transcribe(new byte[]{1}, "a.wav", "audio/wav", "en_US");

        assertEquals("hello", result.text());
        assertFalse(result.lowConfidence());
        assertNull(result.avgLogprob());
        assertTrue(!capturedBody().containsKey("prompt"));
    }

    /**
     * A shaky transcript now says so, instead of being logged and forgotten.
     *
     * <p>avg_logprob was already read here for the silence check and written to the log on
     * every request. The device never saw it, so a learner who was misheard had no way to
     * intervene before the wrong sentence reached the tutor.
     */
    @Test
    void transcribeShouldFlagAShakyTranscriptAndReportTheNumberBehindIt() {
        when(restTemplate.postForEntity(eq("https://groq.test/audio/transcriptions"),
                org.mockito.ArgumentMatchers.any(HttpEntity.class),
                eq(String.class)))
                .thenReturn(new ResponseEntity<>(
                        "{\"text\":\"I am angry with you.\",\"segments\":["
                                + "{\"no_speech_prob\":0.01,\"avg_logprob\":-0.2},"
                                + "{\"no_speech_prob\":0.02,\"avg_logprob\":-0.95}]}",
                        HttpStatus.OK));

        GroqSpeechToTextService.TranscriptionResult result = service.transcribe(
                new byte[]{1}, "a.wav", "audio/wav", "en_US");

        assertEquals("I am angry with you.", result.text());
        assertTrue(result.lowConfidence());
        assertEquals(-0.95, result.avgLogprob(),
                "The worst segment, not the mean: one garbled clause is enough to misdirect the tutor");
    }

    @Test
    void transcribeShouldNotFlagAConfidentTranscript() {
        when(restTemplate.postForEntity(eq("https://groq.test/audio/transcriptions"),
                org.mockito.ArgumentMatchers.any(HttpEntity.class),
                eq(String.class)))
                .thenReturn(new ResponseEntity<>(
                        "{\"text\":\"I agree with you.\",\"segments\":["
                                + "{\"no_speech_prob\":0.01,\"avg_logprob\":-0.31}]}",
                        HttpStatus.OK));

        GroqSpeechToTextService.TranscriptionResult result = service.transcribe(
                new byte[]{1}, "a.wav", "audio/wav", "en_US");

        assertFalse(result.lowConfidence());
        assertEquals(-0.31, result.avgLogprob());
    }

    /**
     * A discarded transcript is nothing, not something shaky.
     *
     * <p>Telling the learner to double-check words that are not there would be worse than
     * saying nothing. The number is still reported, because a discard is exactly the case
     * somebody ends up reading a log line about.
     */
    @Test
    void transcribeShouldNotFlagATranscriptItAlreadyThrewAway() {
        when(restTemplate.postForEntity(eq("https://groq.test/audio/transcriptions"),
                org.mockito.ArgumentMatchers.any(HttpEntity.class),
                eq(String.class)))
                .thenReturn(new ResponseEntity<>(
                        "{\"text\":\"Thank you.\",\"segments\":["
                                + "{\"no_speech_prob\":0.94,\"avg_logprob\":-1.7}]}",
                        HttpStatus.OK));

        GroqSpeechToTextService.TranscriptionResult result = service.transcribe(
                new byte[]{1}, "a.wav", "audio/wav", "en_US");

        assertEquals("", result.text(), "The silence check must still discard this");
        assertFalse(result.lowConfidence());
        assertEquals(-1.7, result.avgLogprob());
    }

    /**
     * The hint being read back is not a transcript.
     *
     * <p>The risk this feature opens: the prompt is prior transcript text, so handed silence
     * and a word list, the model can carry on writing the list — the same move that turned
     * the old prose prompt into invented subtitle boilerplate.
     */
    @Test
    void transcribeShouldDiscardTheHintComingStraightBack() {
        ReflectionTestUtils.setField(service, "prompt", "");
        when(restTemplate.postForEntity(eq("https://groq.test/audio/transcriptions"),
                org.mockito.ArgumentMatchers.any(HttpEntity.class),
                eq(String.class)))
                .thenReturn(new ResponseEntity<>(
                        "{\"text\":\"agree, married, teacher, weekend.\"}", HttpStatus.OK));

        GroqSpeechToTextService.TranscriptionResult result = service.transcribe(
                new byte[]{1}, "a.wav", "audio/wav", "en_US",
                java.util.List.of("agree", "married", "teacher", "weekend"));

        assertEquals("", result.text());
    }

    /** Stubs both passes, telling them apart by whether the request pins a language. */
    private void stubBothPasses(String pinnedJson, String unpinnedJson) {
        when(restTemplate.postForEntity(eq("https://groq.test/audio/transcriptions"),
                org.mockito.ArgumentMatchers.any(HttpEntity.class),
                eq(String.class)))
                .thenAnswer(invocation -> {
                    HttpEntity<?> request = invocation.getArgument(1);
                    boolean pinned = multipartBody(request).containsKey("language");
                    return new ResponseEntity<>(pinned ? pinnedJson : unpinnedJson, HttpStatus.OK);
                });
    }

    /**
     * Stubs all three passes, telling them apart by the language each one pins: English for
     * the transcript, none for the detection, and the learner's own for the respelling.
     */
    private List<String> stubThreePasses(String pinnedJson, String unpinnedJson, String nativeJson) {
        List<String> languagesAsked = new java.util.ArrayList<>();
        when(restTemplate.postForEntity(eq("https://groq.test/audio/transcriptions"),
                org.mockito.ArgumentMatchers.any(HttpEntity.class),
                eq(String.class)))
                .thenAnswer(invocation -> {
                    HttpEntity<?> request = invocation.getArgument(1);
                    Object language = multipartBody(request).getFirst("language");
                    synchronized (languagesAsked) {
                        languagesAsked.add(language == null ? "none" : language.toString());
                    }
                    if (language == null) {
                        return new ResponseEntity<>(unpinnedJson, HttpStatus.OK);
                    }
                    return new ResponseEntity<>("en".equals(language) ? pinnedJson : nativeJson, HttpStatus.OK);
                });
        return languagesAsked;
    }

    private static final String PINNED_INVENTED =
            "{\"text\":\"Hello, can you please take a while?\",\"segments\":[{\"no_speech_prob\":0.02,\"avg_logprob\":-1.24}]}";

    /**
     * A Turkish sentence labelled Azerbaijani is shown back in Turkish.
     *
     * <p>Measured on a device: two of three Turkish sentences were labelled "azerbaijani", and
     * the footer showed the learner their own words in Azerbaijani spelling. One pass pinned
     * to their language writes it as they would.
     */
    @Test
    void aSentenceInTheLearnersLanguageIsSpelledTheWayTheyWouldWriteIt() {
        ReflectionTestUtils.setField(service, "detectLanguage", true);
        List<String> asked = stubThreePasses(PINNED_INVENTED,
                "{\"text\":\"Mahaba, bir az su ala bilir mayiz?\",\"language\":\"azerbaijani\"}",
                "{\"text\":\"Merhaba, biraz su alabilir miyiz?\"}");

        GroqSpeechToTextService.TranscriptionResult result = service.transcribe(
                new byte[]{1}, "a.wav", "audio/wav", "en_US", List.of(), "Turkish");

        assertTrue(result.otherLanguage());
        assertEquals("Merhaba, biraz su alabilir miyiz?", result.heardAs());
        assertTrue(asked.contains("tr"), "the respelling pass was never asked: " + asked);
    }

    @Test
    void aLanguageThatIsNotTheLearnersOwnIsNotRespelledIntoIt() {
        // Respelling a sentence into a language it was never spoken in garbles it. Dutch is
        // not Turkish and is not a language Whisper is known to mistake for Turkish.
        ReflectionTestUtils.setField(service, "detectLanguage", true);
        List<String> asked = stubThreePasses(PINNED_INVENTED,
                "{\"text\":\"Goedenavond, mag ik wat water?\",\"language\":\"dutch\"}",
                "{\"text\":\"should never be used\"}");

        GroqSpeechToTextService.TranscriptionResult result = service.transcribe(
                new byte[]{1}, "a.wav", "audio/wav", "en_US", List.of(), "Turkish");

        assertTrue(result.otherLanguage());
        assertEquals("Goedenavond, mag ik wat water?", result.heardAs());
        assertFalse(asked.contains("tr"), "respelled into a language nobody spoke: " + asked);
    }

    @Test
    void englishTurnsCostNoRespellingPass() {
        // The pass is for the held-back path only. On every ordinary turn it would be a
        // request for nothing.
        ReflectionTestUtils.setField(service, "detectLanguage", true);
        List<String> asked = stubThreePasses(
                "{\"text\":\"A table for two, please.\",\"segments\":[{\"no_speech_prob\":0.02,\"avg_logprob\":-0.2}]}",
                "{\"text\":\"A table for two, please.\",\"language\":\"english\"}",
                "{\"text\":\"should never be used\"}");

        GroqSpeechToTextService.TranscriptionResult result = service.transcribe(
                new byte[]{1}, "a.wav", "audio/wav", "en_US", List.of(), "Turkish");

        assertFalse(result.otherLanguage());
        assertFalse(asked.contains("tr"), asked.toString());
    }

    /**
     * A sentence only partly in the learner's language keeps both halves.
     *
     * <p>The free pass writes a mixed sentence with its English and its Turkish intact. Pinned
     * to Turkish for a respelling, the English half would be forced into Turkish as well.
     */
    @Test
    void aSentenceOnlyPartlyInTheLearnersLanguageIsNotRespelled() {
        ReflectionTestUtils.setField(service, "detectLanguage", true);
        List<String> asked = stubThreePasses(
                "{\"text\":\"I'd like the pasta, and also birasso?\",\"segments\":[{\"no_speech_prob\":0.02,\"avg_logprob\":-0.3}]}",
                "{\"text\":\"I'd like the pasta, and also biraz su alabilir miyiz?\",\"language\":\"turkish\"}",
                "{\"text\":\"Ayd layk dhe pasta, end olso biraz su alabilir miyiz?\"}");

        GroqSpeechToTextService.TranscriptionResult result = service.transcribe(
                new byte[]{1}, "a.wav", "audio/wav", "en_US", List.of(), "Turkish");

        assertTrue(result.otherLanguage(), "held back for the learner to check");
        assertEquals("I'd like the pasta, and also biraz su alabilir miyiz?", result.heardAs());
        assertFalse(asked.contains("tr"), "respelled a sentence that was half English: " + asked);
    }

    @Test
    void aRespellingThatFailsLeavesWhatTheFreePassHeard() {
        ReflectionTestUtils.setField(service, "detectLanguage", true);
        stubThreePasses(PINNED_INVENTED,
                "{\"text\":\"Mahaba, bir az su ala bilir mayiz?\",\"language\":\"azerbaijani\"}",
                "not json at all");

        GroqSpeechToTextService.TranscriptionResult result = service.transcribe(
                new byte[]{1}, "a.wav", "audio/wav", "en_US", List.of(), "Turkish");

        assertTrue(result.otherLanguage());
        assertEquals("Mahaba, bir az su ala bilir mayiz?", result.heardAs(),
                "a failed respelling must cost the spelling, never the sentence");
    }

    /**
     * A sentence in the wrong language is held for a second look.
     *
     * <p>Seen on a device: a Turkish sentence, spoken to a transcriber pinned to English,
     * came back as "No, so, so, name me." with a confident avg_logprob, went straight to
     * the tutor, and was corrected -- "name me" -> "call me" -- for something the learner
     * never said. The confidence number cannot see this: the model is sure of its English.
     * Only a pass with nothing pinned can report what the audio actually was.
     */
    @Test
    void transcribeShouldHoldATranscriptWhoseAudioWasNotEnglish() {
        ReflectionTestUtils.setField(service, "detectLanguage", true);
        ReflectionTestUtils.setField(service, "prompt", "");
        stubBothPasses(
                "{\"text\":\"No, so, so, name me.\",\"segments\":[{\"no_speech_prob\":0.02,\"avg_logprob\":-0.35}]}",
                "{\"text\":\"Bugün hava çok güzel, dışarı çıkalım.\",\"language\":\"turkish\"}");

        GroqSpeechToTextService.TranscriptionResult result = service.transcribe(
                new byte[]{1}, "a.wav", "audio/wav", "en_US");

        assertEquals("No, so, so, name me.", result.text(),
                "The English transcript is what the learner is shown; the verdict is about whether to send it");
        assertTrue(result.otherLanguage());
        assertEquals("turkish", result.detectedLanguage());
        assertTrue(result.lowConfidence(), "The one flag the shipped app reads has to carry it");
        assertEquals(-0.35, result.avgLogprob(), "The number stays the transcriber's own");
    }

    @Test
    void transcribeShouldNotHoldEnglishThatMerelySoundsForeign() {
        // -0.6 is an accent, which is most of this app's audience. That line does not move.
        ReflectionTestUtils.setField(service, "detectLanguage", true);
        stubBothPasses(
                "{\"text\":\"I am agree with you.\",\"segments\":[{\"no_speech_prob\":0.02,\"avg_logprob\":-0.6}]}",
                "{\"text\":\"I am agree with you.\",\"language\":\"english\"}");

        GroqSpeechToTextService.TranscriptionResult result = service.transcribe(
                new byte[]{1}, "a.wav", "audio/wav", "en_US");

        assertFalse(result.otherLanguage());
        assertEquals("english", result.detectedLanguage());
        assertFalse(result.lowConfidence());
    }

    /**
     * A wrong label on words both passes agree on is not a verdict.
     *
     * <p>Measured on a device: 1.7 seconds of clear English, transcribed correctly, labelled
     * "dutch" by the free pass, and held back for the learner to approve a sentence that was
     * exactly what they said. Twice in five turns, both times on a short clip. The free pass
     * got the language wrong and the words right -- and when two readings of the same audio
     * write the same sentence, the audio was that sentence.
     */
    @Test
    void transcribeShouldNotHoldEnglishWhoseLabelAloneDisagrees() {
        ReflectionTestUtils.setField(service, "detectLanguage", true);
        stubBothPasses(
                "{\"text\":\"Hi, good evening.\",\"segments\":[{\"no_speech_prob\":0.02,\"avg_logprob\":-0.38}]}",
                "{\"text\":\"Hi, good evening.\",\"language\":\"dutch\"}");

        GroqSpeechToTextService.TranscriptionResult result = service.transcribe(
                new byte[]{1}, "a.wav", "audio/wav", "en_US");

        assertFalse(result.otherLanguage());
        assertFalse(result.lowConfidence(), "a sentence the learner said exactly was held back");
        assertEquals("dutch", result.detectedLanguage(), "the label stays visible in the log");
    }

    /**
     * The sentence the learner said, instead of the one the pin invented.
     *
     * <p>Measured on a device: "Merhaba, biraz su alabilir miyiz?" came back pinned as
     * "Hello, can you please take a while?", and the footer offered that to the learner --
     * words they never said, with nothing to show what they had said. The free pass had it.
     */
    @Test
    void transcribeShouldCarryWhatTheFreePassHeardWhenTheLanguageWasAnother() {
        ReflectionTestUtils.setField(service, "detectLanguage", true);
        stubBothPasses(
                "{\"text\":\"Hello, can you please take a while?\",\"segments\":[{\"no_speech_prob\":0.02,\"avg_logprob\":-1.17}]}",
                "{\"text\":\"Merhaba, biraz su alabilir miyiz?\",\"language\":\"azerbaijani\"}");

        GroqSpeechToTextService.TranscriptionResult result = service.transcribe(
                new byte[]{1}, "a.wav", "audio/wav", "en_US");

        assertTrue(result.otherLanguage());
        assertTrue(result.lowConfidence());
        assertEquals("Merhaba, biraz su alabilir miyiz?", result.heardAs());
        assertEquals("Hello, can you please take a while?", result.text(),
                "the pinned transcript is unchanged; the app chooses what to show");
    }

    /**
     * A learner who mixes the languages is sent as they spoke.
     *
     * <p>Measured on a device: "Spaghetti Pomodoro sounds good and also, merhaba, biraz su
     * alabilir miyiz?" -- both languages written faithfully by the pinned pass, at a
     * confident -0.18, and labelled Turkish by the free one. There is nothing invented in
     * that transcript to protect anyone from; what reaches the tutor is what they said.
     */
    @Test
    void transcribeShouldNotHoldAMixedSentenceBothPassesWroteTheSame() {
        ReflectionTestUtils.setField(service, "detectLanguage", true);
        String mixed = "Spaghetti Pomodoro sounds good and also, merhaba, biraz su alabilir miyiz?";
        stubBothPasses(
                "{\"text\":\"" + mixed + "\",\"segments\":[{\"no_speech_prob\":0.02,\"avg_logprob\":-0.18}]}",
                "{\"text\":\"" + mixed + "\",\"language\":\"turkish\"}");

        GroqSpeechToTextService.TranscriptionResult result = service.transcribe(
                new byte[]{1}, "a.wav", "audio/wav", "en_US");

        assertFalse(result.otherLanguage());
        assertFalse(result.lowConfidence());
        assertEquals(mixed, result.text());
    }

    /**
     * A mixed sentence the pin mangled is held back.
     *
     * <p>Measured on a device: the Turkish half of a sentence came back as one nonsense word,
     * the two transcripts shared six words of ten -- exactly the old 0.6 -- and it went
     * straight to the tutor, where the card taught "a beer" for a request for water.
     */
    @Test
    void transcribeShouldHoldAMixedSentenceThePinMangled() {
        ReflectionTestUtils.setField(service, "detectLanguage", true);
        stubBothPasses(
                "{\"text\":\"I'd like the pasta, and also birasso?\",\"segments\":[{\"no_speech_prob\":0.02,\"avg_logprob\":-0.3}]}",
                "{\"text\":\"I'd like the pasta, and also biraz su alabilir miyiz?\",\"language\":\"turkish\"}");

        GroqSpeechToTextService.TranscriptionResult result = service.transcribe(
                new byte[]{1}, "a.wav", "audio/wav", "en_US");

        assertTrue(result.otherLanguage());
        assertTrue(result.lowConfidence(), "a mangled sentence reached the tutor unchecked");
    }

    @Test
    void theAgreementCheckCountsWordsNotPunctuation() {
        assertEquals(1.0, GroqSpeechToTextService.SpokenLanguage.wordOverlap(
                "Hi, good evening.", "hi good evening"), 0.0001);
        assertEquals(0.0, GroqSpeechToTextService.SpokenLanguage.wordOverlap(
                "Hello, can you please take a while?", "Merhaba, biraz su alabilir miyiz?"), 0.0001);
        assertEquals(0.0, GroqSpeechToTextService.SpokenLanguage.wordOverlap("", "anything"), 0.0001);
    }

    @Test
    void whatTheLearnerSaidIsNeverWrittenToTheLog() {
        // The verdict is logged on every turn; the free transcript is their own speech.
        GroqSpeechToTextService.SpokenLanguage spoken = new GroqSpeechToTextService.SpokenLanguage(
                true, "turkish", "Merhaba, biraz su alabilir miyiz?", 0.0);

        assertFalse(spoken.toString().contains("Merhaba"), spoken.toString());
        assertTrue(spoken.toString().contains("heardAsChars=33"), spoken.toString());
    }

    @Test
    void transcribeShouldReadTheScriptWhenTheProviderNamesNoLanguage() {
        // Groq's documented verbose_json example carries no language field. If it really
        // does not, the letters have to carry the verdict, or the feature silently does
        // nothing -- which is how the silence check spent a release.
        ReflectionTestUtils.setField(service, "detectLanguage", true);
        stubBothPasses(
                "{\"text\":\"No, so, so, name me.\"}",
                "{\"text\":\"Hayır, şöyle böyle, bana ad ver.\"}");

        GroqSpeechToTextService.TranscriptionResult result = service.transcribe(
                new byte[]{1}, "a.wav", "audio/wav", "en_US");

        assertTrue(result.otherLanguage());
        assertEquals("non-english-script", result.detectedLanguage());
        assertTrue(result.lowConfidence());
    }

    @Test
    void transcribeShouldNotGuessFromAnUnpinnedPassThatIsPlainAscii() {
        ReflectionTestUtils.setField(service, "detectLanguage", true);
        stubBothPasses("{\"text\":\"I want some coffee.\"}", "{\"text\":\"I want some coffee.\"}");

        GroqSpeechToTextService.TranscriptionResult result = service.transcribe(
                new byte[]{1}, "a.wav", "audio/wav", "en_US");

        assertFalse(result.otherLanguage());
        assertNull(result.detectedLanguage());
        assertFalse(result.lowConfidence());
    }

    @Test
    void transcribeShouldNeverWarnBecauseDetectionFailed() {
        // The transcript the learner is waiting on is not hostage to the check, and a check
        // that failed is not evidence of anything.
        ReflectionTestUtils.setField(service, "detectLanguage", true);
        when(restTemplate.postForEntity(eq("https://groq.test/audio/transcriptions"),
                org.mockito.ArgumentMatchers.any(HttpEntity.class),
                eq(String.class)))
                .thenAnswer(invocation -> {
                    HttpEntity<?> request = invocation.getArgument(1);
                    if (!multipartBody(request).containsKey("language")) {
                        throw new HttpClientErrorException(HttpStatus.TOO_MANY_REQUESTS);
                    }
                    return new ResponseEntity<>("{\"text\":\"I want some coffee.\"}", HttpStatus.OK);
                });

        GroqSpeechToTextService.TranscriptionResult result = service.transcribe(
                new byte[]{1}, "a.wav", "audio/wav", "en_US");

        assertEquals("I want some coffee.", result.text());
        assertFalse(result.otherLanguage());
        assertFalse(result.lowConfidence());
    }

    @Test
    void theUnpinnedPassCarriesNoLanguageAndNoPrompt() {
        // Either would pull the detection toward English, which is the one answer it must
        // be free to disagree with.
        ReflectionTestUtils.setField(service, "detectLanguage", true);
        ReflectionTestUtils.setField(service, "prompt", "");
        stubBothPasses("{\"text\":\"I agree.\"}", "{\"text\":\"I agree.\",\"language\":\"english\"}");

        service.transcribe(new byte[]{1}, "a.wav", "audio/wav", "en_US",
                java.util.List.of("agree", "married"));

        ArgumentCaptor<HttpEntity> entityCaptor = ArgumentCaptor.forClass(HttpEntity.class);
        verify(restTemplate, times(2)).postForEntity(
                eq("https://groq.test/audio/transcriptions"), entityCaptor.capture(), eq(String.class));
        MultiValueMap<String, Object> pinned = null;
        MultiValueMap<String, Object> unpinned = null;
        for (HttpEntity<?> request : entityCaptor.getAllValues()) {
            MultiValueMap<String, Object> body = multipartBody(request);
            if (body.containsKey("language")) {
                pinned = body;
            } else {
                unpinned = body;
            }
        }
        assertEquals("en", pinned.getFirst("language"));
        assertTrue(String.valueOf(pinned.getFirst("prompt")).contains("agree"),
                "The main pass keeps the learner's own words");
        assertNull(unpinned.getFirst("language"));
        assertNull(unpinned.getFirst("prompt"));
        assertEquals("verbose_json", unpinned.getFirst("response_format"));
    }

    @Test
    void aDiscardedTranscriptIsNotHeldForItsLanguageEither() {
        // There is nothing to hold; the silence path already handled it.
        ReflectionTestUtils.setField(service, "detectLanguage", true);
        stubBothPasses(
                "{\"text\":\"Thank you.\",\"segments\":[{\"no_speech_prob\":0.94,\"avg_logprob\":-1.7}]}",
                "{\"text\":\"Teşekkürler.\",\"language\":\"turkish\"}");

        GroqSpeechToTextService.TranscriptionResult result = service.transcribe(
                new byte[]{1}, "a.wav", "audio/wav", "en_US");

        assertEquals("", result.text());
        assertFalse(result.otherLanguage());
        assertFalse(result.lowConfidence());
    }

    /**
     * The pin not holding is itself the evidence.
     *
     * <p>On the device, a Turkish sentence sent to a request pinned to English came back as
     * "Selam nasılsın?". The fallback only looked for foreign letters in the free pass when
     * the pinned one had none, so with both in Turkish it said nothing at all.
     */
    @Test
    void aPinnedTranscriptInAnotherLanguageIsHeldEvenWhenBothPassesAgree() {
        ReflectionTestUtils.setField(service, "detectLanguage", true);
        stubBothPasses("{\"text\":\"Selam nasılsın?\"}", "{\"text\":\"Selam nasılsın?\"}");

        GroqSpeechToTextService.TranscriptionResult result = service.transcribe(
                new byte[]{1}, "a.wav", "audio/wav", "en_US");

        assertEquals("Selam nasılsın?", result.text());
        assertTrue(result.otherLanguage());
        assertTrue(result.lowConfidence());
    }

    @Test
    void aPinnedTranscriptInAnotherLanguageIsHeldEvenWhenTheSecondPassFails() {
        ReflectionTestUtils.setField(service, "detectLanguage", true);
        when(restTemplate.postForEntity(eq("https://groq.test/audio/transcriptions"),
                org.mockito.ArgumentMatchers.any(HttpEntity.class),
                eq(String.class)))
                .thenAnswer(invocation -> {
                    HttpEntity<?> request = invocation.getArgument(1);
                    if (!multipartBody(request).containsKey("language")) {
                        throw new HttpClientErrorException(HttpStatus.TOO_MANY_REQUESTS);
                    }
                    return new ResponseEntity<>("{\"text\":\"Selam nasılsın?\"}", HttpStatus.OK);
                });

        GroqSpeechToTextService.TranscriptionResult result = service.transcribe(
                new byte[]{1}, "a.wav", "audio/wav", "en_US");

        assertTrue(result.otherLanguage());
        assertTrue(result.lowConfidence());
    }

    @Test
    void aServiceConfiguredForAnotherLanguageIsNeverHeldForSpeakingIt() {
        // Every rule in the check is "is this English?". Asked of a service configured for
        // Turkish, a Turkish transcript is the right answer, not a warning -- and no second
        // pass is spent asking.
        ReflectionTestUtils.setField(service, "detectLanguage", true);
        ReflectionTestUtils.setField(service, "language", "tr");
        when(restTemplate.postForEntity(eq("https://groq.test/audio/transcriptions"),
                org.mockito.ArgumentMatchers.any(HttpEntity.class),
                eq(String.class)))
                .thenReturn(new ResponseEntity<>("{\"text\":\"Selam nasılsın?\"}", HttpStatus.OK));

        GroqSpeechToTextService.TranscriptionResult result = service.transcribe(
                new byte[]{1}, "a.wav", "audio/wav", "tr_TR");

        assertFalse(result.otherLanguage());
        assertFalse(result.lowConfidence());
        verify(restTemplate, times(1)).postForEntity(
                eq("https://groq.test/audio/transcriptions"),
                org.mockito.ArgumentMatchers.any(HttpEntity.class),
                eq(String.class));
    }

    private MultiValueMap<String, Object> capturedBody() {
        ArgumentCaptor<HttpEntity> entityCaptor = ArgumentCaptor.forClass(HttpEntity.class);
        verify(restTemplate).postForEntity(
                eq("https://groq.test/audio/transcriptions"),
                entityCaptor.capture(),
                eq(String.class));
        return multipartBody(entityCaptor.getValue());
    }

    @SuppressWarnings("unchecked")
    private MultiValueMap<String, Object> multipartBody(HttpEntity<?> request) {
        return (MultiValueMap<String, Object>) assertInstanceOf(MultiValueMap.class, request.getBody());
    }
}
