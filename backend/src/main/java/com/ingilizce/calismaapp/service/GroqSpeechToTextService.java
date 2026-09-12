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
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.regex.Pattern;

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
     *
     * <p>lowConfidence / avgLogprob: whether this transcript is worth the learner
     * double-checking, and the number that decision came from. The judgement is made here
     * rather than on the device — see {@link #LOW_CONFIDENCE_AVG_LOGPROB_THRESHOLD}. Both
     * default to "nothing to report" for the two-argument constructor, so a caller that
     * predates them keeps compiling and keeps meaning "no warning".
     *
     * <p>otherLanguage / detectedLanguage: whether a second, unpinned pass over the same
     * audio concluded it was not English, and what it called the language. The pinned
     * transcription cannot report this -- forced to English, it produces English -- and it
     * is the case the confidence number is blind to: a Turkish sentence comes back as
     * confident English nonsense. otherLanguage is already folded into lowConfidence, so a
     * client that reads only that still asks before sending; it is kept separately so a
     * later client can say why it is asking.
     */
    public record TranscriptionResult(String text,
                                      String model,
                                      Double durationSeconds,
                                      List<WordTiming> words,
                                      boolean lowConfidence,
                                      Double avgLogprob,
                                      boolean otherLanguage,
                                      String detectedLanguage,
                                      String heardAs) {
        public TranscriptionResult(String text, String model) {
            this(text, model, null, List.of(), false, null, false, null, null);
        }

        /** A language verdict without the free transcript: what every caller before it meant. */
        public TranscriptionResult(String text,
                                   String model,
                                   Double durationSeconds,
                                   List<WordTiming> words,
                                   boolean lowConfidence,
                                   Double avgLogprob,
                                   boolean otherLanguage,
                                   String detectedLanguage) {
            this(text, model, durationSeconds, words, lowConfidence, avgLogprob, otherLanguage,
                    detectedLanguage, null);
        }

        public TranscriptionResult(String text,
                                   String model,
                                   Double durationSeconds,
                                   List<WordTiming> words) {
            this(text, model, durationSeconds, words, false, null, false, null, null);
        }

        /** Confidence without a language verdict: what every caller before detection meant. */
        public TranscriptionResult(String text,
                                   String model,
                                   Double durationSeconds,
                                   List<WordTiming> words,
                                   boolean lowConfidence,
                                   Double avgLogprob) {
            this(text, model, durationSeconds, words, lowConfidence, avgLogprob, false, null, null);
        }
    }

    /**
     * What the unpinned pass concluded about the language actually spoken.
     *
     * <p>{@code detected} is the provider's own name for it when the response carried one,
     * else a script-based guess, else null. {@code other} is the one thing the caller acts
     * on, and it is true only on positive evidence that the audio was not English. Absent
     * data is never evidence -- the rule this whole file already follows.
     */
    record SpokenLanguage(boolean other, String detected, String heardAs, Double overlap) {
        static final SpokenLanguage UNKNOWN = new SpokenLanguage(false, null);

        SpokenLanguage(boolean other, String detected) {
            this(other, detected, null, null);
        }

        /** The same verdict, with the sentence written the way the learner would write it. */
        SpokenLanguage withHeardAs(String respelled) {
            return new SpokenLanguage(other, detected, respelled, overlap);
        }

        /**
         * The share of words two transcripts of the same audio have in common, above which
         * they are the same sentence.
         *
         * <p>Two readings of one clip differ in punctuation and the odd filler, never in most
         * of their words. A pinned "Hello, can you please take a while?" against a free
         * "Merhaba, biraz su alabilir miyiz?" shares nothing at all.
         *
         * <p>This was 0.6 and that was too loose. A sentence that changes language halfway can
         * come back pinned as "I'd like the pasta, and also birasso" -- the Turkish mangled
         * into one nonsense word -- against a free pass that kept "biraz su alabilir miyiz".
         * Six shared words out of ten is exactly 0.6: counted as the same sentence, sent
         * straight on, and the card then taught "a beer" for a request for water. A
         * transcript that lost or changed a third of the words is not the same sentence,
         * and holding it back is the behaviour this threshold falls back to anyway.
         */
        static final double SAME_SENTENCE_OVERLAP = 0.85;

        static SpokenLanguage from(Map<String, Object> payload, String pinnedTranscript) {
            // The transcript about to be sent is supposed to be English. If it carries
            // letters English does not use, the pin did not hold -- on a device, a request
            // pinned to English came back "Selam nasılsın?" -- and that is evidence on its
            // own, with or without a second pass to agree.
            boolean pinnedIsForeign = hasLettersEnglishLacks(pinnedTranscript);
            if (payload == null) {
                return pinnedIsForeign ? new SpokenLanguage(true, "non-english-script") : UNKNOWN;
            }
            String free = payload.get("text") == null ? "" : payload.get("text").toString().trim();
            Object named = payload.get("language");
            if (named != null && !named.toString().isBlank()) {
                String language = named.toString().trim().toLowerCase(Locale.ROOT);
                if (pinnedIsForeign) {
                    return new SpokenLanguage(true, language, blankToNull(free), null);
                }
                if (isEnglish(language)) {
                    return new SpokenLanguage(false, language);
                }
                // The label says another language and the pinned transcript looks English.
                // Whether to believe the label is settled by what the free pass wrote, not by
                // the label alone. Measured on a device, the label was wrong twice in five
                // turns -- "dutch" on 1.7 seconds of clear English, and another on 2.5 -- and
                // both times the transcript was right. Language identification on a clip that
                // short is a guess. But a pass that got the language wrong still hears the
                // words: if it wrote the same sentence, the audio was that sentence, and it
                // is the label that is noise.
                //
                // The case this exists to catch cannot pass that test. When the pin invents
                // English from a Turkish sentence -- "No, so, so, name me." -- the two
                // transcripts share no words at all. And a learner who mixes the languages is
                // transcribed the same way by both passes, both languages intact, so what
                // reaches the tutor is what they said.
                double overlap = wordOverlap(pinnedTranscript, free);
                if (overlap >= SAME_SENTENCE_OVERLAP) {
                    return new SpokenLanguage(false, language, null, overlap);
                }
                return new SpokenLanguage(true, language, blankToNull(free), overlap);
            }
            // No language field. Groq's documentation shows none in its verbose_json
            // example, so this cannot be the only path or the feature silently does
            // nothing -- the mistake the silence check spent a release making. A free
            // transcript that carries letters English does not use, where the pinned one
            // does not, was not English: ç ğ ı ö ş ü, ä ß, é ñ, and every non-Latin script.
            // The free pass's letters count too. This used to require the pinned transcript
            // to be clean as well, which is exactly backwards: with both in Turkish it said
            // nothing at all.
            if (pinnedIsForeign || hasLettersEnglishLacks(free)) {
                return new SpokenLanguage(true, "non-english-script", blankToNull(free), null);
            }
            return UNKNOWN;
        }

        /**
         * Without the free transcript's words: that is the learner's own speech, and this line
         * is logged on every turn. Its length is enough to see whether there was one.
         */
        @Override
        public String toString() {
            return "SpokenLanguage[other=" + other + ", detected=" + detected
                    + ", overlap=" + overlap
                    + ", heardAsChars=" + (heardAs == null ? 0 : heardAs.length()) + "]";
        }

        /** Shared words over the longer transcript's length; 0 when either is empty. */
        static double wordOverlap(String pinned, String free) {
            List<String> left = words(pinned);
            List<String> right = words(free);
            if (left.isEmpty() || right.isEmpty()) {
                return 0;
            }
            Map<String, Integer> remaining = new HashMap<>();
            for (String word : right) {
                remaining.merge(word, 1, Integer::sum);
            }
            int shared = 0;
            for (String word : left) {
                Integer count = remaining.get(word);
                if (count != null && count > 0) {
                    shared++;
                    remaining.put(word, count - 1);
                }
            }
            return (double) shared / Math.max(left.size(), right.size());
        }

        /** Lowercased runs of letters, digits and apostrophes: punctuation is not a word. */
        static List<String> words(String text) {
            List<String> words = new ArrayList<>();
            if (text == null) {
                return words;
            }
            StringBuilder current = new StringBuilder();
            text.toLowerCase(Locale.ROOT).codePoints().forEach(cp -> {
                if (Character.isLetterOrDigit(cp) || cp == 39) {
                    current.appendCodePoint(cp);
                } else if (current.length() > 0) {
                    words.add(current.toString());
                    current.setLength(0);
                }
            });
            if (current.length() > 0) {
                words.add(current.toString());
            }
            return words;
        }

        private static String blankToNull(String text) {
            return text == null || text.isBlank() ? null : text;
        }

        /** "en" and "english" are both seen in the wild; nothing else is English. */
        static boolean isEnglish(String language) {
            return language.startsWith("en");
        }

        static boolean hasLettersEnglishLacks(String text) {
            return text != null
                    && text.codePoints().anyMatch(cp -> Character.isLetter(cp) && cp > 127);
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

    /**
     * Empty by default, and it must stay that way unless someone has a very specific reason.
     *
     * <p>This used to default to "English learning conversation. Transcribe the learner's
     * English speech exactly." It reads like an instruction. Whisper's {@code prompt} is not
     * an instruction — it is prepended as *prior transcript text*, context the model assumes
     * it has already produced. So when the audio contains nothing to transcribe, the model
     * does the only sensible thing with a half-finished paragraph: it continues it.
     *
     * <p>The first hallucination captured on a device began, verbatim: "English learning
     * conversation. Transcribe or the stream of language can be seen in general.
     * Transcription by CastingWords..." — the prompt's own opening words, carried on into
     * invented subtitle boilerplate. This setting was not failing to prevent the
     * hallucination. It was writing the first half of it.
     *
     * <p>It also explains the reading that made no sense: {@code no_speech_prob = 0.0} on a
     * recording of an empty room. The model was not guessing at speech it could not hear, it
     * was confidently continuing text it had been handed, and it is right to be confident
     * about that. Two attempts at this bug were built on trusting that number.
     *
     * <p>A Whisper prompt is for vocabulary and spelling hints — proper nouns, product
     * names. Prose belongs nowhere near it.
     *
     * <p>That correct use is now taken up by {@link #vocabularyHint(List)}, which builds a
     * comma-separated list of the learner's own saved words. This property stays as the
     * override: set, it replaces the generated hint entirely, so an operator can pin an
     * exact prompt (or reproduce a bug report) without a deploy. It stays empty by default
     * because the safe prompt is no prompt.
     */
    @Value("${groq.speech.prompt:}")
    private String prompt;

    /**
     * Whether every transcription is paired with an unpinned pass to check the language.
     *
     * <p>On by default under Spring; false when the service is built with {@code new},
     * which is how the older unit tests build it, so they keep seeing exactly one request.
     * Groq bills a minimum of ten seconds per request, so the second pass costs about a
     * hundredth of a cent, and because it runs in parallel it costs no latency.
     */
    @Value("${groq.speech.detect-language:true}")
    private boolean detectLanguage;

    /** How long, once the transcript is back, the detection is still worth waiting for. */
    @Value("${groq.speech.detect-language-wait-ms:1500}")
    private long detectionWaitMillis = 1500;

    /**
     * Daemon threads, so an unanswered detection can never keep the JVM from stopping;
     * cached, so an idle service holds none.
     */
    private final ExecutorService detectionExecutor = Executors.newCachedThreadPool(runnable -> {
        Thread thread = new Thread(runnable, "speech-language-detect");
        thread.setDaemon(true);
        return thread;
    });

    private final RestTemplate restTemplate;
    private final ObjectMapper objectMapper;

    public GroqSpeechToTextService() {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(30000);
        factory.setReadTimeout(60000);
        this.restTemplate = new RestTemplate(factory);
        this.objectMapper = new ObjectMapper();
    }

    /** Transcribes with no vocabulary hint — exactly the behaviour that shipped. */
    public TranscriptionResult transcribe(byte[] audioBytes,
                                          String filename,
                                          String contentType,
                                          String requestedLocale) {
        return transcribe(audioBytes, filename, contentType, requestedLocale, List.of());
    }

    /**
     * @param learnerVocabulary words this learner has actually saved, best candidates first.
     *                          Empty, null, or unusable entries simply mean no hint is sent;
     *                          this list can never be a reason a transcription fails.
     */
    public TranscriptionResult transcribe(byte[] audioBytes,
                                          String filename,
                                          String contentType,
                                          String requestedLocale,
                                          List<String> learnerVocabulary) {
        return transcribe(audioBytes, filename, contentType, requestedLocale, learnerVocabulary, null);
    }

    /**
     * @param nativeLanguage the learner's own language by name ("Turkish"), or null. Used only
     *     to write out a sentence that was spoken in it -- see {@link #respellInNativeLanguage}.
     */
    public TranscriptionResult transcribe(byte[] audioBytes,
                                          String filename,
                                          String contentType,
                                          String requestedLocale,
                                          List<String> learnerVocabulary,
                                          String nativeLanguage) {
        if (apiKey == null || apiKey.isBlank()) {
            throw new IllegalStateException("Groq API key is not configured");
        }
        if (audioBytes == null || audioBytes.length == 0) {
            throw new IllegalArgumentException("Audio file is empty");
        }

        String selectedLanguage = resolveLanguage(requestedLocale);
        String safeFilename = sanitizeFilename(filename);
        // Resolved once, outside the try, so the echo guard below can compare the transcript
        // against the exact string that was sent rather than rebuilding it.
        String resolvedPrompt = resolvePrompt(learnerVocabulary);

        // Started before the transcription and read after it, so on the path the learner
        // is waiting on it costs nothing; see detectSpokenLanguage for why it exists.
        // Only when the learner is practising English. Every rule below is "is this
        // English?", which is the wrong question for a service configured for another
        // language -- where a Turkish transcript is the expected answer, not a warning.
        CompletableFuture<Map<String, Object>> detection = detectLanguage && "en".equals(selectedLanguage)
                ? CompletableFuture.supplyAsync(
                        () -> detectSpokenLanguage(audioBytes, safeFilename, contentType),
                        detectionExecutor)
                : null;

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
            if (!resolvedPrompt.isBlank()) {
                body.add("prompt", resolvedPrompt);
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
            Double avgLogprob = worstAvgLogprob(payload.get("segments"));
            if (segmentsLookLikeSilence(payload.get("segments"))) {
                log.info("Discarding transcript: model reports no speech. text='{}'", text);
                text = "";
            } else if (isHallucinatedSilence(text)) {
                log.info("Discarding hallucinated transcript for silent audio: '{}'", text);
                text = "";
            } else if (isPromptEcho(text, resolvedPrompt)) {
                log.info("Discarding transcript: the model read the prompt back. text='{}'", text);
                text = "";
            }
            Double durationSeconds = parseDuration(payload.get("duration"));
            List<WordTiming> words = parseWordTimings(payload.get("words"));
            // An empty transcript is not "shaky", it is nothing: the client already has a
            // path for "we could not hear you", and adding a double-check warning on top of
            // it would tell the learner to re-read words that are not there. avgLogprob is
            // still reported, because a discarded transcript is exactly the case somebody
            // will be reading a log line about later.
            SpokenLanguage spoken = awaitDetection(detection, text);
            if (!text.isBlank() && spoken.other()) {
                spoken = respellInNativeLanguage(spoken, nativeLanguage, audioBytes, safeFilename, contentType);
            }
            log.info("Speech language: {}", spoken);
            // Either signal is enough to hold the transcript for a second look. The learner
            // sees the same English transcript either way; what changes is that they are
            // asked before it is sent, instead of being corrected for words they never said.
            boolean otherLanguage = !text.isBlank() && spoken.other();
            boolean lowConfidence = !text.isBlank() && (isLowConfidence(avgLogprob) || otherLanguage);
            // What the learner actually said, when it was not the language being practised --
            // so the app can show them their own sentence instead of the English the pin made
            // up from it. Asked for on a device: "it did not show the Turkish I said".
            return new TranscriptionResult(text, model, durationSeconds, words, lowConfidence, avgLogprob,
                    otherLanguage, spoken.detected(), otherLanguage ? spoken.heardAs() : null);
        } catch (RestClientResponseException e) {
            log.warn("Groq speech transcription failed: status={}, body={}", e.getStatusCode(), e.getResponseBodyAsString());
            throw new RuntimeException("Groq speech transcription failed: " + e.getStatusCode(), e);
        } catch (Exception e) {
            log.warn("Groq speech transcription failed: {}", e.getMessage());
            throw new RuntimeException("Groq speech transcription failed", e);
        }
    }

    /**
     * The same audio, transcribed with nothing forced.
     *
     * <p>The main request pins the language to English and hands Whisper the learner's own
     * English words as a prompt. Both are right for a learner speaking English, and both
     * are exactly what turns a Turkish sentence into confident English nonsense: on a
     * device, "Bugün hava çok güzel, dışarı çıkalım" came back as "No, so, so, name me."
     * with an avg_logprob above the shaky line, went to the tutor, and was corrected --
     * "name me" -> "call me" -- for something the learner never said. A pinned language
     * cannot report that the audio was not in it. Only an unpinned pass can.
     *
     * <p>No language and no prompt, deliberately: either would pull the detection toward
     * English. Returns the raw payload, or null on any failure -- a detection that failed
     * is not evidence of anything, and the transcript proceeds exactly as it did before
     * this existed.
     */
    Map<String, Object> detectSpokenLanguage(byte[] audioBytes, String safeFilename, String contentType) {
        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setBearerAuth(apiKey);
            headers.setContentType(MediaType.MULTIPART_FORM_DATA);

            MultiValueMap<String, Object> body = new LinkedMultiValueMap<>();
            body.add("model", model);
            body.add("temperature", "0");
            body.add("response_format", "verbose_json");

            HttpHeaders fileHeaders = new HttpHeaders();
            fileHeaders.setContentType(resolveMediaType(contentType, safeFilename));
            body.add("file", new HttpEntity<>(new NamedByteArrayResource(audioBytes, safeFilename), fileHeaders));

            ResponseEntity<String> response = restTemplate.postForEntity(
                    transcriptionUrl, new HttpEntity<>(body, headers), String.class);
            return objectMapper.readValue(response.getBody(), new TypeReference<Map<String, Object>>() {
            });
        } catch (Exception e) {
            log.warn("Speech language detection failed: {}", e.getMessage());
            return null;
        }
    }

    /**
     * Whisper's code for each native language the app supports. English is absent on purpose:
     * it is the language being learned, and a sentence is never respelled into it.
     */
    private static final Map<String, String> WHISPER_CODES = Map.of(
            "turkish", "tr",
            "spanish", "es",
            "portuguese", "pt",
            "indonesian", "id",
            "german", "de",
            "french", "fr",
            "italian", "it");

    /**
     * The languages Whisper has been seen to name instead of a learner's own.
     *
     * <p>Measured on a device: two of the three sentences spoken in Turkish were labelled
     * "azerbaijani", and the free pass wrote them in Azerbaijani spelling -- "Merhaba, biraz su
     * alabilir miyiz?" came back as "Məhəba, bir az su ala bilir məyiz?". The two languages
     * are close enough that the recogniser cannot keep them apart; a learner reading their own
     * sentence can, and the schwa reads as a bug. Add a pair here when it is seen, not before:
     * respelling a sentence into a language it was never spoken in would garble it.
     */
    private static final Map<String, Set<String>> MISTAKEN_FOR = Map.of(
            "turkish", Set.of("azerbaijani"));

    /**
     * The sentence written in the learner's own language, when that is what they spoke.
     *
     * <p>The free pass has to stay unpinned -- it is the only thing that can say the audio was
     * not English -- so the spelling it writes is the spelling of whatever it guessed. When the
     * guess is the learner's own language, or one it is known to mistake for it, one more pass
     * pinned to that language writes the sentence as they would. Only on this path: a turn
     * already held back for the learner to read, where a quarter of a second more is not a
     * wait anyone feels, and a request on every turn would be a cost for nothing.
     *
     * <p>Anything short of a clean answer leaves the verdict as it was.
     */
    SpokenLanguage respellInNativeLanguage(SpokenLanguage spoken, String nativeLanguage,
                                           byte[] audioBytes, String safeFilename, String contentType) {
        if (spoken.heardAs() == null || nativeLanguage == null || spoken.detected() == null) {
            return spoken;
        }
        String nativeName = nativeLanguage.trim().toLowerCase(Locale.ROOT);
        String code = WHISPER_CODES.get(nativeName);
        String detected = spoken.detected().trim().toLowerCase(Locale.ROOT);
        boolean spokenInIt = detected.equals(nativeName)
                || MISTAKEN_FOR.getOrDefault(nativeName, Set.of()).contains(detected);
        if (code == null || !spokenInIt) {
            return spoken;
        }
        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setBearerAuth(apiKey);
            headers.setContentType(MediaType.MULTIPART_FORM_DATA);

            MultiValueMap<String, Object> body = new LinkedMultiValueMap<>();
            body.add("model", model);
            body.add("language", code);
            body.add("temperature", "0");
            body.add("response_format", "json");

            HttpHeaders fileHeaders = new HttpHeaders();
            fileHeaders.setContentType(resolveMediaType(contentType, safeFilename));
            body.add("file", new HttpEntity<>(new NamedByteArrayResource(audioBytes, safeFilename), fileHeaders));

            ResponseEntity<String> response = restTemplate.postForEntity(
                    transcriptionUrl, new HttpEntity<>(body, headers), String.class);
            Map<String, Object> payload = objectMapper.readValue(response.getBody(),
                    new TypeReference<Map<String, Object>>() {
                    });
            Object text = payload.get("text");
            String respelled = text == null ? "" : text.toString().trim();
            if (respelled.isEmpty() || isHallucinatedSilence(respelled)) {
                return spoken;
            }
            return spoken.withHeardAs(respelled);
        } catch (Exception e) {
            log.warn("Speech respelling in {} failed: {}", code, e.getMessage());
            return spoken;
        }
    }

    /** What the unpinned pass said, or unknown when there was no pass or it said nothing usable. */
    private SpokenLanguage awaitDetection(CompletableFuture<Map<String, Object>> detection, String pinnedTranscript) {
        if (detection == null) {
            return SpokenLanguage.UNKNOWN;
        }
        // A pass that failed or ran late says nothing -- but the pinned transcript still
        // can, so it is judged either way.
        Map<String, Object> payload = null;
        try {
            payload = detection.get(detectionWaitMillis, TimeUnit.MILLISECONDS);
        } catch (TimeoutException e) {
            log.warn("Speech language detection did not answer within {} ms; proceeding without it", detectionWaitMillis);
            detection.cancel(true);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            log.warn("Speech language detection interrupted");
        } catch (Exception e) {
            log.warn("Speech language detection unavailable: {}", e.getMessage());
        }
        return SpokenLanguage.from(payload, pinnedTranscript);
    }

    /**
     * The configured prompt wins outright; otherwise the learner's own vocabulary.
     *
     * <p>Returns the literal string that goes on the wire, never null. Blank means no
     * {@code prompt} part is sent at all, which is what a learner with no saved words and a
     * default configuration gets — byte-for-byte the request that ships today.
     */
    private String resolvePrompt(List<String> learnerVocabulary) {
        if (prompt != null && !prompt.isBlank()) {
            return prompt.trim();
        }
        try {
            return vocabularyHint(learnerVocabulary);
        } catch (RuntimeException e) {
            // Nothing in vocabularyHint throws today, and this still stays. The hint is an
            // accuracy improvement; the recording is the learner's actual work. Whatever a
            // future deck entry turns out to contain, losing the hint is the acceptable
            // outcome and losing the transcription is not.
            log.warn("Could not build the speech vocabulary hint; transcribing without one: {}", e.toString());
            return "";
        }
    }

    /**
     * How many of the learner's words are worth sending.
     *
     * <p>Whisper's prompt window is about 224 tokens and everything past it is silently
     * dropped, so the cap is a correctness property, not a tuning knob. English runs near
     * four characters per token, which puts the window at roughly 900 characters;
     * {@link #MAX_VOCABULARY_HINT_CHARS} takes half of that so that vocabulary — which is
     * where a learner's rarer, multi-token words live — cannot overrun it.
     *
     * <p>{@link #MAX_VOCABULARY_HINT_WORDS} is the intent and the character budget is the
     * guarantee: 48 entries at an average English word plus ", " is around 430 characters,
     * so under normal decks the two caps agree and the count is what actually binds. 48
     * rather than "as many as fit" because the hint is a bias, not a dictionary — a longer
     * list spreads the model's attention across words the learner is not about to say, and
     * the words that matter are the ones at the front.
     */
    static final int MAX_VOCABULARY_HINT_WORDS = 48;
    static final int MAX_VOCABULARY_HINT_CHARS = 450;

    /**
     * A deck entry is a headword or a short phrase ("look forward to", "in spite of").
     * Longer than three words it is a note or a sentence somebody typed into the wrong box,
     * and prose is the one thing that must never reach this prompt.
     */
    static final int MAX_WORDS_PER_ENTRY = 3;
    static final int MAX_ENTRY_CHARS = 32;

    /**
     * Punctuation that would make an entry read as a sentence, or break the list apart.
     * Apostrophes and hyphens are deliberately absent: "don't" and "well-known" are words.
     */
    private static final Pattern PROSE_PUNCTUATION = Pattern.compile("[.,;:!?\"“”\\r\\n]");

    private static final Pattern WHITESPACE = Pattern.compile("\\s+");

    /**
     * The learner's own words, as a comma-separated spelling hint.
     *
     * <p>This is the use the {@code prompt} field's comment describes and nobody had taken
     * up. It exists because of the first real feedback this app ever received — "audio to
     * text loses accuracy" — and the three transcripts captured behind it:
     * "I am agree with you" heard as "I am angry with you", "I very like this app" as
     * "I'm very naked", "I am married with a teacher" as "married with the future". Each one
     * is worse than a plain mis-hear, because the tutor then corrects a sentence the learner
     * never said. If "agree" is in the deck, Whisper is far less willing to hear "angry".
     *
     * <p>A list, never a sentence. That distinction is the whole of the bug this file's
     * biggest comment records: the prompt is prepended as prior transcript text, so anything
     * that reads like the start of a paragraph gets continued into invented subtitle
     * boilerplate. A bare comma-separated list is what OpenAI documents for vocabulary
     * hints, and it is enforced here rather than trusted: entries carrying sentence
     * punctuation, or longer than {@link #MAX_WORDS_PER_ENTRY} words, are dropped outright.
     *
     * <p>Never throws and never returns null. A learner with nothing saved gets "", which
     * sends no prompt at all.
     */
    static String vocabularyHint(List<String> learnerVocabulary) {
        if (learnerVocabulary == null || learnerVocabulary.isEmpty()) {
            return "";
        }
        Set<String> seen = new LinkedHashSet<>();
        StringBuilder hint = new StringBuilder();
        for (String raw : learnerVocabulary) {
            if (seen.size() >= MAX_VOCABULARY_HINT_WORDS) {
                break;
            }
            String entry = normalizeVocabularyEntry(raw);
            if (entry == null || !seen.add(entry.toLowerCase(Locale.ROOT))) {
                continue;
            }
            int separator = hint.length() == 0 ? 0 : 2;
            if (hint.length() + separator + entry.length() > MAX_VOCABULARY_HINT_CHARS) {
                // The list is ranked, so the budget is spent on the front of it. Stop rather
                // than skip: everything after this point is a worse candidate anyway.
                break;
            }
            if (hint.length() > 0) {
                hint.append(", ");
            }
            hint.append(entry);
        }
        return hint.toString();
    }

    /** One deck entry, or null if it is not something that belongs in a Whisper prompt. */
    private static String normalizeVocabularyEntry(String raw) {
        if (raw == null) {
            return null;
        }
        String entry = WHITESPACE.matcher(raw.trim()).replaceAll(" ");
        if (entry.isEmpty() || entry.length() > MAX_ENTRY_CHARS) {
            return null;
        }
        if (PROSE_PUNCTUATION.matcher(entry).find()) {
            return null;
        }
        if (entry.split(" ").length > MAX_WORDS_PER_ENTRY) {
            return null;
        }
        return entry;
    }

    /**
     * Whisper handing the prompt straight back, which is the risk this feature opens.
     *
     * <p>The prompt is prior transcript text. Given silence and a list to continue, the
     * model can do to a word list what it once did to the prose prompt: carry on writing it.
     * A transcript that is letter-for-letter the hint we just sent is not speech.
     *
     * <p>Only fires on an exact match of a hint of at least {@link #MIN_ECHO_WORDS} words,
     * because a false positive here deletes something a learner actually said — the failure
     * this whole file is organised around avoiding. One deck word coming back as a
     * one-word transcript is a learner saying that word, and it is left alone.
     */
    static final int MIN_ECHO_WORDS = 4;

    static boolean isPromptEcho(String text, String promptSent) {
        if (text == null || promptSent == null || promptSent.isBlank()) {
            return false;
        }
        String normalizedPrompt = normalizeForEcho(promptSent);
        if (normalizedPrompt.split(" ").length < MIN_ECHO_WORDS) {
            return false;
        }
        return normalizedPrompt.equals(normalizeForEcho(text));
    }

    private static String normalizeForEcho(String value) {
        String stripped = value.toLowerCase(Locale.ROOT).replaceAll("[^\\p{L}\\p{Nd}]+", " ");
        return WHITESPACE.matcher(stripped).replaceAll(" ").trim();
    }

    /**
     * Below this, tell the learner the transcript is worth a second look.
     *
     * <p>The threshold lives here because the client must not have to know what a log
     * probability is; it gets a boolean and the number behind it, nothing to interpret.
     *
     * <p>-0.8 sits deliberately between the two numbers this file already uses. Whisper's
     * avg_logprob reads as roughly confident above -0.5 and shaky below -0.8, and
     * {@link #AVG_LOGPROB_THRESHOLD} (-1.0) is already this file's line for "so unlikely
     * this may not be speech at all". So the two form one scale rather than competing:
     * -0.8 flags a transcript, -1.0 (together with a high no_speech_prob) discards it, and
     * nothing can be flagged that was not first allowed through.
     *
     * <p>-0.8 rather than -0.5 for the reason {@link #segmentsLookLikeSilence} already gives:
     * a poor log-probability on its own fires on a strong accent, which is most of this
     * app's audience. A warning that appears on every genuine attempt is a warning learners
     * stop reading, and then it protects nobody.
     */
    static final double LOW_CONFIDENCE_AVG_LOGPROB_THRESHOLD = -0.8;

    /**
     * The worst segment decides, not the average.
     *
     * <p>The tutor corrects the whole utterance, so one badly-heard clause is enough to make
     * the correction wrong — "I am agree with you" heard as "I am angry with you" is three
     * words inside a longer sentence. An average would let a long confident stretch bury a
     * short garbled one, which is precisely the case the learner complained about.
     *
     * <p>Null when no segment carries the field. Absent data is not evidence of trouble,
     * the same rule {@link #segmentsLookLikeSilence} applies in the other direction.
     */
    static Double worstAvgLogprob(Object rawSegments) {
        if (!(rawSegments instanceof List<?> segments) || segments.isEmpty()) {
            return null;
        }
        Double worst = null;
        for (Object entry : segments) {
            if (!(entry instanceof Map<?, ?> segment)) {
                continue;
            }
            Double avgLogprob = asDouble(segment.get("avg_logprob"));
            if (avgLogprob != null && (worst == null || avgLogprob < worst)) {
                worst = avgLogprob;
            }
        }
        return worst;
    }

    /** False for a missing number: no data means no warning, never a warning by default. */
    static boolean isLowConfidence(Double avgLogprob) {
        return avgLogprob != null && avgLogprob < LOW_CONFIDENCE_AVG_LOGPROB_THRESHOLD;
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
     * those two cases.
     *
     * <p>A backstop, not the fix. Measured on a real recording of an empty room, this model
     * reported {@code no_speech_prob = 0.0} — total confidence that speech was present. The
     * cause was the priming prompt (see the {@code prompt} field): the model was continuing
     * text it had been given rather than inventing speech, and it was right to be sure about
     * that. With the prompt removed the hallucination is gone at source; this check stays for
     * genuinely empty audio, but nothing should be built on the assumption that it fires.
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
