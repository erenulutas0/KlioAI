package com.ingilizce.calismaapp.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.Base64;
import java.util.Comparator;
import java.util.HexFormat;
import java.util.UUID;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Executor;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.locks.ReentrantLock;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.List;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;
import java.util.stream.Stream;

@Service
public class PiperTtsService {
    private static final Logger log = LoggerFactory.getLogger(PiperTtsService.class);

    @Value("${piper.tts.path:}")
    private String configuredPiperPath;

    @Value("${piper.tts.default-model:en_US-amy-medium.onnx}")
    private String configuredDefaultModel;

    // Cache is ON in Spring-managed runtime (placeholder default) but OFF for
    // plain `new PiperTtsService()` construction, so the existing seam-based
    // unit tests keep exercising the real synthesis path without cross-test
    // cache pollution. Piper output is deterministic per (model, text), which
    // is what makes disk caching safe here.
    @Value("${app.tts.cache-enabled:true}")
    private boolean cacheEnabled = false;

    @Value("${app.tts.cache-dir:}")
    private String configuredCacheDir;

    // 512 was far too small for a vocabulary app: the working set is the whole word list
    // plus its example sentences, and every eviction is a word that has to be re-synthesised
    // the next time somebody taps it. A cached WAV is a few tens of KB, so 20,000 entries is
    // well under a gigabyte -- cheap next to re-running Piper for words that never change.
    @Value("${app.tts.cache-max-entries:20000}")
    private int cacheMaxEntries = 20000;

    // How long a "yes, Piper is here" is trusted. The TTS endpoint asks before every
    // synthesis, and asking forks `piper --version` -- so without this, every reply the
    // tutor speaks paid for a process start first, cached single words included. Only a yes
    // is remembered: a Piper that was down is asked again on the next request, and is back
    // the moment it is. Off for plain `new`, like the audio cache, so each seam test still
    // exercises the real check.
    @Value("${app.tts.availability-cache-ms:60000}")
    private long availabilityCacheMs = 0;

    private volatile long availabilityConfirmedAtMs = -1;

    // One Piper per voice, kept running between replies. Measured on the server, loading the
    // voice was 0.24-0.43 s of every reply's synthesis, paid again each time because each
    // reply started a new process. Off for plain `new`, like the audio cache, so the seam
    // tests keep exercising the one-off path. See synthesizeResident.
    @Value("${app.tts.resident-enabled:true}")
    private boolean residentEnabled = false;

    // How long a running Piper may take over one line before it is presumed stuck and replaced.
    // A 400-character reply infers in well under two seconds on the server.
    @Value("${app.tts.resident-timeout-ms:15000}")
    private long residentTimeoutMs = 15000;

    private final Map<String, ResidentPiper> residents = new ConcurrentHashMap<>();
    private final Set<String> residentsStarting = ConcurrentHashMap.newKeySet();

    // --- KRİTİK DEĞİŞİKLİK BURADA ---
    // Modelleri Türkçe karakter sorunu olmaması için C:\piper klasöründen okuyoruz.
    // Docker'da /piper mount point'i kullanılır
    private static final String MODEL_BASE_DIR = System.getProperty("os.name").toLowerCase().contains("windows")
            ? "C:\\piper"
            : "/piper";

    // Model dosyaları, kalite sırasına göre (C:\piper klasöründe olmalı).
    //
    // Each voice lists its builds best-first. Every voice here was running at `-medium`,
    // which is the middle of Piper's four tiers (x_low, low, medium, high) -- so "Piper
    // sounds robotic" was partly a verdict on a model that was never Piper's best. A
    // learner mimics whatever pronunciation this produces, which makes it the wrong place
    // to leave quality on the table.
    //
    // Only some voices have a `high` build published; amy, alan and jenny do not, so those
    // stay at medium rather than pointing at a file that will never exist. Verified against
    // huggingface.co/rhasspy/piper-voices.
    //
    // The list is a preference order, not a requirement: a missing file falls through to
    // the next entry for THE SAME voice. That means this can ship before the .onnx files
    // are on the server -- nothing breaks, and each voice upgrades itself the moment its
    // high build is dropped in.
    private static final List<String> MODELS_LESSAC =
            List.of("en_US-lessac-high.onnx", "en_US-lessac-medium.onnx");
    private static final List<String> MODELS_RYAN =
            List.of("en_US-ryan-high.onnx", "en_US-ryan-medium.onnx");
    private static final List<String> MODELS_CORI =
            List.of("en_GB-cori-high.onnx", "en_GB-cori-medium.onnx");
    private static final List<String> MODELS_AMY = List.of("en_US-amy-medium.onnx");
    private static final List<String> MODELS_ALAN = List.of("en_GB-alan-medium.onnx");
    private static final List<String> MODELS_JENNY = List.of("en_GB-jenny_dioco-medium.onnx");

