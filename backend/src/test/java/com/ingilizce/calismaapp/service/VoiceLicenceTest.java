package com.ingilizce.calismaapp.service;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * The voices this app is allowed to sell.
 *
 * <p>Two Piper voices shipped in production for months and neither may be sold. The Blizzard
 * 2013 Lessac agreement excludes "any commercial purpose, including the development,
 * marketing, commercialisation, sale or licencing of voice synthesis or speech recognition
 * products or services"; RyanSpeech, the tutor's male voice and seven scene characters, is
 * CC BY-NC-SA 4.0. This app has a subscription.
 *
 * <p>A comment saying so is a comment. This fails the build if either model file is named
 * again, wherever someone puts it back.
 */
class VoiceLicenceTest {

    private static final Path SOURCE =
            Path.of("src/main/java/com/ingilizce/calismaapp/service/PiperTtsService.java");

    @Test
    @DisplayName("no Piper model we ship is one we may not sell")
    void noNonCommercialModelIsReferenced() throws Exception {
        String source = Files.readString(SOURCE);
        // The licence comment names them; the code must not.
        String code = source.replaceAll("(?s)/\\*.*?\\*/", "").replaceAll("//[^\n]*", "");

        assertFalse(code.contains("en_US-lessac"), "lessac is licensed for research only");
        assertFalse(code.contains("en_US-ryan"), "RyanSpeech is CC BY-NC-SA 4.0: no commercial use");
        assertTrue(code.contains("en_GB-cori"), "cori is public domain and is what replaced them");
    }

    @Test
    @DisplayName("and the properties do not name one either")
    void noNonCommercialModelIsConfigured() throws Exception {
        for (String file : new String[] { "src/main/resources/application.properties",
                "src/main/resources/application-docker.properties",
                "src/main/resources/application-prod.properties" }) {
            Path path = Path.of(file);
            if (!Files.exists(path)) {
                continue;
            }
            String text = Files.readString(path);
            assertFalse(text.contains("en_US-lessac"), file + " names lessac");
            assertFalse(text.contains("en_US-ryan"), file + " names ryan");
        }
    }
}
