package com.ingilizce.calismaapp.service;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.test.util.ReflectionTestUtils;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
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
        service.existingPaths.put("C:\\models\\en_US-ryan-medium.onnx", false);

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
    void synthesizeSpeech_ShouldUseLessacModel_WhenVoiceIsLessac() {
        service.synthesizeSpeech("text", "lessac");
        assertTrue(service.lastCommand.stream().anyMatch(s -> s.endsWith("en_US-lessac-medium.onnx")));
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
        ReflectionTestUtils.setField(service, "configuredDefaultModel", "en_US-ryan-medium.onnx");
        service.existingPaths.put("C:\\models\\en_US-amy-medium.onnx", false);
        service.existingPaths.put("C:\\models\\en_US-lessac-medium.onnx", false);
        service.existingPaths.put("C:\\models\\en_GB-alan-medium.onnx", false);
        service.existingPaths.put("C:\\models\\en_GB-jenny_dioco-medium.onnx", false);
        service.existingPaths.put("C:\\models\\en_GB-cori-medium.onnx", false);

        String[] supported = service.getSupportedVoices();

        assertArrayEquals(new String[] { "default", "ryan" }, supported);
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
}
