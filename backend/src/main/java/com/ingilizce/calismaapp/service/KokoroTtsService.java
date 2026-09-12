package com.ingilizce.calismaapp.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.Base64;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Stream;

/**
 * The voice the learner hears, from Kokoro.
 *
 * <p>Kokoro-82M is Apache 2.0 -- its model card says the weights can be deployed anywhere
 * "from production environments to personal projects" -- which the two best Piper voices in
 * this app were not: the Blizzard 2013 Lessac agreement excludes "any commercial purpose,
 * including the development, marketing, commercialisation, sale or licencing of voice
 * synthesis ... products or services", and RyanSpeech is CC BY-NC-SA 4.0. It also simply
 * sounds better, which is why it was already the plan.
 *
 * <p>It runs as its own container beside the backend and speaks the OpenAI audio API. The
 * app keeps sending the voice ids it always has ("amy", "ryan", ...); {@link #voiceFor} maps
 * them here, so the engine changed without an app release. Empty base URL means disabled,
 * and {@link SpeechService} then falls back to Piper.
 *
 * <p>Measured on the server: about 2.4 s for a reply of eight seconds of speech, against
 * 0.35 s for Piper's medium and 1.1 s for its high. The cache below is what keeps a replay
 * or a repeated sentence from paying that again.
 */
@Service
public class KokoroTtsService {

    private static final Logger log = LoggerFactory.getLogger(KokoroTtsService.class);
    private static final ObjectMapper JSON = new ObjectMapper();

    /** Empty disables Kokoro entirely: no calls, no cache, and Piper answers. */
    @Value("${kokoro.tts.base-url:}")
    private String baseUrl;

    @Value("${kokoro.tts.model:kokoro}")
    private String model;

    /**
     * The app's voice ids, mapped to Kokoro's. Kept as a property so a voice can be changed
     * on the server without a release. "ryan" and "lessac" are still ids the app and the
     * saved conversations use; what they now name is a Kokoro voice of the same gender and
     * accent, not the model whose licence forbids selling it.
     */
    @Value("${kokoro.tts.voices:amy=af_heart,ryan=am_michael,lessac=af_bella,cori=bf_emma,jenny=bf_isabella,alan=bm_george}")
    private String voiceMapping;

    @Value("${kokoro.tts.default-voice:af_heart}")
    private String defaultVoice;

    @Value("${app.tts.cache-enabled:true}")
    private boolean cacheEnabled = false;

    @Value("${app.tts.cache-dir:}")
    private String configuredCacheDir;

    @Value("${app.tts.cache-max-entries:20000}")
    private int cacheMaxEntries = 20000;

    private final RestTemplate restTemplate;

    public KokoroTtsService() {
        this(defaultRestTemplate());
    }

    KokoroTtsService(RestTemplate restTemplate) {
        this.restTemplate = restTemplate;
    }

    private static RestTemplate defaultRestTemplate() {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(3_000);
        // A long reply is a few seconds of synthesis on a CPU; the learner is waiting, but a
        // timeout here means no voice at all, so it is generous rather than tight.
        factory.setReadTimeout(30_000);
        return new RestTemplate(factory);
    }

    public boolean isEnabled() {
        return baseUrl != null && !baseUrl.isBlank();
    }

    /**
     * One throwaway line at startup, so the first learner does not pay for the model loading.
     *
     * <p>Measured after a restart: the first reply of the day took 8.4 s to speak where the
     * same length later took 2.3 s. Kokoro loads its voice on the first request it is given,
     * and the person who happened to be talking to the tutor was the one who waited. Now the
     * backend is that person.
     *
     * <p>On its own thread: this must not hold up the application coming ready, and a Kokoro
     * that is still starting itself is an ordinary failure here -- the next real request pays
     * what it would have paid anyway.
     */
    @EventListener(ApplicationReadyEvent.class)
    public void warmUpInBackground() {
        if (!isEnabled()) {
            return;
        }
        Thread warmUp = new Thread(this::warmUp, "kokoro-warm-up");
        warmUp.setDaemon(true);
        warmUp.start();
    }

    void warmUp() {
        long startedNs = System.nanoTime();
        String audio = synthesize("Hello.", null);
        log.info("TIMING tts engine=kokoro warm-up ms={} ready={}",
                elapsedMs(startedNs), audio != null);
    }

