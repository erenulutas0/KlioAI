package com.ingilizce.calismaapp.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ingilizce.calismaapp.entity.User;
import com.ingilizce.calismaapp.entity.Word;
import com.ingilizce.calismaapp.repository.UserRepository;
import com.ingilizce.calismaapp.security.ClientIpResolver;
import com.ingilizce.calismaapp.service.AiRateLimitService;
import com.ingilizce.calismaapp.service.AiTokenQuotaService;
import com.ingilizce.calismaapp.service.AiProxyService;
import com.ingilizce.calismaapp.service.ChatbotService;
import com.ingilizce.calismaapp.service.GrammarCheckService;
import com.ingilizce.calismaapp.service.GroqSpeechToTextService;
import com.ingilizce.calismaapp.service.LearningLanguageProfile;
import com.ingilizce.calismaapp.service.ProgressService;
import com.ingilizce.calismaapp.service.SentenceStarterTrackingService;
import com.ingilizce.calismaapp.service.WordService;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.search.MeterNotFoundException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.ValueOperations;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;

import java.time.LocalDateTime;
import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@TestPropertySource(properties = {
                "GROQ_API_KEY=dummy-key",
                "spring.datasource.url=jdbc:h2:mem:chatbotdb;DB_CLOSE_DELAY=-1;MODE=PostgreSQL",
                "spring.datasource.driver-class-name=org.h2.Driver"
})
public class ChatbotControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private ChatbotService chatbotService;

    @MockBean
    private WordService wordService;

    @MockBean
    private UserRepository userRepository;

    @MockBean
    private GrammarCheckService grammarCheckService;

    @MockBean
    private RedisTemplate<String, String> redisTemplate;

    @MockBean
    private ValueOperations<String, String> valueOperations;

    @MockBean
    private AiRateLimitService aiRateLimitService;

    @MockBean
    private AiTokenQuotaService aiTokenQuotaService;

    @MockBean
    private AiProxyService aiProxyService;

    @MockBean
    private GroqSpeechToTextService speechToTextService;

    @MockBean
    private ClientIpResolver clientIpResolver;

    @MockBean
    private ProgressService progressService;

    @MockBean
    private SentenceStarterTrackingService sentenceStarterTrackingService;

    @Autowired
    private MeterRegistry meterRegistry;

    @Autowired
    private ObjectMapper objectMapper;

    @BeforeEach
    void setUp() {
        when(userRepository.findById(anyLong())).thenReturn(Optional.of(activeUser()));
        when(redisTemplate.opsForValue()).thenReturn(valueOperations);
        when(valueOperations.get(anyString())).thenReturn(null);
        when(clientIpResolver.resolve(any())).thenReturn("127.0.0.1");
        when(aiRateLimitService.checkAndConsume(anyLong(), anyString(), anyString()))
                .thenReturn(AiRateLimitService.Decision.allowed());
        when(aiTokenQuotaService.check(anyLong(), anyString(), nullable(String.class), anyString()))
                .thenReturn(AiTokenQuotaService.Decision.allowed());
        when(aiTokenQuotaService.consume(anyLong(), anyString(), anyLong(), nullable(String.class), anyString()))
                .thenReturn(new AiTokenQuotaService.Usage(0L, 0L, 0L));
        when(aiTokenQuotaService.getGlobalUsage(anyLong()))
                .thenReturn(new AiTokenQuotaService.Usage(0L, 50_000L, 50_000L));
    }

    @Test
    void chatReturnsForbiddenWhenSubscriptionInactive() throws Exception {
        when(userRepository.findById(2L)).thenReturn(Optional.of(inactiveUser()));

        mockMvc.perform(post("/api/chatbot/chat")
                .header("X-User-Id", "2")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"message\":\"Hello\"}"))
                .andExpect(status().isForbidden());
    }

    @Test
    void chatReturnsForbiddenForUserOneWhenSubscriptionInactive() throws Exception {
        when(userRepository.findById(1L)).thenReturn(Optional.of(inactiveUser()));

        mockMvc.perform(post("/api/chatbot/chat")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"message\":\"Hello\"}"))
                .andExpect(status().isForbidden());
    }

    @Test
    void chatReturnsBadRequestWhenMessageMissing() throws Exception {
        mockMvc.perform(post("/api/chatbot/chat")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"message\":\"   \"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void chatReturnsOkWhenValid() throws Exception {
        when(chatbotService.chat("Hello", null, null, 1L, LearningLanguageProfile.defaultProfile()))
                .thenReturn(ai("Hi there!"));

        mockMvc.perform(post("/api/chatbot/chat")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"message\":\"Hello\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.response").value("Hi there!"))
                .andExpect(jsonPath("$.timestamp").exists());

        // Regression guard for the premortem finding: previously only SRS
        // review and adding a new word touched the daily streak, so a user
        // who only chatted/read/wrote that day still lost their streak.
        verify(progressService).updateStreak(1L);
    }

    @Test
    void chatPassesLanguageProfileFromRequestBody() throws Exception {
        when(chatbotService.chat(anyString(), any(), any(), anyLong(), any(LearningLanguageProfile.class)))
                .thenReturn(ai("Hi there!"));

        mockMvc.perform(post("/api/chatbot/chat")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                        {
                          "message":"Hello",
                          "sourceLanguage":"Spanish",
                          "targetLanguage":"English",
                          "feedbackLanguage":"Spanish",
                          "englishLevel":"A2",
                          "learningGoal":"Travel"
                        }
                        """))
                .andExpect(status().isOk());

        verify(chatbotService).chat(eq("Hello"), any(), any(), eq(1L),
                argThat((LearningLanguageProfile profile) ->
                        "Spanish".equals(profile.sourceLanguage())
                                && "A2".equals(profile.englishLevel())
                                && "Travel".equals(profile.learningGoal())));
    }

    @Test
    void chatReturnsBadRequestWhenHeaderMissing() throws Exception {
        mockMvc.perform(post("/api/chatbot/chat")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"message\":\"Hello\"}"))
                .andExpect(status().isBadRequest());

        verify(chatbotService, never())
                .chat(anyString(), nullable(String.class), nullable(String.class), anyLong(),
                        any(LearningLanguageProfile.class));
    }

    @Test
    void chatReturnsBadRequestWhenHeaderInvalid() throws Exception {
        mockMvc.perform(post("/api/chatbot/chat")
                .header("X-User-Id", "invalid")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"message\":\"Hello\"}"))
                .andExpect(status().isBadRequest());

        verify(chatbotService, never())
                .chat(anyString(), nullable(String.class), nullable(String.class), anyLong(),
                        any(LearningLanguageProfile.class));
    }

    @Test
    void chatReturnsInternalServerErrorWhenServiceThrows() throws Exception {
        when(chatbotService.chat(anyString(), nullable(String.class), nullable(String.class), anyLong(),
                any(LearningLanguageProfile.class)))
                .thenThrow(new RuntimeException("downstream"));

        mockMvc.perform(post("/api/chatbot/chat")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"message\":\"Hello\"}"))
                .andExpect(status().isInternalServerError());
    }

    @Test
    void speechTranscribeReturnsTextAndConsumesEstimatedAudioTokens() throws Exception {
        when(speechToTextService.transcribe(any(byte[].class), eq("speech.m4a"), eq("audio/mp4"), eq("en_US")))
                .thenReturn(new GroqSpeechToTextService.TranscriptionResult("I want to practice speaking.", "whisper-large-v3-turbo"));

        MockMultipartFile audio = new MockMultipartFile(
                "audio",
                "speech.m4a",
                "audio/mp4",
                new byte[]{1, 2, 3, 4});

        mockMvc.perform(multipart("/api/chatbot/speech/transcribe")
                .file(audio)
                .param("durationMs", "2100")
                .param("locale", "en_US")
                .header("X-User-Id", "1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.text").value("I want to practice speaking."))
                .andExpect(jsonPath("$.model").value("whisper-large-v3-turbo"))
                .andExpect(jsonPath("$.estimatedTokens").value(100));

        verify(aiTokenQuotaService).consume(eq(1L), eq("speech-transcribe"), eq(100L), nullable(String.class), eq("127.0.0.1"));
    }

    @Test
    void speechTranscribeRejectsTooLongAudioBeforeCallingGroq() throws Exception {
        MockMultipartFile audio = new MockMultipartFile(
                "audio",
                "speech.m4a",
                "audio/mp4",
                new byte[]{1, 2, 3, 4});

        mockMvc.perform(multipart("/api/chatbot/speech/transcribe")
                .file(audio)
                .param("durationMs", "61000")
                .header("X-User-Id", "1"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.reason").value("audio-too-long"));

        verify(speechToTextService, never()).transcribe(any(), any(), any(), any());
    }

    @Test
    void chatReturnsTooManyRequestsWhenAiRateLimitExceeded() throws Exception {
        when(aiRateLimitService.checkAndConsume(anyLong(), anyString(), anyString()))
                .thenReturn(AiRateLimitService.Decision.blocked("daily-quota", 120));

        mockMvc.perform(post("/api/chatbot/chat")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"message\":\"Hello\"}"))
                .andExpect(status().isTooManyRequests())
                .andExpect(jsonPath("$.reason").value("daily-quota"))
                .andExpect(jsonPath("$.retryAfterSeconds").value(120));

        verify(chatbotService, never())
                .chat(anyString(), nullable(String.class), nullable(String.class), anyLong());
        // A blocked request never reaches consumeAiTokens, so it must not
        // credit the streak either.
        verify(progressService, never()).updateStreak(anyLong());
    }

    @Test
    void chatReturnsPenaltyMetadataWhenAbuseBanApplied() throws Exception {
        when(aiRateLimitService.checkAndConsume(anyLong(), anyString(), anyString()))
                .thenReturn(AiRateLimitService.Decision.blockedWithPenalty("user-burst", 30, 1, 60));

        mockMvc.perform(post("/api/chatbot/chat")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"message\":\"Hello\"}"))
                .andExpect(status().isTooManyRequests())
                .andExpect(jsonPath("$.reason").value("user-burst"))
                .andExpect(jsonPath("$.banLevel").value(1))
                .andExpect(jsonPath("$.nextBanSeconds").value(60))
                .andExpect(jsonPath("$.abuseWarning").exists());

        verify(chatbotService, never())
                .chat(anyString(), nullable(String.class), nullable(String.class), anyLong());
    }

    @Test
    void generateSentencesReturnsBadRequestWhenWordMissing() throws Exception {
        mockMvc.perform(post("/api/chatbot/generate-sentences")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void generateSentencesReturnsCachedResponseWhenAvailable() throws Exception {
        double beforeLookupHit = counterValue("chatbot.sentences.cache.lookup.total", "hit");
        long beforeLookupTimerHit = timerCount("chatbot.sentences.cache.lookup.latency", "hit");

        when(valueOperations.get(anyString()))
                .thenReturn("[{\"englishSentence\":\"I ate an apple after lunch.\",\"turkishFullTranslation\":\"Ogleden sonra bir elma yedim.\"}]");

        mockMvc.perform(post("/api/chatbot/generate-sentences")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"word\":\"apple\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.count").value(5))
                .andExpect(jsonPath("$.cached").value(true))
                .andExpect(jsonPath("$.sentences[0]").value("I ate an apple after lunch."));

        verify(chatbotService, never()).generateSentences(anyString(), any(LearningLanguageProfile.class));
        assertEquals(beforeLookupHit + 1.0, counterValue("chatbot.sentences.cache.lookup.total", "hit"), 0.0001);
        assertEquals(beforeLookupTimerHit + 1, timerCount("chatbot.sentences.cache.lookup.latency", "hit"));
    }

    @Test
    void generateSentencesCachesFreshResponseWhenCacheMiss() throws Exception {
        double beforeLookupMiss = counterValue("chatbot.sentences.cache.lookup.total", "miss");
        double beforeWriteStored = counterValue("chatbot.sentences.cache.write.total", "stored");

        when(chatbotService.generateSentences(anyString(), any(LearningLanguageProfile.class)))
                .thenReturn(ai("[{\"englishSentence\":\"I eat apple\",\"turkishFullTranslation\":\"Elma yerim\"}]"));

        mockMvc.perform(post("/api/chatbot/generate-sentences")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"word\":\"apple\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.count").value(5))
                .andExpect(jsonPath("$.cached").value(false));

        verify(valueOperations).set(anyString(), anyString(), any(Duration.class));
        assertEquals(beforeLookupMiss + 1.0, counterValue("chatbot.sentences.cache.lookup.total", "miss"), 0.0001);
        assertEquals(beforeWriteStored + 1.0, counterValue("chatbot.sentences.cache.write.total", "stored"), 0.0001);
    }

    @Test
    void generateSentencesReturnsDeterministicFallbackWhenAiProviderFails() throws Exception {
        when(chatbotService.generateSentences(anyString(), any(LearningLanguageProfile.class)))
                .thenThrow(new RuntimeException("Groq API Error: model unavailable"));

        mockMvc.perform(post("/api/chatbot/generate-sentences")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"word\":\"focus\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.count").value(5))
                .andExpect(jsonPath("$.cached").value(false))
                .andExpect(jsonPath("$.sentences[0]").value("Please focus on the main problem first."));

        verify(aiTokenQuotaService, never()).consume(eq(1L), eq("generate-sentences"), anyLong(),
                nullable(String.class), anyString());
    }

    @Test
    void generateSentencesReturnsDeterministicFallbackWhenAiProviderFails_ForNonTurkishSource() throws Exception {
        when(chatbotService.generateSentences(anyString(), any(LearningLanguageProfile.class)))
                .thenThrow(new RuntimeException("Groq API Error: model unavailable"));

        mockMvc.perform(post("/api/chatbot/generate-sentences")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"word\":\"focus\",\"sourceLanguage\":\"Spanish\",\"targetLanguage\":\"English\",\"feedbackLanguage\":\"Spanish\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.count").value(5))
                .andExpect(jsonPath("$.sentences[0]").value("Please focus on the main problem first."))
                .andExpect(jsonPath("$.translations[0]").value(""));
    }

    @Test
    void generateSentencesRecordsCacheErrorMetricWhenCacheReadFails() throws Exception {
        double beforeLookupError = counterValue("chatbot.sentences.cache.lookup.total", "error");
        double beforeWriteStored = counterValue("chatbot.sentences.cache.write.total", "stored");

        when(valueOperations.get(anyString())).thenThrow(new RuntimeException("redis-down"));
        when(chatbotService.generateSentences(anyString(), any(LearningLanguageProfile.class)))
                .thenReturn(ai("[{\"englishSentence\":\"I eat apple\",\"turkishFullTranslation\":\"Elma yerim\"}]"));

        mockMvc.perform(post("/api/chatbot/generate-sentences")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"word\":\"apple\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.cached").value(false));

        assertEquals(beforeLookupError + 1.0, counterValue("chatbot.sentences.cache.lookup.total", "error"), 0.0001);
        assertEquals(beforeWriteStored + 1.0, counterValue("chatbot.sentences.cache.write.total", "stored"), 0.0001);
    }

    @Test
    void generateSentencesReturnsForbiddenWhenSubscriptionInactive() throws Exception {
        when(userRepository.findById(2L)).thenReturn(Optional.of(inactiveUser()));

        mockMvc.perform(post("/api/chatbot/generate-sentences")
                .header("X-User-Id", "2")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"word\":\"apple\"}"))
                .andExpect(status().isForbidden());
    }

    @Test
    void generateSentencesReturnsUpgradeRequiredWhenAiAccessDisabledEvenIfCacheHit() throws Exception {
        when(aiTokenQuotaService.getEntitlement(1L))
                .thenReturn(new AiTokenQuotaService.Entitlement("FREE", false, 0L, false, 0));
        when(aiTokenQuotaService.check(eq(1L), eq("generate-sentences"), nullable(String.class), anyString()))
                .thenReturn(AiTokenQuotaService.Decision.blocked("ai-access-disabled", 0, 0, 0));
        when(valueOperations.get(anyString()))
                .thenReturn("[{\"englishSentence\":\"Cached sentence\",\"turkishFullTranslation\":\"Onbellekten\"}]");

        mockMvc.perform(post("/api/chatbot/generate-sentences")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"word\":\"apple\"}"))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.reason").value("ai-access-disabled"))
                .andExpect(jsonPath("$.upgradeRequired").value(true));

        verify(chatbotService, never()).generateSentences(anyString(), any(LearningLanguageProfile.class));
    }

    @Test
    void generateSentencesFallsBackToDefaultLevelAndLengthWhenInvalid() throws Exception {
        Map<String, Object> request = Map.of(
                "word", "apple",
                "levels", List.of("Z9"),
                "lengths", List.of("verylong"));

        when(chatbotService.generateSentences(anyString(), any(LearningLanguageProfile.class)))
                .thenReturn(ai("[{\"englishSentence\":\"I eat apple\",\"turkishFullTranslation\":\"Elma yerim\"}]"));

        mockMvc.perform(post("/api/chatbot/generate-sentences")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.count").value(5));

        verify(chatbotService).generateSentences(argThat(msg ->
                msg.contains("Level: B1") && msg.contains("Length: medium")),
                any(LearningLanguageProfile.class));
    }

    @Test
    void generateSentencesPassesLanguageProfileAndSeparatesCacheKey() throws Exception {
        when(chatbotService.generateSentences(anyString(), any(LearningLanguageProfile.class)))
                .thenReturn(ai("[{\"englishSentence\":\"I eat apple\",\"turkishFullTranslation\":\"Como manzana\"}]"));

        mockMvc.perform(post("/api/chatbot/generate-sentences")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                        {
                          "word":"apple",
                          "sourceLanguage":"tr",
                          "targetLanguage":"English",
                          "feedbackLanguage":"en",
                          "englishLevel":"B2",
                          "learningGoal":"Work"
                        }
                        """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.count").value(5));

        verify(valueOperations).get(contains("turkish:english:english:b2:work:apple"));
        verify(chatbotService).generateSentences(anyString(), argThat((LearningLanguageProfile profile) ->
                "Turkish".equals(profile.sourceLanguage())
                        && "English".equals(profile.targetLanguage())
                        && "English".equals(profile.feedbackLanguage())
                        && "B2".equals(profile.englishLevel())
                        && "Work".equals(profile.learningGoal())));
    }

    @Test
    void generateSentencesInjectsRecentStarterAvoidList_WhenTrackingServiceHasHistory() throws Exception {
        when(sentenceStarterTrackingService.recentStarters(1L)).thenReturn(List.of("The", "I"));
        when(chatbotService.generateSentences(anyString(), any(LearningLanguageProfile.class)))
                .thenReturn(ai("[{\"englishSentence\":\"Please eat the apple\",\"turkishFullTranslation\":\"t\"}]"));

        mockMvc.perform(post("/api/chatbot/generate-sentences")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"word\":\"apple\"}"))
                .andExpect(status().isOk());

        verify(chatbotService).generateSentences(argThat(msg ->
                msg.contains("recently seen sentences starting with: The, I")),
                any(LearningLanguageProfile.class));
    }

    @Test
    void generateSentencesRecordsNewStarters_AfterSuccessfulGeneration() throws Exception {
        when(sentenceStarterTrackingService.recentStarters(1L)).thenReturn(List.of());
        when(chatbotService.generateSentences(anyString(), any(LearningLanguageProfile.class)))
                .thenReturn(ai("[{\"englishSentence\":\"Please eat the apple\",\"turkishFullTranslation\":\"t\"}]"));

        mockMvc.perform(post("/api/chatbot/generate-sentences")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"word\":\"apple\"}"))
                .andExpect(status().isOk());

        verify(sentenceStarterTrackingService).recordStarters(eq(1L), argThat(starters ->
                starters.contains("Please")));
    }

    @Test
    void generateSentencesTrimsResultToFive() throws Exception {
        when(chatbotService.generateSentences(anyString(), any(LearningLanguageProfile.class))).thenReturn(ai("""
                [
                  {"englishSentence":"s1","turkishFullTranslation":"t1"},
                  {"englishSentence":"s2","turkishFullTranslation":"t2"},
                  {"englishSentence":"s3","turkishFullTranslation":"t3"},
                  {"englishSentence":"s4","turkishFullTranslation":"t4"},
                  {"englishSentence":"s5","turkishFullTranslation":"t5"},
                  {"englishSentence":"s6","turkishFullTranslation":"t6"}
                ]
                """));

        mockMvc.perform(post("/api/chatbot/generate-sentences")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"word\":\"apple\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.count").value(5));

        verify(progressService).updateStreak(1L);
    }

    @Test
    void generateSentencesParsesWrappedSentencesObject() throws Exception {
        when(chatbotService.generateSentences(anyString(), any(LearningLanguageProfile.class)))
                .thenReturn(ai("{\"sentences\":[{\"englishSentence\":\"I read\",\"turkishFullTranslation\":\"Okurum\"}]}"));

        mockMvc.perform(post("/api/chatbot/generate-sentences")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"word\":\"read\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.count").value(5))
                .andExpect(jsonPath("$.sentences[0]").value("I read"));
    }

    @Test
    void generateSentencesParsesSingleSentenceObject() throws Exception {
        when(chatbotService.generateSentences(anyString(), any(LearningLanguageProfile.class)))
                .thenReturn(ai("{\"englishSentence\":\"I run\",\"turkishFullTranslation\":\"Koşarım\"}"));

        mockMvc.perform(post("/api/chatbot/generate-sentences")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"word\":\"run\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.count").value(5))
                .andExpect(jsonPath("$.translations[0]").value("Koşarım"));
    }

    @Test
    void generateSentencesUsesDeterministicFallbackWhenParsingFails() throws Exception {
        when(chatbotService.generateSentences(anyString(), any(LearningLanguageProfile.class))).thenReturn(ai("not-json-at-all"));

        mockMvc.perform(post("/api/chatbot/generate-sentences")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"word\":\"apple\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.count").value(5))
                .andExpect(jsonPath("$.sentences[0]").value("She packed an apple for the bus ride."));
    }

    @Test
    void generateSentencesUsesDeterministicFallbackWhenModelReturnsEmptyContent() throws Exception {
        when(chatbotService.generateSentences(anyString(), any(LearningLanguageProfile.class))).thenReturn(ai(""));

        mockMvc.perform(post("/api/chatbot/generate-sentences")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"word\":\"book\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.count").value(5))
                .andExpect(jsonPath("$.sentences[0]").value("I borrowed this book from the library."));
    }

    @Test
    void generateSentencesUsesNaturalElaborateFallbackWhenModelReturnsEmptyContent() throws Exception {
        when(chatbotService.generateSentences(anyString(), any(LearningLanguageProfile.class))).thenReturn(ai(""));

        mockMvc.perform(post("/api/chatbot/generate-sentences")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"word\":\"elaborate\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.count").value(5))
                .andExpect(jsonPath("$.sentences[0]").value("Could you elaborate on your answer?"))
                .andExpect(jsonPath("$.sentences[1]").value("Maya gave an elaborate explanation after the meeting."));
    }

    @Test
    void generateSentencesFiltersMetaWordFramesFromValidJson() throws Exception {
        when(chatbotService.generateSentences(anyString(), any(LearningLanguageProfile.class))).thenReturn(ai("""
                {
                  "sentences": [
                    {"englishSentence":"A short news article used \\"delay\\" to describe the problem.","turkishFullTranslation":"Kotu"},
                    {"englishSentence":"The flight was delayed by heavy rain.","turkishTranslation":"gecikmek","turkishFullTranslation":"Ucus yogun yagmur nedeniyle gecikti."}
                  ]
                }
                """));

        mockMvc.perform(post("/api/chatbot/generate-sentences")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"word\":\"delay\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.count").value(5))
                .andExpect(jsonPath("$.sentences[0]").value("The flight was delayed by heavy rain."))
                .andExpect(jsonPath("$.sentences[1]").value("The delay forced us to change our plans."));
    }

    @Test
    void generateSentencesFiltersItemsThatDoNotUseTargetWord() throws Exception {
        when(chatbotService.generateSentences(anyString(), any(LearningLanguageProfile.class))).thenReturn(ai("""
                {
                  "sentences": [
                    {"englishSentence":"The route changed quickly.","turkishFullTranslation":"Rota hızlıca değişti."},
                    {"englishSentence":"The flight was delayed by heavy rain.","turkishTranslation":"gecikmek","turkishFullTranslation":"Ucus yogun yagmur nedeniyle gecikti."}
                  ]
                }
                """));

        mockMvc.perform(post("/api/chatbot/generate-sentences")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"word\":\"delay\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.count").value(5))
                .andExpect(jsonPath("$.sentences[0]").value("The flight was delayed by heavy rain."))
                .andExpect(jsonPath("$.sentences[1]").value("The delay forced us to change our plans."));
    }

    @Test
    void generateSentencesRecoversFromTruncatedJsonWithAtLeastOneValidObject() throws Exception {
        when(chatbotService.generateSentences(anyString(), any(LearningLanguageProfile.class))).thenReturn(ai("""
                [
                  {"englishSentence":"I read books","turkishFullTranslation":"Kitap okurum"},
                  {"englishSentence":"I wr
                """));

        mockMvc.perform(post("/api/chatbot/generate-sentences")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"word\":\"book\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.count").value(5))
                .andExpect(jsonPath("$.sentences[0]").value("I read books"))
                .andExpect(jsonPath("$.translations[0]").value("Kitap okurum"));
    }

    @Test
    void generateSentencesParsesCheckGrammarFlagWhenProvided() throws Exception {
        when(chatbotService.generateSentences(anyString(), any(LearningLanguageProfile.class)))
                .thenReturn(ai("[{\"englishSentence\":\"I read\",\"turkishFullTranslation\":\"Okurum\"}]"));

        mockMvc.perform(post("/api/chatbot/generate-sentences")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"word\":\"book\",\"checkGrammar\":\"true\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.count").value(5));
    }

    @Test
    void generateSentencesRemovesDuplicateEnglishSentences() throws Exception {
        when(chatbotService.generateSentences(anyString(), any(LearningLanguageProfile.class))).thenReturn(ai("""
                {
                  "sentences": [
                    {"englishSentence":"I read books every evening.","turkishFullTranslation":"Her aksam kitap okurum."},
                    {"englishSentence":"I read books every evening.","turkishFullTranslation":"Her aksam kitap okurum."},
                    {"englishSentence":"Reading books every evening helps me relax.","turkishFullTranslation":"Her aksam kitap okumak rahatlamama yardimci olur."}
                  ]
                }
                """));

        mockMvc.perform(post("/api/chatbot/generate-sentences")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"word\":\"book\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.count").value(5))
                .andExpect(jsonPath("$.sentences[0]").value("I read books every evening."))
                .andExpect(jsonPath("$.sentences[1]").value("Reading books every evening helps me relax."));
    }

    @Test
    void generateSentencesAddsFreshVariationInstructionsWhenRequested() throws Exception {
        when(chatbotService.generateSentences(anyString(), any(LearningLanguageProfile.class)))
                .thenReturn(ai("{\"sentences\":[{\"englishSentence\":\"Fresh sentence\",\"turkishFullTranslation\":\"Taze cumle\"}]}"));

        mockMvc.perform(post("/api/chatbot/generate-sentences")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"word\":\"apple\",\"fresh\":true}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.count").value(5));

        verify(chatbotService).generateSentences(argThat(msg ->
                msg.contains("variationSeed=")
                        && msg.contains("Avoid reusing common previous examples")
                        && msg.contains("Lengths must be meaningfully different")),
                any(LearningLanguageProfile.class));
    }

    @Test
    void generateSentencesHandlesMultipleTargetWordsAndDirection() throws Exception {
        when(chatbotService.generateSentences(anyString(), any(LearningLanguageProfile.class)))
                .thenReturn(ai("{\"sentences\":[{\"englishSentence\":\"The route changed quickly.\",\"turkishFullTranslation\":\"Rota hızlıca değişti.\"}]}"));

        mockMvc.perform(post("/api/chatbot/generate-sentences")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"word\":\"route, delay, commute\",\"direction\":\"TR_TO_EN\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.count").value(5))
                .andExpect(jsonPath("$.direction").value("TR_TO_EN"))
                .andExpect(jsonPath("$.targetWords[0]").value("route"))
                .andExpect(jsonPath("$.targetWords[1]").value("delay"));

        verify(chatbotService).generateSentences(argThat(msg ->
                msg.contains("Multi-word mode")
                        && msg.contains("Target words: route, delay, commute")
                        && msg.contains("Practice direction: TR_TO_EN")
                        && msg.contains("For source-to-English practice")),
                any(LearningLanguageProfile.class));
    }

    @Test
    void generateSentencesIncludesLearnerMeaningHintsWhenWordExists() throws Exception {
        Word word = new Word();
        word.setUserId(1L);
        word.setEnglishWord("elaborate");
        word.setTurkishMeaning("detaylandırmak");
        when(wordService.getAllWords(1L)).thenReturn(List.of(word));
        when(chatbotService.generateSentences(anyString(), any(LearningLanguageProfile.class)))
                .thenReturn(ai("{\"sentences\":[{\"englishSentence\":\"Could you elaborate on your answer?\",\"turkishFullTranslation\":\"Cevabını biraz daha detaylandırabilir misin?\"}]}"));

        mockMvc.perform(post("/api/chatbot/generate-sentences")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"word\":\"elaborate\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.count").value(5));

        verify(chatbotService).generateSentences(argThat(msg ->
                msg.contains("Target word: elaborate")
                        && msg.contains("Known learner meaning: detaylandırmak")),
                any(LearningLanguageProfile.class));
    }

    @Test
    void generateSentencesDoesNotLeakLegacyTurkishHintsForSpanishSource() throws Exception {
        Word word = new Word();
        word.setUserId(1L);
        word.setEnglishWord("elaborate");
        word.setTurkishMeaning("detaylandırmak");
        when(wordService.getAllWords(1L)).thenReturn(List.of(word));
        when(chatbotService.generateSentences(anyString(), any(LearningLanguageProfile.class)))
                .thenReturn(ai("""
                        {"sentences":[{"englishSentence":"Could you elaborate on your answer?","sourceFullTranslation":"¿Podrías explicar mejor tu respuesta?","sourceTranslation":"explicar"}]}
                        """));

        mockMvc.perform(post("/api/chatbot/generate-sentences")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                        {"word":"elaborate","sourceLanguage":"Spanish","targetLanguage":"English","feedbackLanguage":"Spanish"}
                        """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.count").value(1))
                .andExpect(jsonPath("$.translations[0]").value("¿Podrías explicar mejor tu respuesta?"));

        verify(chatbotService).generateSentences(argThat(msg ->
                msg.contains("Target word: elaborate")
                        && msg.contains("All source-language translations must be in Spanish")
                        && msg.contains("Do not output Turkish translations")
                        && msg.contains("Prefer natural, idiomatic Spanish phrasing")
                        && !msg.contains("Known learner meaning: detaylandırmak")),
                argThat(profile -> "Spanish".equals(profile.sourceLanguage())
                        && "Spanish".equals(profile.feedbackLanguage())));
    }

    @Test
    void generateSentencesUsesThinkInTurkishFirstGuidance_ForTurkishSource() throws Exception {
        when(chatbotService.generateSentences(anyString(), any(LearningLanguageProfile.class)))
                .thenReturn(ai("{\"sentences\":[{\"englishSentence\":\"Could you elaborate?\",\"turkishFullTranslation\":\"Biraz açar mısın?\"}]}"));

        mockMvc.perform(post("/api/chatbot/generate-sentences")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                        {"word":"elaborate","sourceLanguage":"Turkish","targetLanguage":"English","feedbackLanguage":"Turkish"}
                        """))
                .andExpect(status().isOk());

        verify(chatbotService).generateSentences(argThat(msg ->
                msg.contains("Prefer natural, idiomatic Turkish phrasing")
                        && msg.contains("Think in Turkish first for the full-sentence translation")
                        && !msg.contains("All source-language translations must be in Turkish")),
                any(LearningLanguageProfile.class));
    }

    @Test
    void generateSentencesParsesMapWithoutSentencesKey_AsSingleSentenceFallback() throws Exception {
        when(chatbotService.generateSentences(anyString(), any(LearningLanguageProfile.class)))
                .thenReturn(ai("{\"englishSentence\":\"Fallback\",\"turkishFullTranslation\":null}"));

        mockMvc.perform(post("/api/chatbot/generate-sentences")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"word\":\"fallback\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.count").value(5))
                .andExpect(jsonPath("$.translations[0]").value(""));
    }

    @Test
    void checkGrammarReturnsBadRequestWhenSentenceMissing() throws Exception {
        mockMvc.perform(post("/api/chatbot/check-grammar")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"sentence\":\"\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void checkGrammarReturnsOkWhenValid() throws Exception {
        when(grammarCheckService.checkGrammar("I goes to school"))
                .thenReturn(Map.of("hasErrors", true, "errorCount", 1));

        mockMvc.perform(post("/api/chatbot/check-grammar")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"sentence\":\"I goes to school\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.hasErrors").value(true));
    }

    @Test
    void checkGrammarReturnsInternalServerErrorWhenServiceThrows() throws Exception {
        when(grammarCheckService.checkGrammar(anyString())).thenThrow(new RuntimeException("grammar down"));

        mockMvc.perform(post("/api/chatbot/check-grammar")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"sentence\":\"Test\"}"))
                .andExpect(status().isInternalServerError());
    }

    @Test
    void checkGrammarReturnsForbiddenWhenSubscriptionInactive() throws Exception {
        when(userRepository.findById(2L)).thenReturn(Optional.of(inactiveUser()));

        mockMvc.perform(post("/api/chatbot/check-grammar")
                .header("X-User-Id", "2")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"sentence\":\"I am fine\"}"))
                .andExpect(status().isForbidden());
    }

    @Test
    void checkGrammarReturnsUpgradeRequiredWhenAiAccessDisabled() throws Exception {
        when(aiTokenQuotaService.getEntitlement(1L))
                .thenReturn(new AiTokenQuotaService.Entitlement("FREE", false, 0L, false, 0));
        when(aiTokenQuotaService.check(eq(1L), eq("check-grammar"), nullable(String.class), anyString()))
                .thenReturn(AiTokenQuotaService.Decision.blocked("ai-access-disabled", 0, 0, 0));

        mockMvc.perform(post("/api/chatbot/check-grammar")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"sentence\":\"I am fine\"}"))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.reason").value("ai-access-disabled"))
                .andExpect(jsonPath("$.upgradeRequired").value(true));

        verify(grammarCheckService, never()).checkGrammar(anyString());
    }

    @Test
    void checkTranslationReturnsBadRequestWhenUserTranslationMissing() throws Exception {
        mockMvc.perform(post("/api/chatbot/check-translation")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"englishSentence\":\"I love coding\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void checkTranslationReturnsBadRequestWhenTurkishSentenceMissingForTrToEn() throws Exception {
        mockMvc.perform(post("/api/chatbot/check-translation")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"direction\":\"TR_TO_EN\",\"userTranslation\":\"I love coding\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void checkTranslationReturnsBadRequestWhenEnglishSentenceMissingForEnToTr() throws Exception {
        mockMvc.perform(post("/api/chatbot/check-translation")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"direction\":\"EN_TO_TR\",\"userTranslation\":\"Kodlamayı seviyorum\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void checkTranslationReturnsParsedJsonResponse() throws Exception {
        when(chatbotService.checkTranslation(anyString(), any(LearningLanguageProfile.class)))
                .thenReturn(ai("{\"isCorrect\":true,\"correctTranslation\":\"Kodlamayı seviyorum\",\"feedback\":\"İyi\"}"));

        mockMvc.perform(post("/api/chatbot/check-translation")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"direction\":\"EN_TO_TR\",\"englishSentence\":\"I love coding\",\"userTranslation\":\"Kodlamayı seviyorum\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.isCorrect").value(true))
                .andExpect(jsonPath("$.correctTranslation").value("Kodlamayı seviyorum"));
    }

    @Test
    void checkTranslationUsesFallbackParserWhenResponseIsNotJson() throws Exception {
        when(chatbotService.checkTranslation(anyString(), any(LearningLanguageProfile.class)))
                .thenReturn(ai("Bu ceviri dogru gorunuyor."));

        mockMvc.perform(post("/api/chatbot/check-translation")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"direction\":\"EN_TO_TR\",\"englishSentence\":\"I love coding\",\"userTranslation\":\"Kodlamayı seviyorum\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.isCorrect").value(true))
                .andExpect(jsonPath("$.feedback").value("Bu ceviri dogru gorunuyor."));
    }

    @Test
    void checkTranslationFallbackParser_ShouldDetectCapitalIncorrect_OnTurkishLocaleJvm() throws Exception {
        java.util.Locale original = java.util.Locale.getDefault();
        try {
            java.util.Locale.setDefault(new java.util.Locale("tr", "TR"));
            when(chatbotService.checkTranslation(anyString(), any(LearningLanguageProfile.class)))
                    .thenReturn(ai("That translation is Incorrect, please try again."));

            mockMvc.perform(post("/api/chatbot/check-translation")
                    .header("X-User-Id", "1")
                    .contentType(MediaType.APPLICATION_JSON)
                    .content("{\"direction\":\"EN_TO_TR\",\"englishSentence\":\"I love coding\",\"userTranslation\":\"Yanlis\"}"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.isCorrect").value(false));
        } finally {
            java.util.Locale.setDefault(original);
        }
    }

    @Test
    void checkTranslationHandlesNullServiceResponseWithSafeFallback() throws Exception {
        when(chatbotService.checkTranslation(anyString(), any(LearningLanguageProfile.class))).thenReturn(null);

        mockMvc.perform(post("/api/chatbot/check-translation")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"direction\":\"EN_TO_TR\",\"englishSentence\":\"I love coding\",\"userTranslation\":\"Kodlamayı seviyorum\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.isCorrect").value(false))
                .andExpect(jsonPath("$.feedback").value(org.hamcrest.Matchers.containsString("Çeviri kontrol edilemedi")));
    }

    @Test
    void checkTranslationUsesTrToEnPathAndIncludesReferenceWhenProvided() throws Exception {
        when(chatbotService.checkEnglishTranslation(anyString(), any(LearningLanguageProfile.class)))
                .thenReturn(ai("{\"isCorrect\":true,\"correctTranslation\":\"I am learning\",\"feedback\":\"Good\"}"));

        mockMvc.perform(post("/api/chatbot/check-translation")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                        {
                          "direction":"TR_TO_EN",
                          "turkishSentence":"Ogreniyorum",
                          "englishSentence":"I am learning",
                          "userTranslation":"I am learning"
                        }
                        """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.isCorrect").value(true));

        verify(chatbotService).checkEnglishTranslation(argThat(msg ->
                msg.contains("Reference: I am learning")),
                any(LearningLanguageProfile.class));
    }

    @Test
    void checkTranslationUsesGlobalLanguageProfile() throws Exception {
        when(chatbotService.checkEnglishTranslation(anyString(), any(LearningLanguageProfile.class)))
                .thenReturn(ai("{\"isCorrect\":true,\"correctTranslation\":\"Hello\",\"feedback\":\"Good\"}"));

        mockMvc.perform(post("/api/chatbot/check-translation")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                        {
                          "direction":"SOURCE_TO_TARGET",
                          "sourceSentence":"Hola",
                          "targetSentence":"Hello",
                          "userTranslation":"Hello",
                          "sourceLanguage":"Spanish",
                          "targetLanguage":"English",
                          "feedbackLanguage":"Spanish",
                          "englishLevel":"A2",
                          "learningGoal":"Travel"
                        }
                        """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.isCorrect").value(true));

        verify(chatbotService).checkEnglishTranslation(argThat(msg ->
                msg.contains("Spanish sentence: Hola")
                        && msg.contains("User's English translation: Hello")),
                argThat((LearningLanguageProfile profile) ->
                        "Spanish".equals(profile.sourceLanguage())
                                && "English".equals(profile.targetLanguage())
                                && "Spanish".equals(profile.feedbackLanguage())
                                && "A2".equals(profile.englishLevel())
                                && "Travel".equals(profile.learningGoal())));
    }

    @Test
    void checkTranslationReturnsInternalServerErrorWhenServiceThrows() throws Exception {
        when(chatbotService.checkTranslation(anyString(), any(LearningLanguageProfile.class))).thenThrow(new RuntimeException("llm down"));

        mockMvc.perform(post("/api/chatbot/check-translation")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"direction\":\"EN_TO_TR\",\"englishSentence\":\"I love coding\",\"userTranslation\":\"Kodlamayı seviyorum\"}"))
                .andExpect(status().isInternalServerError());
    }

    @Test
    void checkTranslationReturnsForbiddenWhenSubscriptionInactive() throws Exception {
        when(userRepository.findById(2L)).thenReturn(Optional.of(inactiveUser()));

        mockMvc.perform(post("/api/chatbot/check-translation")
                .header("X-User-Id", "2")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"direction\":\"EN_TO_TR\",\"englishSentence\":\"I love coding\",\"userTranslation\":\"Kodlamayı seviyorum\"}"))
                .andExpect(status().isForbidden());
    }

    @Test
    void checkTranslationUsesDefaultFieldsWhenJsonHasNoExpectedKeys() throws Exception {
        when(chatbotService.checkTranslation(anyString(), any(LearningLanguageProfile.class))).thenReturn(ai("{}"));

        mockMvc.perform(post("/api/chatbot/check-translation")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"direction\":\"EN_TO_TR\",\"englishSentence\":\"I love coding\",\"userTranslation\":\"Kodlamayı seviyorum\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.isCorrect").value(false))
                .andExpect(jsonPath("$.correctTranslation").value(""))
                .andExpect(jsonPath("$.feedback").value("Çeviri kontrol edildi."));
    }

    @Test
    void saveToTodayReturnsBadRequestWhenEnglishWordMissing() throws Exception {
        mockMvc.perform(post("/api/chatbot/save-to-today")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"meanings\":[\"elma\"]}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void saveToTodayReturnsOkAndSavesSentences() throws Exception {
        Word saved = new Word();
        saved.setId(10L);
        saved.setUserId(1L);
        saved.setEnglishWord("apple");

        when(wordService.saveWord(any(Word.class))).thenReturn(saved);
        when(wordService.addSentence(anyLong(), anyString(), anyString(), anyString(), anyLong())).thenReturn(saved);
        when(wordService.getWordByIdAndUser(10L, 1L)).thenReturn(Optional.of(saved));

        mockMvc.perform(post("/api/chatbot/save-to-today")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                        {
                          "englishWord":"apple",
                          "meanings":["elma"],
                          "sentences":["I eat apple","Apple is red"]
                        }
                        """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true));

        verify(wordService, times(2)).addSentence(eq(10L), anyString(), eq(""), eq("medium"), eq(1L));
    }

    @Test
    void saveToTodaySkipsSentenceInsertWhenSentencesMissing() throws Exception {
        Word saved = new Word();
        saved.setId(11L);
        saved.setUserId(1L);
        saved.setEnglishWord("book");

        when(wordService.saveWord(any(Word.class))).thenReturn(saved);
        when(wordService.getWordByIdAndUser(11L, 1L)).thenReturn(Optional.of(saved));

        mockMvc.perform(post("/api/chatbot/save-to-today")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"englishWord\":\"book\",\"meanings\":[\"kitap\"]}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true));

        verify(wordService, never()).addSentence(anyLong(), anyString(), anyString(), anyString(), anyLong());
    }

    @Test
    void saveToTodayReturnsInternalServerErrorWhenSaveFails() throws Exception {
        when(wordService.saveWord(any(Word.class))).thenThrow(new RuntimeException("db down"));

        mockMvc.perform(post("/api/chatbot/save-to-today")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"englishWord\":\"apple\"}"))
                .andExpect(status().isInternalServerError());
    }

    @Test
    void generateSpeakingTestQuestionsReturnsBadRequestWhenParamsMissing() throws Exception {
        mockMvc.perform(post("/api/chatbot/speaking-test/generate-questions")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"testType\":\"IELTS\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void generateSpeakingTestQuestionsReturnsOkWhenValid() throws Exception {
        when(chatbotService.generateSpeakingTestQuestions(anyString()))
                .thenReturn(ai("{\"questions\":[\"Q1\",\"Q2\"]}"));

        mockMvc.perform(post("/api/chatbot/speaking-test/generate-questions")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"testType\":\"IELTS\",\"part\":\"Part 1\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.questions[0]").value("Q1"));
    }

    @Test
    void generateSpeakingTestQuestionsReturnsInternalServerErrorWhenInvalidJson() throws Exception {
        when(chatbotService.generateSpeakingTestQuestions(anyString())).thenReturn(ai("not-json"));

        mockMvc.perform(post("/api/chatbot/speaking-test/generate-questions")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"testType\":\"IELTS\",\"part\":\"Part 1\"}"))
                .andExpect(status().isInternalServerError());
    }

    @Test
    void generateSpeakingTestQuestionsReturnsForbiddenWhenSubscriptionInactive() throws Exception {
        when(userRepository.findById(2L)).thenReturn(Optional.of(inactiveUser()));

        mockMvc.perform(post("/api/chatbot/speaking-test/generate-questions")
                .header("X-User-Id", "2")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"testType\":\"IELTS\",\"part\":\"Part 1\"}"))
                .andExpect(status().isForbidden());
    }

    @Test
    void evaluateSpeakingTestReturnsBadRequestWhenParamsMissing() throws Exception {
        mockMvc.perform(post("/api/chatbot/speaking-test/evaluate")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"testType\":\"IELTS\",\"question\":\"Q\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void evaluateSpeakingTestReturnsOkWhenValid() throws Exception {
        when(chatbotService.evaluateSpeakingTest(anyString(), any(LearningLanguageProfile.class))).thenReturn(ai("{\"score\":80}"));

        mockMvc.perform(post("/api/chatbot/speaking-test/evaluate")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"testType\":\"IELTS\",\"question\":\"Q\",\"response\":\"A\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.score").value(80));
    }

    @Test
    void evaluateSpeakingTestPassesLanguageProfile() throws Exception {
        when(chatbotService.evaluateSpeakingTest(anyString(), any(LearningLanguageProfile.class)))
                .thenReturn(ai("{\"score\":80}"));

        mockMvc.perform(post("/api/chatbot/speaking-test/evaluate")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                        {
                          "testType":"IELTS",
                          "question":"Q",
                          "response":"A",
                          "sourceLanguage":"Turkish",
                          "targetLanguage":"English",
                          "feedbackLanguage":"English",
                          "englishLevel":"C1",
                          "learningGoal":"Exam"
                        }
                        """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.score").value(80));

        verify(chatbotService).evaluateSpeakingTest(anyString(), argThat((LearningLanguageProfile profile) ->
                "Turkish".equals(profile.sourceLanguage())
                        && "English".equals(profile.targetLanguage())
                        && "English".equals(profile.feedbackLanguage())
                        && "C1".equals(profile.englishLevel())
                        && "Exam".equals(profile.learningGoal())));
    }

    @Test
    void evaluateSpeakingTestReturnsInternalServerErrorWhenInvalidJson() throws Exception {
        when(chatbotService.evaluateSpeakingTest(anyString(), any(LearningLanguageProfile.class))).thenReturn(ai("bad-json"));

        mockMvc.perform(post("/api/chatbot/speaking-test/evaluate")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"testType\":\"IELTS\",\"question\":\"Q\",\"response\":\"A\"}"))
                .andExpect(status().isInternalServerError());
    }

    @Test
    void evaluateSpeakingTestReturnsForbiddenWhenSubscriptionInactive() throws Exception {
        when(userRepository.findById(2L)).thenReturn(Optional.of(inactiveUser()));

        mockMvc.perform(post("/api/chatbot/speaking-test/evaluate")
                .header("X-User-Id", "2")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"testType\":\"IELTS\",\"question\":\"Q\",\"response\":\"A\"}"))
                .andExpect(status().isForbidden());
    }

    @Test
    void proxiedAiEndpointsReturnTooManyRequestsWhenDailyTokenQuotaExceeded() throws Exception {
        when(aiTokenQuotaService.check(anyLong(), anyString(), nullable(String.class), anyString()))
                .thenReturn(AiTokenQuotaService.Decision.blocked("daily-token-quota", 180, 50000, 50000));

        mockMvc.perform(post("/api/chatbot/dictionary/lookup")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"word\":\"apple\"}"))
                .andExpect(status().isTooManyRequests())
                .andExpect(jsonPath("$.reason").value("daily-token-quota"));

        mockMvc.perform(post("/api/chatbot/dictionary/lookup-detailed")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"word\":\"apple\"}"))
                .andExpect(status().isTooManyRequests())
                .andExpect(jsonPath("$.reason").value("daily-token-quota"));

        mockMvc.perform(post("/api/chatbot/dictionary/explain")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"word\":\"run\",\"sentence\":\"I run every day.\"}"))
                .andExpect(status().isTooManyRequests())
                .andExpect(jsonPath("$.reason").value("daily-token-quota"));

        mockMvc.perform(post("/api/chatbot/dictionary/generate-specific-sentence")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"word\":\"run\",\"translation\":\"kosmak\",\"context\":\"exercise\"}"))
                .andExpect(status().isTooManyRequests())
                .andExpect(jsonPath("$.reason").value("daily-token-quota"));

        mockMvc.perform(post("/api/chatbot/reading/generate")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"level\":\"Intermediate\"}"))
                .andExpect(status().isTooManyRequests())
                .andExpect(jsonPath("$.reason").value("daily-token-quota"));

        mockMvc.perform(post("/api/chatbot/writing/generate-topic")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"level\":\"B2\",\"wordCount\":\"150-200\"}"))
                .andExpect(status().isTooManyRequests())
                .andExpect(jsonPath("$.reason").value("daily-token-quota"));

        mockMvc.perform(post("/api/chatbot/writing/evaluate")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                        {
                          "text":"This is my essay.",
                          "level":"B2",
                          "topic":{"topic":"Technology","description":"AI in daily life"}
                        }
                        """))
                .andExpect(status().isTooManyRequests())
                .andExpect(jsonPath("$.reason").value("daily-token-quota"));

        mockMvc.perform(post("/api/chatbot/exam/generate")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                        {
                          "examType":"YDS/YOKDIL",
                          "mode":"category",
                          "category":"grammar",
                          "questionCount":10
                        }
                        """))
                .andExpect(status().isTooManyRequests())
                .andExpect(jsonPath("$.reason").value("daily-token-quota"));

        verifyNoInteractions(aiProxyService);
    }

    @Test
    void proxiedAiEndpointsReturnForbiddenWhenAiAccessDisabled() throws Exception {
        when(aiTokenQuotaService.check(anyLong(), anyString(), nullable(String.class), anyString()))
                .thenReturn(AiTokenQuotaService.Decision.blocked("ai-access-disabled", 0, 0, 0));

        mockMvc.perform(post("/api/chatbot/dictionary/lookup")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"word\":\"apple\"}"))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.reason").value("ai-access-disabled"))
                .andExpect(jsonPath("$.upgradeRequired").value(true));

        verifyNoInteractions(aiProxyService);
    }

    @Test
    void proxiedAiEndpointsShareSameUserDailyTokenQuota() throws Exception {
        AtomicInteger checkCount = new AtomicInteger(0);
        when(aiTokenQuotaService.check(eq(1L), anyString(), nullable(String.class), anyString()))
                .thenAnswer(invocation -> {
                    if (checkCount.incrementAndGet() == 1) {
                        return AiTokenQuotaService.Decision.allowed();
                    }
                    return AiTokenQuotaService.Decision.blocked("daily-token-quota", 300, 50000, 50000);
                });
        when(aiProxyService.dictionaryLookup(eq("apple"), any(LearningLanguageProfile.class)))
                .thenReturn(new AiProxyService.AiJsonResult(
                        Map.of("word", "apple", "meanings", List.of()),
                        120,
                        80,
                        40));

        mockMvc.perform(post("/api/chatbot/dictionary/lookup")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"word\":\"apple\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.word").value("apple"));

        mockMvc.perform(post("/api/chatbot/reading/generate")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"level\":\"Intermediate\"}"))
                .andExpect(status().isTooManyRequests())
                .andExpect(jsonPath("$.reason").value("daily-token-quota"));

        verify(aiTokenQuotaService).check(eq(1L), eq("dictionary-lookup"), nullable(String.class), anyString());
        verify(aiTokenQuotaService).check(eq(1L), eq("reading-generate"), nullable(String.class), anyString());
        verify(aiTokenQuotaService).consume(eq(1L), eq("dictionary-lookup"), eq(120L), nullable(String.class), anyString());
        verify(aiTokenQuotaService, never()).consume(
                eq(1L),
                eq("reading-generate"),
                anyLong(),
                nullable(String.class),
                anyString());
        verify(aiProxyService, times(1)).dictionaryLookup(eq("apple"), any(LearningLanguageProfile.class));
        verify(aiProxyService, never()).generateReadingPassage(anyString(), any(LearningLanguageProfile.class));
    }

    @Test
    void generatePronunciationTextsReturnsAiTextOptionsAndConsumesTokens() throws Exception {
        when(aiProxyService.generatePronunciationTexts(
                eq("B1"),
                argThat(words -> words.size() == 2 && words.contains("delay") && words.contains("focus")),
                any(LearningLanguageProfile.class)))
                .thenReturn(new AiProxyService.AiJsonResult(
                        Map.of(
                                "texts", List.of(
                                        "The delayed train finally arrived after lunch.",
                                        "Please focus on the final sound of each word.",
                                        "A calm voice can make a difficult sentence easier."),
                                "level", "B1",
                                "focusWords", List.of("delay", "focus")),
                        180,
                        120,
                        60));

        mockMvc.perform(post("/api/chatbot/pronunciation/generate-texts")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                        {
                          "level":"B1",
                          "focusWords":["delay","focus"],
                          "sourceLanguage":"Turkish",
                          "targetLanguage":"English",
                          "feedbackLanguage":"Turkish"
                        }
                        """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.texts[0]").value("The delayed train finally arrived after lunch."))
                .andExpect(jsonPath("$.level").value("B1"));

        verify(aiTokenQuotaService).consume(
                eq(1L),
                eq("pronunciation-text-generate"),
                eq(180L),
                nullable(String.class),
                eq("127.0.0.1"));
    }

    @Test
    void quotaStatusReturnsCurrentTokenUsage() throws Exception {
        when(aiTokenQuotaService.getGlobalUsage(1L))
                .thenReturn(new AiTokenQuotaService.Usage(12_500L, 37_500L, 50_000L));

        mockMvc.perform(get("/api/chatbot/quota/status")
                .header("X-User-Id", "1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.tokenLimit").value(50000))
                .andExpect(jsonPath("$.tokensUsed").value(12500))
                .andExpect(jsonPath("$.tokensRemaining").value(37500))
                .andExpect(jsonPath("$.usagePercent").value(25.0))
                .andExpect(jsonPath("$.remainingPercent").value(75.0))
                // 37500 / {700, 450, 1000, 400} representative per-action token costs
                .andExpect(jsonPath("$.activityEstimates.conversations").value(53))
                .andExpect(jsonPath("$.activityEstimates.translationChecks").value(83))
                .andExpect(jsonPath("$.activityEstimates.sentenceSets").value(37))
                .andExpect(jsonPath("$.activityEstimates.grammarChecks").value(93));
    }

    private static User activeUser() {
        User user = new User();
        user.setSubscriptionEndDate(LocalDateTime.now().plusDays(3));
        return user;
    }

    private static User inactiveUser() {
        User user = new User();
        user.setCreatedAt(LocalDateTime.now().minusDays(30));
        user.setSubscriptionEndDate(LocalDateTime.now().minusDays(1));
        return user;
    }

    private double counterValue(String metricName, String outcome) {
        try {
            return meterRegistry.get(metricName).tag("outcome", outcome).counter().count();
        } catch (MeterNotFoundException ignored) {
            return 0.0;
        }
    }

    private long timerCount(String metricName, String outcome) {
        try {
            return meterRegistry.get(metricName).tag("outcome", outcome).timer().count();
        } catch (MeterNotFoundException ignored) {
            return 0L;
        }
    }

    private static ChatbotService.AiCallResult ai(String content) {
        // Token values are not asserted in these controller tests.
        return new ChatbotService.AiCallResult(content, 123, 100, 23);
    }
}
