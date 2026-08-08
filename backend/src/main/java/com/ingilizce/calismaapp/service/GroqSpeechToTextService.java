package com.ingilizce.calismaapp.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Service;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.RestClientResponseException;
import org.springframework.web.client.RestTemplate;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;

@Service
public class GroqSpeechToTextService {
    private static final Logger log = LoggerFactory.getLogger(GroqSpeechToTextService.class);

    /** Tek bir kelimenin ses içindeki zaman aralığı (saniye). */
    public record WordTiming(String word, double start, double end) {
    }

    /**
     * durationSeconds: Whisper'ın ölçtüğü gerçek ses süresi - istemci
     * duvar-saati (dokunma gecikmesi dahil) yerine dürüst hız hesabı sağlar.
     * words: kelime bazlı zaman damgaları (duraksamayı yakalamak için);
     * sağlayıcı vermezse boş liste.
     */
    public record TranscriptionResult(String text,
                                      String model,
                                      Double durationSeconds,
                                      List<WordTiming> words) {
        public TranscriptionResult(String text, String model) {
            this(text, model, null, List.of());
        }
    }

    @Value("${groq.api.key:}")
    private String apiKey;

    @Value("${groq.speech.api.url:https://api.groq.com/openai/v1/audio/transcriptions}")
    private String transcriptionUrl;

    @Value("${groq.speech.model:whisper-large-v3-turbo}")
    private String model;

    @Value("${groq.speech.language:en}")
    private String language;

    @Value("${groq.speech.prompt:English learning conversation. Transcribe the learner's English speech exactly.}")
    private String prompt;

    private final RestTemplate restTemplate;
    private final ObjectMapper objectMapper;

    public GroqSpeechToTextService() {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(30000);
        factory.setReadTimeout(60000);
        this.restTemplate = new RestTemplate(factory);
        this.objectMapper = new ObjectMapper();
    }

