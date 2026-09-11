package com.ingilizce.calismaapp.service;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.test.util.ReflectionTestUtils;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.io.PipedInputStream;
import java.io.PipedOutputStream;
import java.io.Writer;
import java.util.ArrayList;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.Executor;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.File;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Base64;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class PiperTtsServiceTest {

    private StubPiperTtsService service;
    private Process synthProcess;
    private Process availabilityProcess;
    private ByteArrayOutputStream stdin;

    @BeforeEach
    void setUp() throws Exception {
        service = new StubPiperTtsService();
        ReflectionTestUtils.setField(service, "configuredPiperPath", "/mock/piper");

        synthProcess = mock(Process.class);
        availabilityProcess = mock(Process.class);

        stdin = new ByteArrayOutputStream();
        when(synthProcess.getOutputStream()).thenReturn(stdin);
        when(synthProcess.getInputStream())
                .thenReturn(new ByteArrayInputStream("Piper output".getBytes(StandardCharsets.UTF_8)));
        when(synthProcess.waitFor(anyLong(), any(TimeUnit.class))).thenReturn(true);
        when(synthProcess.exitValue()).thenReturn(0);

        when(availabilityProcess.isAlive()).thenReturn(false);
        when(availabilityProcess.exitValue()).thenReturn(0);

        service.synthProcess = synthProcess;
        service.availabilityProcess = availabilityProcess;
        service.modelContent = new byte[] { 1, 2, 3, 4 };
        service.existingPaths.put("/mock/piper", true);
        service.executablePaths.put("/mock/piper", true);
        service.existingPaths.put("C:\\models\\en_US-amy-medium.onnx", true);
        service.existingPaths.put("C:\\models\\en_US-lessac-medium.onnx", true);
        service.existingPaths.put("C:\\models\\en_GB-alan-medium.onnx", true);
        service.existingPaths.put("C:\\models\\en_US-ryan-medium.onnx", true);
        service.existingPaths.put("C:\\models\\en_GB-jenny_dioco-medium.onnx", true);
        service.existingPaths.put("C:\\models\\en_GB-cori-medium.onnx", true);
    }

    @Test
    void synthesizeSpeech_ShouldReturnBase64Audio_WhenProcessSucceeds() {
        String audio = service.synthesizeSpeech("Hello world", "amy");

        assertEquals(Base64.getEncoder().encodeToString(new byte[] { 1, 2, 3, 4 }), audio);
        assertTrue(service.startProcessCalled);
        assertEquals("Hello world", stdin.toString(StandardCharsets.UTF_8));
        assertNotNull(service.lastCommand);
        assertTrue(service.lastCommand.contains("--model"));
        assertTrue(service.lastCommand.stream().anyMatch(s -> s.endsWith("en_US-amy-medium.onnx")));
    }

    @Test
    void synthesizeSpeech_ShouldUseDefaultAmy_WhenVoiceIsNull() {
        service.synthesizeSpeech("text", null);
        assertTrue(service.lastCommand.stream().anyMatch(s -> s.endsWith("en_US-amy-medium.onnx")));
    }

    @Test
    void synthesizeSpeech_ShouldFallbackToDefaultModel_WhenRequestedVoiceMissing() {
        // "ryan" speaks through alan now -- RyanSpeech is CC BY-NC-SA 4.0 and this app is
        // sold, see VoiceLicenceTest -- so alan's file is the one whose absence falls back.
        service.existingPaths.put("C:\\models\\en_GB-alan-medium.onnx", false);

        service.synthesizeSpeech("text", "ryan");

        assertTrue(service.lastCommand.stream().anyMatch(s -> s.endsWith("en_US-amy-medium.onnx")));
    }

    @Test
    void synthesizeSpeech_ShouldFallbackToAmy_WhenVoiceUnknown() {
        service.synthesizeSpeech("text", "unknown");
        assertTrue(service.lastCommand.stream().anyMatch(s -> s.endsWith("en_US-amy-medium.onnx")));
    }

    @Test
    void synthesizeSpeech_ShouldUseJennyModel_WhenVoiceIsJennyAlias() {
        service.synthesizeSpeech("text", "jenny");
        assertTrue(service.lastCommand.stream().anyMatch(s -> s.endsWith("en_GB-jenny_dioco-medium.onnx")));
    }

    @Test
    void synthesizeSpeech_ShouldUseCoriModel_WhenVoiceIsCori() {
        service.synthesizeSpeech("text", "cori");
        assertTrue(service.lastCommand.stream().anyMatch(s -> s.endsWith("en_GB-cori-medium.onnx")));
    }

    @Test
    void synthesizeSpeech_ShouldUseAlanModel_WhenVoiceIsAlan() {
        service.synthesizeSpeech("text", "alan");
        assertTrue(service.lastCommand.stream().anyMatch(s -> s.endsWith("en_GB-alan-medium.onnx")));
    }

    @Test
    void theLessacIdSpeaksThroughCori_BecauseLessacMayNotBeSold() {
        // The ids stay -- the app, the scene catalog and every saved conversation name them --
        // and what they name is a voice that is free to use: cori is public domain, alan is
        // CC BY-SA, and each keeps the character's gender. See VoiceLicenceTest.
        service.synthesizeSpeech("text", "lessac");
        assertTrue(service.lastCommand.stream().anyMatch(s -> s.endsWith("en_GB-cori-medium.onnx")));
    }

    @Test
    void theRyanIdSpeaksThroughAlan_BecauseRyanSpeechMayNotBeSold() {
        service.synthesizeSpeech("text", "ryan");
        assertTrue(service.lastCommand.stream().anyMatch(s -> s.endsWith("en_GB-alan-medium.onnx")));
    }

    @Test
    void synthesizeSpeech_ShouldFallbackToAmy_WhenMaleVoicesMissing() {
        service.existingPaths.put("C:\\models\\en_US-ryan-medium.onnx", false);
        service.existingPaths.put("C:\\models\\en_GB-alan-medium.onnx", false);

        service.synthesizeSpeech("text", "ryan");

        assertTrue(service.lastCommand.stream().anyMatch(s -> s.endsWith("en_US-amy-medium.onnx")));
    }

    @Test
    void synthesizeSpeech_ShouldThrow_WhenModelDoesNotExist() {
        service.existingPaths.put("C:\\models\\en_US-amy-medium.onnx", false);
        service.existingPaths.put("C:\\models\\en_US-lessac-medium.onnx", false);
        service.existingPaths.put("C:\\models\\en_GB-alan-medium.onnx", false);
        service.existingPaths.put("C:\\models\\en_US-ryan-medium.onnx", false);
        service.existingPaths.put("C:\\models\\en_GB-jenny_dioco-medium.onnx", false);
        service.existingPaths.put("C:\\models\\en_GB-cori-medium.onnx", false);

        RuntimeException ex = assertThrows(RuntimeException.class, () -> service.synthesizeSpeech("text", "amy"));
        assertTrue(ex.getMessage().contains("Model file not found"));
    }

    @Test
    void synthesizeSpeech_ShouldThrow_WhenProcessTimesOut() throws Exception {
        when(synthProcess.waitFor(anyLong(), any(TimeUnit.class))).thenReturn(false);

        RuntimeException ex = assertThrows(RuntimeException.class, () -> service.synthesizeSpeech("text", "amy"));
        assertTrue(ex.getMessage().contains("timed out"));
    }

    @Test
    void synthesizeSpeech_ShouldThrow_WhenProcessExitCodeNonZero() throws Exception {
        when(synthProcess.exitValue()).thenReturn(1);

        RuntimeException ex = assertThrows(RuntimeException.class, () -> service.synthesizeSpeech("text", "amy"));
        assertTrue(ex.getMessage().contains("Piper TTS failed"));
    }

    @Test
    void synthesizeSpeech_ShouldIncludeUnknownError_WhenProcessExitCodeNonZeroAndNoOutput() throws Exception {
        when(synthProcess.getInputStream()).thenReturn(new ByteArrayInputStream(new byte[0]));
        when(synthProcess.exitValue()).thenReturn(2);

        RuntimeException ex = assertThrows(RuntimeException.class, () -> service.synthesizeSpeech("text", "amy"));
        assertTrue(ex.getMessage().contains("Unknown error (exit code: 2)"));
    }

    @Test
    void synthesizeSpeech_ShouldWrapReadError() {
        service.throwOnRead = true;
        RuntimeException ex = assertThrows(RuntimeException.class, () -> service.synthesizeSpeech("text", "amy"));
        assertTrue(ex.getMessage().contains("Failed to synthesize speech"));
    }

    @Test
    void synthesizeSpeech_ShouldHandleStdinCloseIOException() throws Exception {
        Process closeFailingProcess = mock(Process.class);
        OutputStream closeFailingOutput = new ByteArrayOutputStream() {
            @Override
            public void close() throws IOException {
                throw new IOException("close-failed");
            }
        };

        when(closeFailingProcess.getOutputStream()).thenReturn(closeFailingOutput);
        when(closeFailingProcess.getInputStream())
                .thenReturn(new ByteArrayInputStream("ok".getBytes(StandardCharsets.UTF_8)));
        when(closeFailingProcess.waitFor(anyLong(), any(TimeUnit.class))).thenReturn(true);
        when(closeFailingProcess.exitValue()).thenReturn(0);

        service.synthProcess = closeFailingProcess;

        RuntimeException ex = assertThrows(RuntimeException.class, () -> service.synthesizeSpeech("text", "amy"));
        assertTrue(ex.getMessage().contains("close-failed"));
    }

    @Test
    void synthesizeSpeech_ShouldHandleOutputReaderIOExceptionInThread() throws Exception {
        Process readFailingProcess = mock(Process.class);
        when(readFailingProcess.getOutputStream()).thenReturn(new ByteArrayOutputStream());
        when(readFailingProcess.getInputStream()).thenReturn(new java.io.InputStream() {
            @Override
            public int read() throws IOException {
                throw new IOException("read-io");
            }
        });
        when(readFailingProcess.waitFor(anyLong(), any(TimeUnit.class))).thenReturn(true);
        when(readFailingProcess.exitValue()).thenReturn(0);

        service.synthProcess = readFailingProcess;

        String audio = service.synthesizeSpeech("text", "amy");
        assertEquals(Base64.getEncoder().encodeToString(new byte[] { 1, 2, 3, 4 }), audio);
    }

    @Test
    void isAvailable_ShouldReturnTrue_WhenPiperAndModelAvailable() {
        boolean available = service.isAvailable();
        assertTrue(available);
    }

    @Test
    void isAvailable_ShouldNotStartAProcessOnEveryRequest_WhenRecentlyConfirmed() {
        // The TTS endpoint asks before every synthesis, and every ask started `piper
        // --version` and slept at least 100 ms waiting on it -- on the path of every reply
        // the tutor speaks.
        ReflectionTestUtils.setField(service, "availabilityCacheMs", 60_000L);

        assertTrue(service.isAvailable());
        assertTrue(service.isAvailable());
        assertTrue(service.isAvailable());

        verify(availabilityProcess, times(1)).exitValue();
    }

    @Test
    void isAvailable_ShouldAskAgain_WhenTheLastAnswerWasNo() {
        // Only a yes is remembered, so a Piper that was down is back the moment it is.
        ReflectionTestUtils.setField(service, "availabilityCacheMs", 60_000L);
        when(availabilityProcess.exitValue()).thenReturn(2);
        assertFalse(service.isAvailable());

        when(availabilityProcess.exitValue()).thenReturn(0);
        assertTrue(service.isAvailable());
    }

    @Test
    void isAvailable_ShouldReturnFalse_WhenExitCodeNonZero() throws Exception {
        when(availabilityProcess.exitValue()).thenReturn(2);
        assertFalse(service.isAvailable());
    }

    @Test
    void isAvailable_ShouldReturnFalse_WhenModelMissing() {
        service.existingPaths.put("C:\\models\\en_US-amy-medium.onnx", false);
        service.existingPaths.put("C:\\models\\en_US-lessac-medium.onnx", false);
        service.existingPaths.put("C:\\models\\en_GB-alan-medium.onnx", false);
        service.existingPaths.put("C:\\models\\en_US-ryan-medium.onnx", false);
        service.existingPaths.put("C:\\models\\en_GB-jenny_dioco-medium.onnx", false);
        service.existingPaths.put("C:\\models\\en_GB-cori-medium.onnx", false);
        assertFalse(service.isAvailable());
    }

    @Test
    void isAvailable_ShouldReturnTrue_WhenConfiguredDefaultModelExists() {
        ReflectionTestUtils.setField(service, "configuredDefaultModel", "en_US-ryan-medium.onnx");
        service.existingPaths.put("C:\\models\\en_US-amy-medium.onnx", false);

        assertTrue(service.isAvailable());
    }

    @Test
    void getSupportedVoices_ShouldReflectExistingModels() {
        // Only cori's file is here. "lessac" is offered too, because that id is what cori
        // answers to now; "ryan" is not, because alan's file -- the one it answers to -- is
        // missing.
        ReflectionTestUtils.setField(service, "configuredDefaultModel", "en_GB-cori-medium.onnx");
        service.existingPaths.put("C:\\models\\en_US-amy-medium.onnx", false);
        service.existingPaths.put("C:\\models\\en_GB-alan-medium.onnx", false);
        service.existingPaths.put("C:\\models\\en_GB-jenny_dioco-medium.onnx", false);

        String[] supported = service.getSupportedVoices();

        assertArrayEquals(new String[] { "default", "lessac", "cori" }, supported);
    }

    @Test
    void isAvailable_ShouldReturnFalse_WhenStartFails() {
        service.throwOnAvailabilityStart = true;
        assertFalse(service.isAvailable());
    }

    @Test
    void isAvailable_ShouldReturnFalse_WhenProcessNeverExitsWithinTimeout() {
        when(availabilityProcess.isAlive()).thenReturn(true);

        assertFalse(service.isAvailable());
        verify(availabilityProcess).destroy();
    }

    @Test
    void findPiperPath_ShouldUseConfiguredPath_WhenExists() {
        assertEquals("/mock/piper", service.findPiperPath());
    }

    @Test
    void findPiperPath_ShouldReturnCommandFallback_WhenNoConfiguredPath() {
        ReflectionTestUtils.setField(service, "configuredPiperPath", "");
        assertEquals("piper", service.findPiperPath());
    }

    @Test
    void findPiperPath_ShouldUseWindowsExecutable_WhenConfiguredPathMissing() {
        WindowsStubPiperTtsService windowsService = new WindowsStubPiperTtsService();
        ReflectionTestUtils.setField(windowsService, "configuredPiperPath", "");
        windowsService.existingPaths.put("C:\\piper\\piper.exe", true);
        windowsService.executablePaths.put("C:\\piper\\piper.exe", true);

        assertEquals("C:\\piper\\piper.exe", windowsService.findPiperPath());
    }

    @Test
    void findPiperPath_ShouldReturnWindowsCommandFallback_WhenExecutableNotFound() {
        WindowsStubPiperTtsService windowsService = new WindowsStubPiperTtsService();
        ReflectionTestUtils.setField(windowsService, "configuredPiperPath", "");

        assertEquals("piper.exe", windowsService.findPiperPath());
    }

    @Test
    void helperMethods_ShouldWork_OnConcreteService() throws Exception {
        ConcretePiperTtsService concrete = new ConcretePiperTtsService();

        Path tempText = Files.createTempFile("piper-helper", ".txt");
        Files.writeString(tempText, "abc", StandardCharsets.UTF_8);

        assertTrue(concrete.pathExistsPublic(tempText.toString()));
        assertArrayEquals("abc".getBytes(StandardCharsets.UTF_8), concrete.readAllBytesPublic(tempText));
        assertTrue(concrete.absolutePathPublic(".").length() > 0);
        assertNotNull(concrete.getModelBaseDirPublic());

        String javaExec = Path.of(
                System.getProperty("java.home"),
                "bin",
                concrete.isWindowsPublic() ? "java.exe" : "java").toString();

        assertTrue(concrete.pathExistsPublic(javaExec));
        assertTrue(concrete.pathCanExecutePublic(javaExec));

        Process process = concrete.startProcessPublic(
                List.of(javaExec, "-version"),
                new File(System.getProperty("java.io.tmpdir")));
        assertTrue(process.waitFor(10, TimeUnit.SECONDS));
        assertEquals(0, process.exitValue());

        Process availability = concrete.startAvailabilityProcessPublic(javaExec);
        assertTrue(availability.waitFor(10, TimeUnit.SECONDS));
        assertEquals(0, availability.exitValue());

        Path wavPath = concrete.createTempOutputPathPublic();
        assertTrue(wavPath.toString().endsWith(".wav"));

        concrete.deleteIfExistsPublic(tempText);
        assertFalse(Files.exists(tempText));
    }

    @Test
    void synthesizeSpeech_ShouldNotUseCache_WhenCacheDisabledByDefault(@TempDir Path tempDir) {
        ReflectionTestUtils.setField(service, "configuredCacheDir", tempDir.toString());

        service.synthesizeSpeech("Hello cache", "amy");

        assertTrue(service.startProcessCalled);
        assertEquals(0, tempDir.toFile().listFiles().length,
                "plain-constructed service must not write cache files");
    }

    @Test
    void synthesizeSpeech_ShouldServeSecondCallFromCache_WhenCacheEnabled(@TempDir Path tempDir) {
        ReflectionTestUtils.setField(service, "cacheEnabled", true);
        ReflectionTestUtils.setField(service, "configuredCacheDir", tempDir.toString());

        String first = service.synthesizeSpeech("Hello cache", "amy");
        assertTrue(service.startProcessCalled, "first call must run the real synthesis");
        assertEquals(1, tempDir.toFile().listFiles().length, "first call must write one cache file");

        service.startProcessCalled = false;
        String second = service.synthesizeSpeech("Hello cache", "amy");

        assertEquals(first, second);
        assertFalse(service.startProcessCalled, "second call must be served from cache");
    }

    @Test
    void synthesizeSpeech_ShouldEvictOldestCacheEntry_WhenOverMaxEntries(@TempDir Path tempDir) throws Exception {
        ReflectionTestUtils.setField(service, "cacheEnabled", true);
        ReflectionTestUtils.setField(service, "configuredCacheDir", tempDir.toString());
        ReflectionTestUtils.setField(service, "cacheMaxEntries", 1);

        service.synthesizeSpeech("first text", "amy");
        File[] afterFirst = tempDir.toFile().listFiles();
        assertEquals(1, afterFirst.length);
        // Make the first entry clearly older so eviction ordering is deterministic.
        assertTrue(afterFirst[0].setLastModified(System.currentTimeMillis() - 60_000));

        service.synthesizeSpeech("second text", "amy");

        assertEquals(1, tempDir.toFile().listFiles().length,
                "cache must keep at most cacheMaxEntries files");
    }

    // -------------------------------------------------------------------------
    // One Piper per voice, kept running
    // -------------------------------------------------------------------------

    private ResidentStub residentStub() {
        ResidentStub stub = new ResidentStub();
        ReflectionTestUtils.setField(stub, "configuredPiperPath", "/mock/piper");
        ReflectionTestUtils.setField(stub, "residentEnabled", true);
        ReflectionTestUtils.setField(stub, "residentTimeoutMs", 2_000L);
        stub.synthProcess = synthProcess;
        stub.availabilityProcess = availabilityProcess;
        stub.modelContent = new byte[] { 1, 2, 3, 4 };
        stub.existingPaths.putAll(service.existingPaths);
        stub.executablePaths.putAll(service.executablePaths);
        return stub;
    }

    @Test
    void synthesizeSpeech_ShouldKeepOnePiperRunning_AndReuseItForEveryReply() {
        // Measured on the server: 0.24-0.43 s of every reply's synthesis was Piper loading the
        // voice, paid again each time because every reply started a new process.
        ResidentStub stub = residentStub();

        String first = stub.synthesizeSpeech("Oh cool! I love hearing about it.", "amy");
        String second = stub.synthesizeSpeech("Do you think \"crit\" matters?\nOr lifesteal?", "amy");

        assertEquals(Base64.getEncoder().encodeToString(new byte[] { 1, 2, 3, 4 }), first);
        assertEquals(first, second);
        assertEquals(1, stub.residentsStarted.size(), "one process for the voice, not one per reply");
        assertFalse(stub.startProcessCalled, "no reply may have fallen back to a one-off process");
        EchoPiperProcess piper = stub.residentsStarted.get(0);
        assertEquals(3, piper.lines.size(), "a warm-up line, then one line per reply");
        assertTrue(piper.lines.get(2).contains("\\\"crit\\\""),
                "a quotation mark travels escaped, and the newline did not split the line");
        assertTrue(stub.lastResidentCommand.contains("--json-input"));
        assertFalse(stub.lastResidentCommand.contains("--output_file"),
                "with --output_file Piper waits for the end of its input and never answers");
    }

    @Test
    void synthesizeSpeech_ShouldAnswerFromAOneOffPiper_WhileTheResidentIsStillStarting() {
        // Loading and warming the voice must never be what a reply waits on.
        ResidentStub stub = residentStub();
        stub.startResidentsNow = false;

        String audio = stub.synthesizeSpeech("Hello there", "amy");

        assertEquals(Base64.getEncoder().encodeToString(new byte[] { 1, 2, 3, 4 }), audio);
        assertTrue(stub.startProcessCalled);
        assertTrue(stub.residentsStarted.isEmpty());
        assertEquals(1, stub.deferred.size(), "the resident is being started for the next reply");
    }

    @Test
    void synthesizeSpeech_ShouldFallBackAndReplaceTheResident_WhenItStopsAnswering() {
        ResidentStub stub = residentStub();
        ReflectionTestUtils.setField(stub, "residentTimeoutMs", 200L);
        stub.answerFirst = 1; // answers its warm-up line, then nothing

        String audio = stub.synthesizeSpeech("Hello there", "amy");

        assertEquals(Base64.getEncoder().encodeToString(new byte[] { 1, 2, 3, 4 }), audio);
        assertTrue(stub.startProcessCalled, "the one-off path answers instead");
        assertFalse(stub.residentsStarted.get(0).isAlive(), "a Piper that stopped answering is stopped");

        stub.answerFirst = Integer.MAX_VALUE;
        stub.startProcessCalled = false;
        stub.synthesizeSpeech("Hello again", "amy");

        assertEquals(2, stub.residentsStarted.size(), "and replaced by a new one");
        assertFalse(stub.startProcessCalled);
    }

    /** Stands in for `piper --json-input`: answers each JSON line with its output_file. */
    static class EchoPiperProcess extends Process {
        final List<String> lines = new CopyOnWriteArrayList<>();
        private final PipedOutputStream toPiper = new PipedOutputStream();
        private final PipedInputStream fromPiper = new PipedInputStream();
        private volatile boolean alive = true;

        EchoPiperProcess(int answerFirst) throws IOException {
            PipedInputStream piperStdin = new PipedInputStream(toPiper);
            PipedOutputStream piperStdout = new PipedOutputStream(fromPiper);
            Thread piper = new Thread(() -> {
                ObjectMapper json = new ObjectMapper();
                try (BufferedReader in = new BufferedReader(
                        new InputStreamReader(piperStdin, StandardCharsets.UTF_8));
                        Writer out = new OutputStreamWriter(piperStdout, StandardCharsets.UTF_8)) {
                    String line;
                    while ((line = in.readLine()) != null) {
                        lines.add(line);
                        if (lines.size() <= answerFirst) {
                            out.write(json.readTree(line).get("output_file").asText() + "\n");
                            out.flush();
                        }
                    }
                } catch (IOException ignored) {
                    // The test is over, or the service closed the pipe.
                }
            });
            piper.setDaemon(true);
            piper.start();
        }

        @Override
        public OutputStream getOutputStream() {
            return toPiper;
        }

        @Override
        public InputStream getInputStream() {
            return fromPiper;
        }

        @Override
        public InputStream getErrorStream() {
            return new ByteArrayInputStream(new byte[0]);
        }

        @Override
        public int waitFor() {
            return 0;
        }

        @Override
        public int exitValue() {
            if (alive) {
                throw new IllegalThreadStateException("still running");
            }
            return 0;
        }

        @Override
        public void destroy() {
            alive = false;
        }

        @Override
        public boolean isAlive() {
            return alive;
        }
    }

    static class ResidentStub extends StubPiperTtsService {
        final List<EchoPiperProcess> residentsStarted = new CopyOnWriteArrayList<>();
        final List<Runnable> deferred = new ArrayList<>();
        volatile int answerFirst = Integer.MAX_VALUE;
        boolean startResidentsNow = true;
        List<String> lastResidentCommand;

        @Override
        protected Process startResidentProcess(List<String> command, File workingDir) throws IOException {
            lastResidentCommand = command;
            EchoPiperProcess process = new EchoPiperProcess(answerFirst);
            residentsStarted.add(process);
            return process;
        }

        @Override
        protected Executor residentStarter() {
            return task -> {
                if (startResidentsNow) {
                    task.run();
                } else {
                    deferred.add(task);
                }
            };
        }
    }

    static class StubPiperTtsService extends PiperTtsService {
        Process synthProcess;
        Process availabilityProcess;
        boolean startProcessCalled;
        boolean throwOnRead;
        boolean throwOnAvailabilityStart;
        List<String> lastCommand;
        byte[] modelContent = new byte[0];
        final Map<String, Boolean> existingPaths = new HashMap<>();
        final Map<String, Boolean> executablePaths = new HashMap<>();

        @Override
        protected String getModelBaseDir() {
            return "C:\\models";
        }

        @Override
        protected Path createTempOutputPath() {
            return Path.of("/tmp/mock.wav");
        }

        @Override
        protected byte[] readAllBytes(Path path) throws IOException {
            if (throwOnRead) {
                throw new IOException("read-failed");
            }
            return modelContent;
        }

        @Override
        protected void deleteIfExists(Path path) {
            // no-op for tests
        }

        @Override
        protected boolean pathExists(String path) {
            String normalized = normalizeTestPath(path);
            return existingPaths.entrySet().stream()
                    .filter(e -> normalizeTestPath(e.getKey()).equals(normalized))
                    .map(Map.Entry::getValue)
                    .findFirst()
                    .orElse(false);
        }

        @Override
        protected boolean pathCanExecute(String path) {
            String normalized = normalizeTestPath(path);
            return executablePaths.entrySet().stream()
                    .filter(e -> normalizeTestPath(e.getKey()).equals(normalized))
                    .map(Map.Entry::getValue)
                    .findFirst()
                    .orElse(false);
        }

        @Override
        protected String absolutePath(String path) {
            return path;
        }

        @Override
        protected boolean isWindows() {
            return false;
        }

        private String normalizeTestPath(String path) {
            return path.replace('\\', '/');
        }

        @Override
        protected Process startProcess(List<String> command, File workingDir) {
            startProcessCalled = true;
            lastCommand = command;
            return synthProcess;
        }

        @Override
        protected Process startAvailabilityProcess(String piperPath) throws IOException {
            if (throwOnAvailabilityStart) {
                throw new IOException("cannot start");
            }
            return availabilityProcess;
        }
    }

    static class WindowsStubPiperTtsService extends StubPiperTtsService {
        @Override
        protected boolean isWindows() {
            return true;
        }
    }

    static class ConcretePiperTtsService extends PiperTtsService {
        Process startProcessPublic(List<String> command, File workingDir) throws IOException {
            return super.startProcess(command, workingDir);
        }

        Process startAvailabilityProcessPublic(String piperPath) throws IOException {
            return super.startAvailabilityProcess(piperPath);
        }

        boolean pathExistsPublic(String path) {
            return super.pathExists(path);
        }

        boolean pathCanExecutePublic(String path) {
            return super.pathCanExecute(path);
        }

        String absolutePathPublic(String path) {
            return super.absolutePath(path);
        }

        Path createTempOutputPathPublic() {
            return super.createTempOutputPath();
        }

        byte[] readAllBytesPublic(Path path) throws IOException {
            return super.readAllBytes(path);
        }

        void deleteIfExistsPublic(Path path) throws IOException {
            super.deleteIfExists(path);
        }

        String getModelBaseDirPublic() {
            return super.getModelBaseDir();
        }

        boolean isWindowsPublic() {
            return super.isWindows();
        }
    }

    @Test
    void aVoicePrefersItsHighBuildAndFallsBackToItsOwnMediumOne() {
        // Every voice shipped at `-medium`, the middle of Piper's four tiers, which is a
        // large part of why the output sounded synthetic. The high builds are drop-in.
        //
        // The fallback matters as much as the preference: if the high file is not on the
        // server yet, the learner must get lessac-medium, not the default voice. Dropping a
        // tier is a quality change; dropping to a different speaker mid-session is someone
        // else reading to them. It is also what lets this ship before the files are copied.
        java.util.Set<String> present = new java.util.HashSet<>();
        PiperTtsService service = new PiperTtsService() {
            @Override
            protected boolean pathExists(String path) {
                return present.stream().anyMatch(path::endsWith);
            }
        };

        present.add("en_GB-cori-high.onnx");
        present.add("en_GB-cori-medium.onnx");
        assertTrue(service.getModelFile("cori").endsWith("en_GB-cori-high.onnx"));

        present.remove("en_GB-cori-high.onnx");
        assertTrue(service.getModelFile("cori").endsWith("en_GB-cori-medium.onnx"),
                "a missing high build must not silently change which person is speaking");
    }

    @Test
    void voicesWithoutAHighBuildStayOnMedium() {
        // amy, alan and jenny have no high build published. Listing one would point at a
        // file that will never exist and send every request down the fallback path.
        java.util.Set<String> present = new java.util.HashSet<>(java.util.List.of(
                "en_US-amy-medium.onnx", "en_GB-alan-medium.onnx"));
        PiperTtsService service = new PiperTtsService() {
            @Override
            protected boolean pathExists(String path) {
                return present.stream().anyMatch(path::endsWith);
            }
        };

        assertTrue(service.getModelFile("amy").endsWith("en_US-amy-medium.onnx"));
        assertTrue(service.getModelFile("alan").endsWith("en_GB-alan-medium.onnx"));
    }
}
