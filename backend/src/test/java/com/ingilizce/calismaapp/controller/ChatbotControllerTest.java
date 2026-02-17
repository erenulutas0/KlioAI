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
    private ClientIpResolver clientIpResolver;

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
        when(aiTokenQuotaService.check(anyLong(), anyString()))
                .thenReturn(AiTokenQuotaService.Decision.allowed());
        when(aiTokenQuotaService.consume(anyLong(), anyString(), anyLong()))
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
        when(chatbotService.chat("Hello")).thenReturn(ai("Hi there!"));

        mockMvc.perform(post("/api/chatbot/chat")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"message\":\"Hello\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.response").value("Hi there!"))
                .andExpect(jsonPath("$.timestamp").exists());
    }

    @Test
    void chatReturnsBadRequestWhenHeaderMissing() throws Exception {
        mockMvc.perform(post("/api/chatbot/chat")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"message\":\"Hello\"}"))
                .andExpect(status().isBadRequest());

        verify(chatbotService, never()).chat(anyString());
    }

    @Test
    void chatReturnsBadRequestWhenHeaderInvalid() throws Exception {
        mockMvc.perform(post("/api/chatbot/chat")
                .header("X-User-Id", "invalid")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"message\":\"Hello\"}"))
                .andExpect(status().isBadRequest());

        verify(chatbotService, never()).chat(anyString());
    }

    @Test
    void chatReturnsInternalServerErrorWhenServiceThrows() throws Exception {
        when(chatbotService.chat(anyString())).thenThrow(new RuntimeException("downstream"));

        mockMvc.perform(post("/api/chatbot/chat")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"message\":\"Hello\"}"))
                .andExpect(status().isInternalServerError());
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

        verify(chatbotService, never()).chat(anyString());
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

        verify(chatbotService, never()).chat(anyString());
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
                .thenReturn("[{\"englishSentence\":\"Cached sentence\",\"turkishFullTranslation\":\"Onbellekten\"}]");

        mockMvc.perform(post("/api/chatbot/generate-sentences")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"word\":\"apple\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.count").value(1))
                .andExpect(jsonPath("$.cached").value(true))
                .andExpect(jsonPath("$.sentences[0]").value("Cached sentence"));

        verify(chatbotService, never()).generateSentences(anyString());
        assertEquals(beforeLookupHit + 1.0, counterValue("chatbot.sentences.cache.lookup.total", "hit"), 0.0001);
        assertEquals(beforeLookupTimerHit + 1, timerCount("chatbot.sentences.cache.lookup.latency", "hit"));
    }

    @Test
    void generateSentencesCachesFreshResponseWhenCacheMiss() throws Exception {
        double beforeLookupMiss = counterValue("chatbot.sentences.cache.lookup.total", "miss");
        double beforeWriteStored = counterValue("chatbot.sentences.cache.write.total", "stored");

        when(chatbotService.generateSentences(anyString()))
                .thenReturn(ai("[{\"englishSentence\":\"I eat apple\",\"turkishFullTranslation\":\"Elma yerim\"}]"));

        mockMvc.perform(post("/api/chatbot/generate-sentences")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"word\":\"apple\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.count").value(1))
                .andExpect(jsonPath("$.cached").value(false));

        verify(valueOperations).set(anyString(), anyString(), any(Duration.class));
        assertEquals(beforeLookupMiss + 1.0, counterValue("chatbot.sentences.cache.lookup.total", "miss"), 0.0001);
        assertEquals(beforeWriteStored + 1.0, counterValue("chatbot.sentences.cache.write.total", "stored"), 0.0001);
    }

    @Test
    void generateSentencesRecordsCacheErrorMetricWhenCacheReadFails() throws Exception {
        double beforeLookupError = counterValue("chatbot.sentences.cache.lookup.total", "error");
        double beforeWriteStored = counterValue("chatbot.sentences.cache.write.total", "stored");

        when(valueOperations.get(anyString())).thenThrow(new RuntimeException("redis-down"));
        when(chatbotService.generateSentences(anyString()))
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
    void generateSentencesFallsBackToDefaultLevelAndLengthWhenInvalid() throws Exception {
        Map<String, Object> request = Map.of(
                "word", "apple",
                "levels", List.of("Z9"),
                "lengths", List.of("verylong"));

        when(chatbotService.generateSentences(anyString()))
                .thenReturn(ai("[{\"englishSentence\":\"I eat apple\",\"turkishFullTranslation\":\"Elma yerim\"}]"));

        mockMvc.perform(post("/api/chatbot/generate-sentences")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.count").value(1));

        verify(chatbotService).generateSentences(argThat(msg ->
                msg.contains("Level: B1") && msg.contains("Length: medium")));
    }

    @Test
    void generateSentencesTrimsResultToFive() throws Exception {
        when(chatbotService.generateSentences(anyString())).thenReturn(ai("""
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
    }

    @Test
    void generateSentencesParsesWrappedSentencesObject() throws Exception {
        when(chatbotService.generateSentences(anyString()))
                .thenReturn(ai("{\"sentences\":[{\"englishSentence\":\"I read\",\"turkishFullTranslation\":\"Okurum\"}]}"));

        mockMvc.perform(post("/api/chatbot/generate-sentences")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"word\":\"book\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.count").value(1))
                .andExpect(jsonPath("$.sentences[0]").value("I read"));
    }

    @Test
    void generateSentencesParsesSingleSentenceObject() throws Exception {
        when(chatbotService.generateSentences(anyString()))
                .thenReturn(ai("{\"englishSentence\":\"I run\",\"turkishFullTranslation\":\"Koşarım\"}"));

        mockMvc.perform(post("/api/chatbot/generate-sentences")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"word\":\"run\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.count").value(1))
                .andExpect(jsonPath("$.translations[0]").value("Koşarım"));
    }

    @Test
    void generateSentencesReturnsInternalServerErrorWhenParsingFails() throws Exception {
        when(chatbotService.generateSentences(anyString())).thenReturn(ai("not-json-at-all"));

        mockMvc.perform(post("/api/chatbot/generate-sentences")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"word\":\"apple\"}"))
                .andExpect(status().isInternalServerError());
    }

    @Test
    void generateSentencesParsesCheckGrammarFlagWhenProvided() throws Exception {
        when(chatbotService.generateSentences(anyString()))
                .thenReturn(ai("[{\"englishSentence\":\"I read\",\"turkishFullTranslation\":\"Okurum\"}]"));

        mockMvc.perform(post("/api/chatbot/generate-sentences")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"word\":\"book\",\"checkGrammar\":\"true\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.count").value(1));
    }

    @Test
    void generateSentencesParsesMapWithoutSentencesKey_AsSingleSentenceFallback() throws Exception {
        when(chatbotService.generateSentences(anyString()))
                .thenReturn(ai("{\"englishSentence\":\"Fallback\",\"turkishFullTranslation\":null}"));

        mockMvc.perform(post("/api/chatbot/generate-sentences")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"word\":\"fallback\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.count").value(1))
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
        when(chatbotService.checkTranslation(anyString()))
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
        when(chatbotService.checkTranslation(anyString()))
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
    void checkTranslationHandlesNullServiceResponseWithSafeFallback() throws Exception {
        when(chatbotService.checkTranslation(anyString())).thenReturn(null);

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
        when(chatbotService.checkEnglishTranslation(anyString()))
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
                msg.contains("Reference: I am learning")));
    }

    @Test
    void checkTranslationReturnsInternalServerErrorWhenServiceThrows() throws Exception {
        when(chatbotService.checkTranslation(anyString())).thenThrow(new RuntimeException("llm down"));

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
        when(chatbotService.checkTranslation(anyString())).thenReturn(ai("{}"));

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
        when(chatbotService.evaluateSpeakingTest(anyString())).thenReturn(ai("{\"score\":80}"));

        mockMvc.perform(post("/api/chatbot/speaking-test/evaluate")
                .header("X-User-Id", "1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"testType\":\"IELTS\",\"question\":\"Q\",\"response\":\"A\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.score").value(80));
    }

    @Test
    void evaluateSpeakingTestReturnsInternalServerErrorWhenInvalidJson() throws Exception {
        when(chatbotService.evaluateSpeakingTest(anyString())).thenReturn(ai("bad-json"));

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
        when(aiTokenQuotaService.check(anyLong(), anyString()))
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
    void proxiedAiEndpointsShareSameUserDailyTokenQuota() throws Exception {
        AtomicInteger checkCount = new AtomicInteger(0);
        when(aiTokenQuotaService.check(eq(1L), anyString()))
                .thenAnswer(invocation -> {
                    if (checkCount.incrementAndGet() == 1) {
                        return AiTokenQuotaService.Decision.allowed();
                    }
                    return AiTokenQuotaService.Decision.blocked("daily-token-quota", 300, 50000, 50000);
                });
        when(aiProxyService.dictionaryLookup("apple"))
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

        verify(aiTokenQuotaService).check(1L, "dictionary-lookup");
        verify(aiTokenQuotaService).check(1L, "reading-generate");
        verify(aiTokenQuotaService).consume(1L, "dictionary-lookup", 120L);
        verify(aiTokenQuotaService, never()).consume(eq(1L), eq("reading-generate"), anyLong());
        verify(aiProxyService, times(1)).dictionaryLookup("apple");
        verify(aiProxyService, never()).generateReadingPassage(anyString());
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
                .andExpect(jsonPath("$.remainingPercent").value(75.0));
    }

    private static User activeUser() {
        User user = new User();
        user.setSubscriptionEndDate(LocalDateTime.now().plusDays(3));
        return user;
    }

    private static User inactiveUser() {
        User user = new User();
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
