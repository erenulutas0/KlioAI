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