    public TranscriptionResult transcribe(byte[] audioBytes,
                                          String filename,
                                          String contentType,
                                          String requestedLocale) {
        if (apiKey == null || apiKey.isBlank()) {
            throw new IllegalStateException("Groq API key is not configured");
        }
        if (audioBytes == null || audioBytes.length == 0) {
            throw new IllegalArgumentException("Audio file is empty");
        }

        String selectedLanguage = resolveLanguage(requestedLocale);
        String safeFilename = sanitizeFilename(filename);

        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setBearerAuth(apiKey);
            headers.setContentType(MediaType.MULTIPART_FORM_DATA);

            MultiValueMap<String, Object> body = new LinkedMultiValueMap<>();
            body.add("model", model);
            body.add("language", selectedLanguage);
            body.add("temperature", "0");
            // verbose_json: ölçülen ses süresi + kelime zaman damgaları.
            // Aynı fiyat, aynı gecikme sınıfı; "json" yalnızca text döndürüyordu.
            body.add("response_format", "verbose_json");
            body.add("timestamp_granularities[]", "word");
            // Both, not just word. Asking for word timestamps alone makes the API drop the
            // `segments` array, and `segments` is the only place no_speech_prob and
            // avg_logprob appear — the two numbers the silence check depends on. Without
            // this the check received nothing, correctly declined to guess, and passed every
            // hallucinated transcript straight through while looking like it was working.
            body.add("timestamp_granularities[]", "segment");
            if (prompt != null && !prompt.isBlank()) {
                body.add("prompt", prompt.trim());
            }

            HttpHeaders fileHeaders = new HttpHeaders();
            fileHeaders.setContentType(resolveMediaType(contentType, safeFilename));
            body.add("file", new HttpEntity<>(new NamedByteArrayResource(audioBytes, safeFilename), fileHeaders));

            ResponseEntity<String> response = restTemplate.postForEntity(
                    transcriptionUrl,
                    new HttpEntity<>(body, headers),
                    String.class);

            Map<String, Object> payload = objectMapper.readValue(
                    response.getBody(),
                    new TypeReference<Map<String, Object>>() {
                    });
            String text = payload.get("text") == null ? "" : payload.get("text").toString().trim();
            // Logged every time, not only on a discard. The silence check spent a whole
            // release doing nothing because `segments` was absent from the response and the
            // code — correctly — refuses to guess from missing data. Silently declining to
            // act is indistinguishable from acting correctly, so the inputs to the decision
            // have to be visible.
            log.info("Speech confidence: {}", describeConfidence(payload.get("segments")));
            if (segmentsLookLikeSilence(payload.get("segments"))) {
                log.info("Discarding transcript: model reports no speech. text='{}'", text);
                text = "";
            } else if (isHallucinatedSilence(text)) {
                log.info("Discarding hallucinated transcript for silent audio: '{}'", text);
                text = "";
            }
            Double durationSeconds = parseDuration(payload.get("duration"));
            List<WordTiming> words = parseWordTimings(payload.get("words"));
            return new TranscriptionResult(text, model, durationSeconds, words);
        } catch (RestClientResponseException e) {
            log.warn("Groq speech transcription failed: status={}, body={}", e.getStatusCode(), e.getResponseBodyAsString());
            throw new RuntimeException("Groq speech transcription failed: " + e.getStatusCode(), e);
        } catch (Exception e) {
            log.warn("Groq speech transcription failed: {}", e.getMessage());
            throw new RuntimeException("Groq speech transcription failed", e);
        }
    }

    /** OpenAI's own decoding defaults for "this segment contains no speech". */
    static final double NO_SPEECH_PROB_THRESHOLD = 0.6;
    static final double AVG_LOGPROB_THRESHOLD = -1.0;

    /**
     * Asks the model whether it actually heard anything, instead of guessing from the words.
     *
     * <p>{@code verbose_json} returns a {@code no_speech_prob} and an {@code avg_logprob}
     * per segment — Whisper's own confidence that the audio was silence, and how sure it was
     * of the text it produced anyway. Both thresholds must trip together, which is the
     * combination OpenAI's reference decoder uses: high no-speech probability alone can fire
     * on quiet but real speech, and low log-probability alone fires on unusual accents.
     * Requiring both is what keeps a learner's genuine attempt from being deleted.
     *
     * <p>This exists because string matching was not enough. The marker list below caught the
     * subtitle boilerplate, and then the very next recording of the same silent room came
     * back as "Thank you." — which is also one of Whisper's most common silence outputs, and
     * is also something a learner plainly might say. There is no wording that separates
     * those two cases. The model's own confidence does.
     */
    static boolean segmentsLookLikeSilence(Object rawSegments) {
        if (!(rawSegments instanceof List<?> segments) || segments.isEmpty()) {
            return false;
        }
        for (Object entry : segments) {
            if (!(entry instanceof Map<?, ?> segment)) {
                return false;
            }
            Double noSpeech = asDouble(segment.get("no_speech_prob"));
            Double avgLogprob = asDouble(segment.get("avg_logprob"));
            if (noSpeech == null || avgLogprob == null) {
                // Older or partial responses: fall through to the marker list rather than
                // guessing from missing data.
                return false;
            }
            boolean silent = noSpeech > NO_SPEECH_PROB_THRESHOLD && avgLogprob < AVG_LOGPROB_THRESHOLD;
            if (!silent) {
                // One segment with real speech is enough to keep the whole transcript.
                return false;
            }
        }
        return true;
    }

    private static Double asDouble(Object raw) {
        return raw instanceof Number number ? number.doubleValue() : null;
    }

    /** One log line saying what the silence check actually had to work with. */
    static String describeConfidence(Object rawSegments) {
        if (!(rawSegments instanceof List<?> segments)) {
            return "no segments in response";
        }
        if (segments.isEmpty()) {
            return "segments empty";
        }
        StringBuilder sb = new StringBuilder(segments.size() + " segment(s)");
        for (Object entry : segments) {
            if (entry instanceof Map<?, ?> segment) {
                sb.append(" [noSpeech=").append(segment.get("no_speech_prob"))
                        .append(" avgLogprob=").append(segment.get("avg_logprob")).append(']');
            }
        }
        return sb.toString();
    }

    /**
     * Whisper credits a subtitling company when it is handed silence.
     *
     * <p>Given near-silent audio the model does not return nothing — it returns fluent,
     * confident text copied from the subtitle files it was trained on. A four-second
     * recording of an empty room produced: "English learning conversation. Transcribe or the
     * stream of language can be seen in general. Transcription by CastingWords. You can
     * still explain your presence in learning..."
     *
     * <p>In this app that transcript is auto-sent the moment it arrives. So a learner who
     * taps the microphone and hesitates has words put in their mouth, watches the tutor
     * answer a question they never asked, and pays for it out of their daily token budget.
     * For somebody learning the language, being unable to tell "the app misheard me" from
     * "I said something wrong" is the worst possible failure here.
     *
     * <p>These strings are artefacts of Whisper's training data, not of anything the learner
     * did, so they are matched literally. The list is deliberately narrow: a false positive
     * would silently drop real speech, which is the mistake we are trying to avoid, so
     * anything not clearly boilerplate is passed through.
     */
    static boolean isHallucinatedSilence(String text) {
        if (text == null || text.isBlank()) {
            return true;
        }
        String normalized = text.toLowerCase(Locale.ROOT);
        for (String marker : SILENCE_HALLUCINATION_MARKERS) {
            if (normalized.contains(marker)) {
                return true;
            }
        }
        // A transcript with no letters at all — "...", "[Music]", stray punctuation — is not
        // speech either.
        return normalized.chars().noneMatch(Character::isLetter);
    }

    private static final List<String> SILENCE_HALLUCINATION_MARKERS = List.of(
            "castingwords",
            "amara.org",
            "subtitles by",
            "subtitled by",
            "subtitles provided by",
            "transcription by",
            "transcript by",
            "thanks for watching",
            "thank you for watching",
            "please subscribe",
            "www.",
            "[music]",
            "[applause]",
            "[silence]",
            "altyazı m.k.");

    private Double parseDuration(Object raw) {
        if (raw instanceof Number number) {
            double value = number.doubleValue();
            return value > 0 ? value : null;
        }
        return null;
    }

    private List<WordTiming> parseWordTimings(Object raw) {
        if (!(raw instanceof List<?> list)) {
            return List.of();
        }
        List<WordTiming> timings = new ArrayList<>(list.size());
        for (Object entry : list) {
            if (!(entry instanceof Map<?, ?> map)) {
                continue;
            }
            Object word = map.get("word");
            Object start = map.get("start");
            Object end = map.get("end");
            if (word instanceof String text && !text.isBlank()
                    && start instanceof Number startNum
                    && end instanceof Number endNum) {
                timings.add(new WordTiming(text.trim(),
                        startNum.doubleValue(),
                        endNum.doubleValue()));
            }
        }
        return List.copyOf(timings);
    }

    private String resolveLanguage(String requestedLocale) {
        String candidate = requestedLocale == null || requestedLocale.isBlank() ? language : requestedLocale;
        String normalized = candidate.trim().replace('_', '-').toLowerCase(Locale.ROOT);
        if (normalized.startsWith("en")) {
            return "en";
        }
        return language == null || language.isBlank() ? "en" : language.trim();
    }

    private String sanitizeFilename(String filename) {
        if (filename == null || filename.isBlank()) {
            return "speech.m4a";
        }
        String sanitized = filename.replaceAll("[^A-Za-z0-9._-]", "_");
        return sanitized.isBlank() ? "speech.m4a" : sanitized;
    }

    private MediaType resolveMediaType(String contentType, String filename) {
        if (contentType != null && !contentType.isBlank()) {
            try {
                return MediaType.parseMediaType(contentType);
            } catch (Exception ignored) {
            }
        }
        String lower = filename.toLowerCase(Locale.ROOT);
        if (lower.endsWith(".wav")) {
            return MediaType.parseMediaType("audio/wav");
        }
        if (lower.endsWith(".mp3")) {
            return MediaType.parseMediaType("audio/mpeg");
        }
        return MediaType.parseMediaType("audio/mp4");
    }

    private static final class NamedByteArrayResource extends ByteArrayResource {
        private final String filename;

        private NamedByteArrayResource(byte[] byteArray, String filename) {
            super(byteArray);
            this.filename = filename;
        }

        @Override
        public String getFilename() {
            return filename;
        }
    }
}
