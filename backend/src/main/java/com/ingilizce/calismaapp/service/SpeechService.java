package com.ingilizce.calismaapp.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

/**
 * Whichever engine can speak: Kokoro if it is configured and answers, Piper if it is not.
 *
 * <p>The controllers used to hold PiperTtsService directly. They hold this instead, so the
 * engine is one decision in one place -- and so a Kokoro that is down for a minute costs a
 * slightly worse voice rather than a silent tutor, which is the failure a learner actually
 * feels mid-conversation.
 */
@Service
public class SpeechService {

    private static final Logger log = LoggerFactory.getLogger(SpeechService.class);

    private final KokoroTtsService kokoro;
    private final PiperTtsService piper;

    public SpeechService(KokoroTtsService kokoro, PiperTtsService piper) {
        this.kokoro = kokoro;
        this.piper = piper;
    }

    /** Whether anything can speak at all. Kokoro configured counts; so does Piper installed. */
    public boolean isAvailable() {
        return kokoro.isEnabled() || piper.isAvailable();
    }

    /**
     * The voice ids that can be asked for. With Kokoro these are the app's own ids, since
     * that is what it maps; with Piper they are whichever models are installed.
     */
    public String[] supportedVoices() {
        if (kokoro.isEnabled()) {
            return new String[] { "default", "amy", "ryan", "lessac", "cori", "jenny", "alan" };
        }
        return piper.getSupportedVoices();
    }

    /**
     * The text as Base64 WAV, or null if no engine could produce it.
     *
     * <p>Never throws: the callers treat "no audio" as "the app asks again later, or reads it
     * with the device voice", and a reply without audio is far better than a failed reply.
     */
    public String synthesizeSpeech(String text, String voice) {
        if (kokoro.isEnabled()) {
            String audio = kokoro.synthesize(text, voice);
            if (audio != null) {
                return audio;
            }
            log.warn("Kokoro could not speak; trying Piper for voice {}", voice);
        }
        try {
            return piper.isAvailable() ? piper.synthesizeSpeech(text, voice) : null;
        } catch (Exception e) {
            log.warn("Piper could not speak either: {}", e.toString());
            return null;
        }
    }
}
