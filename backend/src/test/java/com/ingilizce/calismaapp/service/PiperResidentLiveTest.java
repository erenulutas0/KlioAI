package com.ingilizce.calismaapp.service;

import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.io.File;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

/**
 * The resident path against a real Piper, where one is installed.
 *
 * <p>The seam tests pin what the service does with an answer; only a real Piper can say
 * whether it answers at all -- whether `--json-input` keeps the process alive, whether the
 * path comes back only once the WAV is complete, and whether a quotation mark or a newline
 * in a reply survives the trip. Runs on a developer machine with Piper in C:\piper (the
 * layout the service itself looks for on Windows); skipped everywhere else, CI included.
 */
class PiperResidentLiveTest {

    private static final Path PIPER = Path.of("C:/piper/piper.exe");
    private static final Path AMY = Path.of("C:/piper/en_US-amy-medium.onnx");

    @Test
    void aRealPiperStaysRunningAndAnswersLineAfterLine() throws Exception {
        assumeTrue(Files.exists(PIPER) && Files.exists(AMY), "no local Piper installed");

        AtomicInteger oneOffProcesses = new AtomicInteger();
        PiperTtsService service = new PiperTtsService() {
            @Override
            protected Process startProcess(List<String> command, File workingDir) throws IOException {
                oneOffProcesses.incrementAndGet();
                return super.startProcess(command, workingDir);
            }
        };
        ReflectionTestUtils.setField(service, "configuredPiperPath", PIPER.toString());
        ReflectionTestUtils.setField(service, "residentEnabled", true);
        ReflectionTestUtils.setField(service, "residentTimeoutMs", 30_000L);

        try {
            // The first reply for a voice is answered the old way while the resident starts.
            assertComplete(service.synthesizeSpeech("Hello there, this one starts it.", "amy"));
            assertEquals(1, oneOffProcesses.get());

            Map<?, ?> residents = (Map<?, ?>) ReflectionTestUtils.getField(service, "residents");
            long deadline = System.currentTimeMillis() + 60_000;
            while (residents.isEmpty() && System.currentTimeMillis() < deadline) {
                Thread.sleep(100);
            }
            assertFalse(residents.isEmpty(), "the resident Piper never became ready");

            for (String reply : List.of(
                    "Do you think \"crit\" matters?\nOr is it the lifesteal?",
                    "Oh cool! I love hearing about powerful champs like Ringo.")) {
                long startedNs = System.nanoTime();
                byte[] wav = assertComplete(service.synthesizeSpeech(reply, "amy"));
                System.out.printf("resident synthesis: %d ms, %d bytes%n",
                        (System.nanoTime() - startedNs) / 1_000_000L, wav.length);
            }
            assertEquals(1, oneOffProcesses.get(), "every later reply came from the running Piper");
        } finally {
            service.stopResidents();
        }
    }

    private static byte[] assertComplete(String base64) {
        byte[] wav = Base64.getDecoder().decode(base64);
        assertTrue(wav.length > 44, "no audio");
        assertEquals("RIFF", new String(wav, 0, 4, StandardCharsets.US_ASCII));
        int riffSize = ByteBuffer.wrap(wav, 4, 4).order(ByteOrder.LITTLE_ENDIAN).getInt();
        assertEquals(wav.length, riffSize + 8, "the WAV was read before Piper finished it");
        return wav;
    }
}