    /** Base64 WAV in [voice], or null if Kokoro is off or could not answer. */
    public String synthesize(String text, String voice) {
        if (!isEnabled() || text == null || text.isBlank()) {
            return null;
        }
        long startedNs = System.nanoTime();
        String kokoroVoice = voiceFor(voice);
        Path cacheFile = cacheEnabled ? cacheFileFor(kokoroVoice, text) : null;
        if (cacheFile != null) {
            byte[] cached = readCached(cacheFile);
            if (cached != null) {
                log.info("TIMING tts engine=kokoro cache=hit voice={} chars={} ms={}",
                        kokoroVoice, text.length(), elapsedMs(startedNs));
                return Base64.getEncoder().encodeToString(cached);
            }
        }
        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            headers.setAccept(List.of(MediaType.parseMediaType("audio/wav"), MediaType.ALL));
            Map<String, Object> body = new LinkedHashMap<>();
            body.put("model", model);
            body.put("input", text.trim());
            body.put("voice", kokoroVoice);
            body.put("response_format", "wav");
            byte[] audio = restTemplate.postForObject(
                    baseUrl.trim().replaceAll("/+$", "") + "/v1/audio/speech",
                    new HttpEntity<>(JSON.writeValueAsString(body), headers),
                    byte[].class);
            if (audio == null || audio.length == 0) {
                log.warn("Kokoro returned no audio for {} characters in {}", text.length(), kokoroVoice);
                return null;
            }
            if (cacheFile != null) {
                writeCached(cacheFile, audio);
            }
            log.info("TIMING tts engine=kokoro cache=miss voice={} chars={} ms={} bytes={}",
                    kokoroVoice, text.length(), elapsedMs(startedNs), audio.length);
            return Base64.getEncoder().encodeToString(audio);
        } catch (Exception e) {
            log.warn("Kokoro could not speak; falling back: {}", e.toString());
            return null;
        }
    }

    /** The Kokoro voice for one of the app's voice ids, or the default for an unknown one. */
    String voiceFor(String voice) {
        String key = voice == null ? "" : voice.trim().toLowerCase(Locale.ROOT);
        for (String pair : voiceMapping.split(",")) {
            int equals = pair.indexOf('=');
            if (equals > 0 && pair.substring(0, equals).trim().toLowerCase(Locale.ROOT).equals(key)) {
                String mapped = pair.substring(equals + 1).trim();
                if (!mapped.isEmpty()) {
                    return mapped;
                }
            }
        }
        return defaultVoice;
    }

    // The cache is Piper's policy, written again rather than shared: Piper's is tied to its
    // own test seams, and one sentence in one voice is one file either way. The key includes
    // the voice, so the same line in two voices is two entries.
    private Path cacheFileFor(String voice, String text) {
        try {
            byte[] hash = MessageDigest.getInstance("SHA-256")
                    .digest(("kokoro\n" + voice + "\n" + text).getBytes(java.nio.charset.StandardCharsets.UTF_8));
            return cacheDir().resolve(java.util.HexFormat.of().formatHex(hash) + ".wav");
        } catch (Exception e) {
            log.debug("Kokoro cache key failed: {}", e.toString());
            return null;
        }
    }

    private Path cacheDir() {
        if (configuredCacheDir != null && !configuredCacheDir.isBlank()) {
            return Paths.get(configuredCacheDir.trim());
        }
        return Paths.get(System.getProperty("java.io.tmpdir"), "piper-tts-cache");
    }

    private byte[] readCached(Path cacheFile) {
        try {
            if (Files.isRegularFile(cacheFile)) {
                byte[] audio = Files.readAllBytes(cacheFile);
                Files.setLastModifiedTime(cacheFile, java.nio.file.attribute.FileTime.from(Instant.now()));
                return audio;
            }
        } catch (IOException e) {
            log.debug("Kokoro cache read failed: {}", e.toString());
        }
        return null;
    }

    private void writeCached(Path cacheFile, byte[] audio) {
        try {
            Files.createDirectories(cacheFile.getParent());
            Path tmp = cacheFile.resolveSibling(cacheFile.getFileName() + ".tmp-" + UUID.randomUUID());
            Files.write(tmp, audio);
            Files.move(tmp, cacheFile, StandardCopyOption.REPLACE_EXISTING);
            evict(cacheFile.getParent());
        } catch (IOException e) {
            log.debug("Kokoro cache write failed: {}", e.toString());
        }
    }

    private void evict(Path dir) {
        if (cacheMaxEntries <= 0) {
            return;
        }
        try (Stream<Path> entries = Files.list(dir)) {
            List<Path> files = entries
                    .filter(p -> p.getFileName().toString().endsWith(".wav"))
                    .sorted(Comparator.comparingLong(p -> p.toFile().lastModified()))
                    .toList();
            for (int i = 0; i < files.size() - cacheMaxEntries; i++) {
                Files.deleteIfExists(files.get(i));
            }
        } catch (IOException e) {
            log.debug("Kokoro cache eviction failed: {}", e.toString());
        }
    }

    private static long elapsedMs(long startedNs) {
        return (System.nanoTime() - startedNs) / 1_000_000L;
    }
}