    /**
     * Generate speech audio from text using Piper TTS
     * 
     * @param text  Text to convert to speech
     * @param voice Voice model to use (lessac, amy, alan, ryan, etc.)
     * @return Base64 encoded WAV audio data
     */
    public String synthesizeSpeech(String text, String voice) {
        long startedNs = System.nanoTime();
        try {
            // Select model based on voice
            String modelFile = getModelFile(voice);

            Path cacheFile = cacheEnabled ? cacheFileFor(modelFile, text) : null;
            if (cacheFile != null) {
                byte[] cachedAudio = readCachedAudio(cacheFile);
                if (cachedAudio != null && cachedAudio.length > 0) {
                    log.info("TIMING tts cache=hit chars={} ms={}", text.length(), elapsedMs(startedNs));
                    return Base64.getEncoder().encodeToString(cachedAudio);
                }
            }

            // A voice already loaded in a running Piper answers without loading it again. Null
            // means it could not this time, and the one-off path below answers instead.
            if (residentEnabled) {
                byte[] residentAudio = synthesizeResident(modelFile, text);
                if (residentAudio != null && residentAudio.length > 0) {
                    if (cacheFile != null) {
                        writeCachedAudio(cacheFile, residentAudio);
                    }
                    log.info("TIMING tts cache=miss resident=true chars={} ms={} bytes={}",
                            text.length(), elapsedMs(startedNs), residentAudio.length);
                    return Base64.getEncoder().encodeToString(residentAudio);
                }
            }

            // Create temporary output file
            Path outputPath = createTempOutputPath();
            String outputFile = outputPath.toString();

            // Build Piper command - keep path resolution overridable for tests
            String absoluteModelPath = absolutePath(modelFile);

            // Verify model file exists
            if (!pathExists(absoluteModelPath)) {
                throw new RuntimeException("Model file not found at SAFE path: " + absoluteModelPath);
            }
            log.debug("Using SAFE model file: {}", absoluteModelPath);
            log.debug("Model file exists: {}", pathExists(absoluteModelPath));

            String piperPath = findPiperPath();
            log.debug("Using Piper path: {}", piperPath);

            // Working directory setup moved here
            File workingDir = new File(getModelBaseDir());

            List<String> command = new ArrayList<>();
            command.add(piperPath);
            command.add("--model");
            command.add(absoluteModelPath);
            command.add("--output_file");
            command.add(outputFile);

            Process process = startProcess(command, workingDir);

            // Write text to process stdin and explicitly close it
            OutputStream stdin = process.getOutputStream();
            try (BufferedWriter writer = new BufferedWriter(
                    new OutputStreamWriter(stdin, java.nio.charset.StandardCharsets.UTF_8))) {
                writer.write(text);
                writer.flush();
            } finally {
                // Explicitly close stdin to signal end of input
                try {
                    stdin.close();
                } catch (IOException e) {
                    log.warn("Error closing Piper stdin", e);
                }
            }

            // Read output/error stream in a separate thread to prevent blocking
            StringBuilder output = new StringBuilder();
            final Process finalProcess = process;

            Thread outputThread = new Thread(() -> {
                try (BufferedReader reader = new BufferedReader(
                        new InputStreamReader(finalProcess.getInputStream(),
                                java.nio.charset.StandardCharsets.UTF_8))) {
                    String line;
                    while ((line = reader.readLine()) != null) {
                        output.append(line).append("\n");
                        // Piper reports how long the voice took to load and how long the
                        // speech took to infer. Every call starts a new process, so the first
                        // is paid on every reply; these two lines are how we know how much.
                        if (line.contains("Loaded voice") || line.contains("Real-time factor")) {
                            log.info("TIMING piper {}", line.trim());
                        } else {
                            log.debug("Piper output: {}", line);
                        }
                    }
                } catch (IOException e) {
                    log.warn("Error reading Piper output", e);
                }
            });
            outputThread.setDaemon(true);
            outputThread.start();

            // Wait for process to complete with timeout (30 seconds)
            boolean finished = process.waitFor(30, TimeUnit.SECONDS);
            if (!finished) {
                process.destroyForcibly();
                throw new RuntimeException("Piper TTS process timed out after 30 seconds");
            }

            outputThread.join(5000); // Wait max 5 seconds for output thread

            int exitCode = process.exitValue();

            if (exitCode != 0) {
                String errorMsg = output.length() > 0 ? output.toString()
                        : "Unknown error (exit code: " + exitCode + ")";
                log.error("Piper TTS failed with exit code={}", exitCode);
                log.error("Piper output: {}", errorMsg);
                throw new RuntimeException("Piper TTS failed: " + errorMsg);
            }

            // Read generated audio file
            byte[] audioData = readAllBytes(outputPath);
            log.info("TIMING tts cache=miss resident=false chars={} ms={} bytes={}", text.length(),
                    elapsedMs(startedNs), audioData == null ? 0 : audioData.length);

            if (cacheFile != null && audioData != null && audioData.length > 0) {
                writeCachedAudio(cacheFile, audioData);
            }

            // Clean up temporary file
            deleteIfExists(outputPath);

            // Return base64 encoded audio
            return Base64.getEncoder().encodeToString(audioData);

        } catch (Exception e) {
            throw new RuntimeException("Failed to synthesize speech: " + e.getMessage(), e);
        }
    }

    private Path cacheFileFor(String modelFile, String text) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] hash = digest.digest((modelFile + "\n" + text).getBytes(StandardCharsets.UTF_8));
            return cacheDir().resolve(HexFormat.of().formatHex(hash) + ".wav");
        } catch (Exception e) {
            log.debug("Piper TTS cache key computation failed: {}", e.toString());
            return null;
        }
    }

    private Path cacheDir() {
        if (configuredCacheDir != null && !configuredCacheDir.isBlank()) {
            return Paths.get(configuredCacheDir.trim());
        }
        return Paths.get(System.getProperty("java.io.tmpdir"), "piper-tts-cache");
    }

    /** Best-effort cache read; any IO problem falls back to real synthesis. */
    protected byte[] readCachedAudio(Path cacheFile) {
        try {
            if (Files.isRegularFile(cacheFile)) {
                byte[] audio = Files.readAllBytes(cacheFile);
                touchForRecency(cacheFile);
                return audio;
            }
        } catch (IOException e) {
            log.debug("Piper TTS cache read failed for {}: {}", cacheFile, e.toString());
        }
        return null;
    }

    /** Best-effort cache write with atomic move; failures never break synthesis. */
    protected void writeCachedAudio(Path cacheFile, byte[] audioData) {
        try {
            Files.createDirectories(cacheFile.getParent());
            Path tmp = cacheFile.resolveSibling(cacheFile.getFileName() + ".tmp-" + UUID.randomUUID());
            Files.write(tmp, audioData);
            Files.move(tmp, cacheFile, StandardCopyOption.REPLACE_EXISTING);
            evictCacheIfNeeded(cacheFile.getParent());
        } catch (IOException e) {
            log.debug("Piper TTS cache write failed for {}: {}", cacheFile, e.toString());
        }
    }

    /**
     * Marks a cache entry as just-used, so eviction can order by last read.
     *
     * <p>{@link #evictCacheIfNeeded} sorts by last-modified time, which without this is the
     * time the file was written and never changes again — so eviction was really by age,
     * not by use. In a vocabulary app that is backwards: a common word heard every single
     * day would be deleted before a one-off generated sentence written yesterday, and then
     * re-synthesised from scratch. Touching on read turns the same eviction into a real LRU.
     */
    private void touchForRecency(Path cacheFile) {
        try {
            Files.setLastModifiedTime(cacheFile, java.nio.file.attribute.FileTime.from(Instant.now()));
        } catch (IOException e) {
            // Losing the recency hint only costs cache efficiency, never correctness.
            log.debug("Piper TTS cache touch failed for {}: {}", cacheFile, e.toString());
        }
    }

    private void evictCacheIfNeeded(Path dir) {
        if (cacheMaxEntries <= 0) {
            return;
        }
        try (Stream<Path> entries = Files.list(dir)) {
            List<Path> wavFiles = entries
                    .filter(p -> p.getFileName().toString().endsWith(".wav"))
                    .sorted(Comparator.comparingLong(p -> p.toFile().lastModified()))
                    .toList();
            int excess = wavFiles.size() - cacheMaxEntries;
            for (int i = 0; i < excess; i++) {
                Files.deleteIfExists(wavFiles.get(i));
            }
        } catch (IOException e) {
            log.debug("Piper TTS cache eviction failed for {}: {}", dir, e.toString());
        }
    }

    /**
     * Get model file path based on voice name
     */
    protected String getModelFile(String voice) {
        String normalizedVoice = normalizeVoice(voice);
        Map<String, List<String>> voiceModels = getVoiceModelMap();

        // Best available build of the voice that was actually asked for. Dropping to a
        // lower tier of the same speaker is a quality change; dropping to the default is a
        // different person reading to the learner mid-session, which is worse.
        List<String> requestedModels =
                voiceModels.getOrDefault(normalizedVoice, List.of(getDefaultModelName()));
        for (String candidate : requestedModels) {
            String candidatePath = getModelBaseDir() + File.separator + candidate;
            if (pathExists(candidatePath)) {
                log.debug("Selected model path (SAFE): {}", candidatePath);
                return candidatePath;
            }
        }

        if (!voiceModels.containsKey(normalizedVoice)) {
            log.warn("Unknown voice requested: {}, falling back to default model", voice);
        } else {
            log.warn("No model file present for voice {} (tried {})", normalizedVoice, requestedModels);
        }

        String defaultPath = getModelBaseDir() + File.separator + getDefaultModelName();
        if (pathExists(defaultPath)) {
            log.info("Falling back to configured default model: {}", defaultPath);
            return defaultPath;
        }

        String firstAvailable = resolveFirstAvailableModelPath();
        if (firstAvailable != null) {
            log.info("Falling back to first available model: {}", firstAvailable);
            return firstAvailable;
        }

        // Let caller fail with explicit model-not-found message.
        log.warn("No Piper model file found under {}", getModelBaseDir());
        return defaultPath;
    }

    /**
     * Find Piper executable path
     */
    protected String findPiperPath() {
        // First, try configured path
        if (configuredPiperPath != null && !configuredPiperPath.trim().isEmpty()) {
            String path = configuredPiperPath.trim();

            if (pathExists(path)) {
                return absolutePath(path);
            }
        }

        // Try common locations (including our new safe location)
        // Docker'da Linux path'leri, Windows'ta Windows path'leri
        boolean isWindows = isWindows();
        String[] pathsToTry = isWindows ? new String[] {
                "C:\\piper\\piper.exe", // Windows location
                "piper.exe",
                "piper"
        }
                : new String[] {
                        "/usr/local/bin/piper", // Docker installed location
                        "/piper/piper", // Docker mount location (fallback)
                        "piper"
                };

        for (String path : pathsToTry) {
            if (pathExists(path) && pathCanExecute(path)) {
                return absolutePath(path);
            }
            // Check if it's just a command available in PATH
            if (!path.contains(File.separator) && !path.contains("/") && !path.contains("\\")) {
                return path;
            }
        }

        return "piper";
    }

    /**
     * Check if Piper TTS is available
     */
    public boolean isAvailable() {
        long confirmedAt = availabilityConfirmedAtMs;
        if (availabilityCacheMs > 0 && confirmedAt >= 0
                && System.currentTimeMillis() - confirmedAt < availabilityCacheMs) {
            return true;
        }
        boolean available = checkAvailability();
        availabilityConfirmedAtMs = available ? System.currentTimeMillis() : -1;
        return available;
    }

    private boolean checkAvailability() {
        try {
            String piperPath = findPiperPath();
            log.debug("Trying Piper path: {}", piperPath);

            Process process = startAvailabilityProcess(piperPath);

            // Waited on, not polled: the old loop slept in 100 ms steps, so even a Piper
            // that answered in 5 ms cost a tenth of a second.
            process.waitFor(5, TimeUnit.SECONDS);

            if (process.isAlive()) {
                process.destroy();
                return false;
            }

            int exitCode = process.exitValue();

            String modelPath = resolveFirstAvailableModelPath();
            boolean modelExists = modelPath != null;

            log.debug("Piper TTS check - path: {}, exitCode: {}, modelPath: {}", piperPath, exitCode, modelPath);

            return exitCode == 0 && modelExists;
        } catch (Exception e) {
            log.warn("Piper TTS availability check failed", e);
            return false;
        }
    }

    /**
     * Speech from the running Piper for this voice, or null if it cannot answer right now.
     *
     * <p>Null covers every reason not to wait: the process is still starting (it was asked
     * for just now and is loading in the background), it is busy with another reply, it did
     * not answer within {@link #residentTimeoutMs}, or it has died. The caller then takes the
     * one-off path, so a reply is never slower than it was before this existed. A process
     * that failed is stopped and replaced on the next request.
     */
    private byte[] synthesizeResident(String modelFile, String text) {
        String modelPath = absolutePath(modelFile);
        if (!pathExists(modelPath)) {
            return null;
        }
        ResidentPiper resident = residentFor(modelPath);
        if (resident == null || !resident.lock.tryLock()) {
            return null;
        }
        Path outputPath = createTempOutputPath();
        try {
            if (!resident.speak(text, outputPath, residentTimeoutMs)) {
                log.warn("Resident Piper did not answer within {} ms for {}; replacing it",
                        residentTimeoutMs, modelPath);
                retire(modelPath, resident);
                return null;
            }
            return readAllBytes(outputPath);
        } catch (Exception e) {
            log.warn("Resident Piper failed for {}: {}", modelPath, e.toString());
            retire(modelPath, resident);
            return null;
        } finally {
            resident.lock.unlock();
            try {
                deleteIfExists(outputPath);
            } catch (IOException ignored) {
                // A stray temp file costs disk, never a reply.
            }
        }
    }

    /** The running Piper for [modelPath] if it is ready; otherwise starts one and returns null. */
    private ResidentPiper residentFor(String modelPath) {
        ResidentPiper resident = residents.get(modelPath);
        if (resident != null && resident.isAlive()) {
            return resident;
        }
        if (resident != null) {
            residents.remove(modelPath, resident);
        }
        if (residentsStarting.add(modelPath)) {
            residentStarter().execute(() -> {
                try {
                    ResidentPiper started = startResident(modelPath);
                    if (started != null) {
                        residents.put(modelPath, started);
                    }
                } finally {
                    residentsStarting.remove(modelPath);
                }
            });
        }
        ResidentPiper ready = residents.get(modelPath);
        return ready != null && ready.isAlive() ? ready : null;
    }

    /**
     * A new Piper for [modelPath], already warmed up, or null if it would not start.
     *
     * <p>The first line a fresh process speaks is the slow one -- the voice loads, and the
     * first inference warms the runtime -- so it is spent on a throwaway word, in the
     * background, and no learner waits for it.
     */
    private ResidentPiper startResident(String modelPath) {
        long startedNs = System.nanoTime();
        Path warmup = createTempOutputPath();
        ResidentPiper resident = null;
        try {
            // No --output_file: with it Piper reads to the end of its input and writes one file,
            // which a process that is meant to keep running never reaches.
            List<String> command = List.of(findPiperPath(), "--model", modelPath, "--json-input",
                    "--output_dir", System.getProperty("java.io.tmpdir"));
            resident = new ResidentPiper(startResidentProcess(command, new File(getModelBaseDir())));
            if (!resident.speak("Hello.", warmup, residentTimeoutMs)) {
                log.warn("A resident Piper for {} did not answer its warm-up line", modelPath);
                resident.stop();
                return null;
            }
            log.info("TIMING tts resident-ready model={} ms={}",
                    Paths.get(modelPath).getFileName(), elapsedMs(startedNs));
            return resident;
        } catch (Exception e) {
            log.warn("Could not start a resident Piper for {}: {}", modelPath, e.toString());
            if (resident != null) {
                resident.stop();
            }
            return null;
        } finally {
            try {
                deleteIfExists(warmup);
            } catch (IOException ignored) {
                // Same as above.
            }
        }
    }

    private void retire(String modelPath, ResidentPiper resident) {
        residents.remove(modelPath, resident);
        resident.stop();
    }

    @jakarta.annotation.PreDestroy
    void stopResidents() {
        residents.values().forEach(ResidentPiper::stop);
        residents.clear();
    }

    /**
     * Starts a Piper that stays running. Protected to allow a fake in tests.
     *
     * <p>Unlike {@link #startProcess}, stderr is kept apart: stdout carries only Piper's
     * answers, one output path per line, and a log line mixed into it would be read as one.
     */
    protected Process startResidentProcess(List<String> command, File workingDir) throws IOException {
        ProcessBuilder processBuilder = new ProcessBuilder(command);
        if (workingDir != null && workingDir.exists()) {
            processBuilder.directory(workingDir);
        }
        return processBuilder.start();
    }

    /** Where a resident Piper is started. A daemon thread, so no request waits on it. */
    protected Executor residentStarter() {
        return task -> {
            Thread thread = new Thread(task, "piper-resident-start");
            thread.setDaemon(true);
            thread.start();
        };
    }

    /**
     * One running `piper --json-input`: a JSON line in, the WAV written, its path printed back.
     *
     * <p>The path comes back only after the file is complete, so reading it the moment the
     * line arrives is safe. One line at a time, under {@link #lock}.
     */
    static final class ResidentPiper {
        private static final ObjectMapper JSON = new ObjectMapper();

        final ReentrantLock lock = new ReentrantLock();
        private final Process process;
        private final BufferedWriter stdin;
        private final BlockingQueue<String> answers = new LinkedBlockingQueue<>();

        ResidentPiper(Process process) {
            this.process = process;
            this.stdin = new BufferedWriter(
                    new OutputStreamWriter(process.getOutputStream(), StandardCharsets.UTF_8));
            Thread out = new Thread(() -> {
                try (BufferedReader reader = new BufferedReader(
                        new InputStreamReader(process.getInputStream(), StandardCharsets.UTF_8))) {
                    String line;
                    while ((line = reader.readLine()) != null) {
                        answers.offer(line.trim());
                    }
                } catch (IOException ignored) {
                    // The process is gone; speak() sees it time out or the process dead.
                }
            }, "piper-resident-out");
            out.setDaemon(true);
            out.start();
            // Piper's own log. Its "Real-time factor" line is a running total in this mode, not
            // the cost of the line just spoken, so it stays at debug; TIMING tts carries the real
            // figure per reply.
            Thread err = new Thread(() -> {
                try (BufferedReader reader = new BufferedReader(
                        new InputStreamReader(process.getErrorStream(), StandardCharsets.UTF_8))) {
                    String line;
                    while ((line = reader.readLine()) != null) {
                        log.debug("Resident Piper: {}", line);
                    }
                } catch (IOException ignored) {
                    // Nothing to log from a process that is gone.
                }
            }, "piper-resident-err");
            err.setDaemon(true);
            err.start();
        }

        /** Speaks [text] into [outputPath]; false if Piper did not answer with it in time. */
        boolean speak(String text, Path outputPath, long timeoutMs) throws IOException, InterruptedException {
            if (!process.isAlive()) {
                return false;
            }
            answers.clear();
            // JSON, so a newline or a quotation mark in the reply stays inside one line.
            stdin.write(JSON.writeValueAsString(Map.of("text", text, "output_file", outputPath.toString())));
            stdin.write('\n');
            stdin.flush();
            String answer = answers.poll(timeoutMs, TimeUnit.MILLISECONDS);
            return answer != null && answer.endsWith(outputPath.getFileName().toString());
        }

        boolean isAlive() {
            return process.isAlive();
        }

        void stop() {
            try {
                stdin.close();
            } catch (IOException ignored) {
                // Closing is a courtesy; destroy below is the stop.
            }
            process.destroy();
        }
    }

    private static long elapsedMs(long startedNs) {
        return (System.nanoTime() - startedNs) / 1_000_000L;
    }

    public String[] getSupportedVoices() {
        Map<String, List<String>> voiceModels = getVoiceModelMap();
        Set<String> supported = new LinkedHashSet<>();

        String defaultPath = getModelBaseDir() + File.separator + getDefaultModelName();
        if (pathExists(defaultPath)) {
            supported.add("default");
        }

        for (Map.Entry<String, List<String>> entry : voiceModels.entrySet()) {
            String voice = entry.getKey();
            if ("default".equals(voice)) {
                continue;
            }

            // Offered if any build of it is installed, whatever the tier.
            for (String modelName : entry.getValue()) {
                if (pathExists(getModelBaseDir() + File.separator + modelName)) {
                    supported.add(voice);
                    break;
                }
            }
        }

        return supported.toArray(new String[0]);
    }

    private String normalizeVoice(String voice) {
        if (voice == null || voice.trim().isEmpty()) {
            return "default";
        }
        // Locale.ROOT is required here: on a JVM whose default locale is Turkish,
        // toLowerCase() maps 'I' -> 'ı' (dotless), so a client-requested voice like
        // "JENNY_DIOCO" would silently fail to match the literal below or any key
        // in the voice model map, falling back to the default voice instead.
        String normalized = voice.trim().toLowerCase(java.util.Locale.ROOT);
        if ("jenny_dioco".equals(normalized)) {
            return "jenny";
        }
        return normalized;
    }

    private String getDefaultModelName() {
        if (configuredDefaultModel == null || configuredDefaultModel.trim().isEmpty()) {
            // lessac rather than amy: this is the voice a learner hears unless they pick
            // one, so it should be the best build available, and amy has no high build.
            return MODELS_LESSAC.get(0);
        }
        return configuredDefaultModel.trim();
    }

    /** Voice name to its model builds, best quality first. */
    private Map<String, List<String>> getVoiceModelMap() {
        Map<String, List<String>> voiceModels = new LinkedHashMap<>();
        voiceModels.put("default", List.of(getDefaultModelName()));
        voiceModels.put("amy", MODELS_AMY);
        voiceModels.put("alan", MODELS_ALAN);
        voiceModels.put("lessac", MODELS_LESSAC);
        voiceModels.put("ryan", MODELS_RYAN);
        voiceModels.put("jenny", MODELS_JENNY);
        voiceModels.put("cori", MODELS_CORI);
        return voiceModels;
    }

    private String resolveFirstAvailableModelPath() {
        Set<String> modelNames = new LinkedHashSet<>();
        getVoiceModelMap().values().forEach(modelNames::addAll);
        for (String modelName : modelNames) {
            String modelPath = getModelBaseDir() + File.separator + modelName;
            if (pathExists(modelPath)) {
                return modelPath;
            }
        }
        return null;
    }

    /**
     * Start the process. Protected to allow mocking in tests.
     */
    protected Process startProcess(List<String> command, File workingDir) throws IOException {
        ProcessBuilder processBuilder = new ProcessBuilder(command);
        if (workingDir != null && workingDir.exists()) {
            processBuilder.directory(workingDir);
        }
        processBuilder.redirectErrorStream(true);
        return processBuilder.start();
    }

    protected Process startAvailabilityProcess(String piperPath) throws IOException {
        ProcessBuilder processBuilder = new ProcessBuilder(piperPath, "--version");
        processBuilder.redirectErrorStream(true);
        return processBuilder.start();
    }

    protected boolean pathExists(String path) {
        return new File(path).exists();
    }

    protected boolean pathCanExecute(String path) {
        return new File(path).canExecute();
    }

    protected String absolutePath(String path) {
        return new File(path).getAbsolutePath();
    }

    protected Path createTempOutputPath() {
        String tempDir = System.getProperty("java.io.tmpdir");
        return Paths.get(tempDir, UUID.randomUUID() + ".wav");
    }

    protected byte[] readAllBytes(Path path) throws IOException {
        return Files.readAllBytes(path);
    }

    protected void deleteIfExists(Path path) throws IOException {
        Files.deleteIfExists(path);
    }

    protected String getModelBaseDir() {
        return MODEL_BASE_DIR;
    }

    protected boolean isWindows() {
        return System.getProperty("os.name").toLowerCase().contains("windows");
    }
}
