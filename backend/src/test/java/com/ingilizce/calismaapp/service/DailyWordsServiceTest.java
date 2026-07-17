package com.ingilizce.calismaapp.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ingilizce.calismaapp.entity.DailyContent;
import com.ingilizce.calismaapp.repository.DailyContentRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class DailyWordsServiceTest {

    @Mock
    private DailyContentRepository dailyContentRepository;

    @Mock
    private AiCompletionProvider aiCompletionProvider;

    private DailyWordsService dailyWordsService;

    @BeforeEach
    void setUp() {
        dailyWordsService = new DailyWordsService(
                dailyContentRepository,
                aiCompletionProvider,
                new ObjectMapper());
        ReflectionTestUtils.setField(dailyWordsService, "groqApiKey", "test-key");
    }

    @Test
    void getDailyWords_ShouldPassRecentWordsAndTopicIntoPrompt() {
        LocalDate date = LocalDate.of(2026, 5, 30);
        when(dailyContentRepository.findByContentDateAndContentType(eq(date), eq("daily_words_v3")))
                .thenReturn(Optional.empty());
        when(dailyContentRepository.findByContentTypeAndContentDateBetweenOrderByContentDateDesc(
                eq("daily_words_v3"), any(LocalDate.class), any(LocalDate.class)))
                .thenReturn(List.of());
        when(dailyContentRepository.findByContentTypeAndContentDateBetweenOrderByContentDateDesc(
                eq("daily_words_v2"), any(LocalDate.class), any(LocalDate.class)))
                .thenReturn(List.of());
        when(dailyContentRepository.findByContentTypeAndContentDateBetweenOrderByContentDateDesc(
                eq("daily_words_v1"), any(LocalDate.class), any(LocalDate.class)))
                .thenReturn(List.of(new DailyContent(
                        date.minusDays(1),
                        "daily_words_v1",
                        "{\"words\":[{\"word\":\"resilient\"}]}")));
        when(aiCompletionProvider.chatCompletion(any(), anyBoolean(), isNull()))
                .thenReturn("""
                        {"words":[
                          {"id":1,"word":"route","pronunciation":"/ru:t/","translation":"rota","meanings":[{"translation":"rota","sense":"way to a place","exampleSentence":"Which route is faster?","exampleTranslation":"Hangi rota daha hızlı?"},{"translation":"güzergah","sense":"planned path","exampleSentence":"The bus route changed.","exampleTranslation":"Otobüs güzergahı değişti."}],"partOfSpeech":"Noun","definition":"A way to a place.","exampleSentence":"Which route is faster?","exampleTranslation":"Hangi rota daha hızlı?","synonyms":["path"],"difficulty":"Easy"},
                          {"id":2,"word":"navigate","pronunciation":"/navigeit/","translation":"yolunu bulmak","meanings":[{"translation":"yolunu bulmak","sense":"find the way","exampleSentence":"We navigated the city.","exampleTranslation":"Şehirde yolumuzu bulduk."},{"translation":"idare etmek","sense":"handle a difficult situation","exampleSentence":"She navigated the meeting well.","exampleTranslation":"Toplantıyı iyi idare etti."}],"partOfSpeech":"Verb","definition":"To find the way.","exampleSentence":"We navigated the city.","exampleTranslation":"Şehirde yolumuzu bulduk.","synonyms":["guide"],"difficulty":"Medium"},
                          {"id":3,"word":"delay","pronunciation":"/dilei/","translation":"gecikme","meanings":[{"translation":"gecikme","sense":"extra waiting time","exampleSentence":"The delay was short.","exampleTranslation":"Gecikme kısaydı."},{"translation":"ertelemek","sense":"make something happen later","exampleSentence":"They delayed the launch.","exampleTranslation":"Lansmanı ertelediler."}],"partOfSpeech":"Noun","definition":"Extra waiting time.","exampleSentence":"The delay was short.","exampleTranslation":"Gecikme kısaydı.","synonyms":["wait"],"difficulty":"Easy"},
                          {"id":4,"word":"accessible","pronunciation":"/aksesibıl/","translation":"erişilebilir","meanings":[{"translation":"erişilebilir","sense":"easy to reach","exampleSentence":"The station is accessible.","exampleTranslation":"İstasyona erişilebilir."},{"translation":"anlaşılır","sense":"easy to understand","exampleSentence":"Her talk was accessible.","exampleTranslation":"Konuşması anlaşılırdı."}],"partOfSpeech":"Adjective","definition":"Easy to reach.","exampleSentence":"The station is accessible.","exampleTranslation":"İstasyona erişilebilir.","synonyms":["reachable"],"difficulty":"Medium"},
                          {"id":5,"word":"commute","pronunciation":"/kəmyu:t/","translation":"işe gidip gelmek","meanings":[{"translation":"işe gidip gelmek","sense":"travel to work","exampleSentence":"Do you commute by train?","exampleTranslation":"İşe trenle mi gidip geliyorsun?"},{"translation":"yolculuk","sense":"regular trip to work","exampleSentence":"Her commute takes an hour.","exampleTranslation":"İşe gidiş yolculuğu bir saat sürüyor."}],"partOfSpeech":"Verb","definition":"Travel to work.","exampleSentence":"Do you commute by train?","exampleTranslation":"İşe trenle mi gidip geliyorsun?","synonyms":["travel"],"difficulty":"Hard"}
                        ]}
                        """);

        List<Map<String, Object>> words = dailyWordsService.getDailyWords(date);

        assertEquals(5, words.size());
        ArgumentCaptor<List<Map<String, String>>> messagesCaptor = ArgumentCaptor.forClass(List.class);
        verify(aiCompletionProvider).chatCompletion(messagesCaptor.capture(), eq(false), isNull());
        String userPrompt = messagesCaptor.getValue().get(1).get("content");
        assertTrue(userPrompt.contains("TODAY'S TOPIC CATEGORY"));
        assertTrue(userPrompt.contains("EXCLUDE recently used words: [resilient]"));
        assertTrue(userPrompt.contains("meanings (Array of 2-3 objects"));
        verify(dailyContentRepository).save(any(DailyContent.class));
    }

    @Test
    void getDailyWords_shouldReturnCachedWordsWithoutCallingProvider() {
        LocalDate date = LocalDate.of(2026, 7, 5);
        when(dailyContentRepository.findByContentDateAndContentType(date, "daily_words_v3"))
                .thenReturn(Optional.of(new DailyContent(
                        date,
                        "daily_words_v3",
                        """
                                {"words":[
                                  {"id":1,"word":"cached","translation":"önbellek"},
                                  {"id":2,"word":"stable","translation":"sabit"}
                                ]}
                                """)));

        List<Map<String, Object>> words = dailyWordsService.getDailyWords(date);

        assertEquals(2, words.size());
        assertEquals("cached", words.get(0).get("word"));
        verify(aiCompletionProvider, never()).chatCompletion(any(), anyBoolean(), any());
        verify(dailyContentRepository, never()).save(any(DailyContent.class));
    }

    @Test
    void getDailyWords_shouldReturnEmptyListForMalformedCachedPayload() {
        LocalDate date = LocalDate.of(2026, 7, 5);
        when(dailyContentRepository.findByContentDateAndContentType(date, "daily_words_v3"))
                .thenReturn(Optional.of(new DailyContent(date, "daily_words_v3", "{broken")));

        List<Map<String, Object>> words = dailyWordsService.getDailyWords(date);

        assertTrue(words.isEmpty());
        verify(aiCompletionProvider, never()).chatCompletion(any(), anyBoolean(), any());
    }

    @Test
    void getDailyWords_shouldUseFallbackBankWhenApiKeyIsMissing() {
        ReflectionTestUtils.setField(dailyWordsService, "groqApiKey", "");
        when(dailyContentRepository.findByContentDateAndContentType(any(LocalDate.class), eq("daily_words_v3")))
                .thenReturn(Optional.empty());

        List<String> firstWords = new java.util.ArrayList<>();
        LocalDate cursor = LocalDate.of(2026, 1, 1);
        for (int i = 0; i < 80 && firstWords.size() < 8; i++) {
            List<Map<String, Object>> words = dailyWordsService.getDailyWords(cursor.plusDays(i));
            assertEquals(5, words.size());
            String firstWord = (String) words.get(0).get("word");
            if (!firstWords.contains(firstWord)) {
                firstWords.add(firstWord);
            }
        }

        assertTrue(firstWords.contains("resilient"));
        assertTrue(firstWords.contains("clarify"));
        assertTrue(firstWords.contains("commute"));
        assertTrue(firstWords.contains("ingredient"));
        assertTrue(firstWords.contains("symptom"));
        assertTrue(firstWords.contains("device"));
        assertTrue(firstWords.contains("deadline"));
        assertTrue(firstWords.contains("habit"));
        verify(aiCompletionProvider, never()).chatCompletion(any(), anyBoolean(), any());
        verify(dailyContentRepository, never()).save(any(DailyContent.class));
    }

    @Test
    void getDailyWords_shouldFallbackAndNotPersistWhenProviderReturnsInvalidPayload() {
        LocalDate date = LocalDate.of(2026, 2, 3);
        when(dailyContentRepository.findByContentDateAndContentType(date, "daily_words_v3"))
                .thenReturn(Optional.empty());
        when(dailyContentRepository.findByContentTypeAndContentDateBetweenOrderByContentDateDesc(
                any(), any(LocalDate.class), any(LocalDate.class)))
                .thenReturn(List.of());
        when(aiCompletionProvider.chatCompletion(any(), anyBoolean(), isNull()))
                .thenReturn("{\"words\":[{\"word\":\"only-one\"}]}");

        List<Map<String, Object>> words = dailyWordsService.getDailyWords(date);

        assertEquals(5, words.size());
        verify(dailyContentRepository, never()).save(any(DailyContent.class));
    }

    @Test
    void getDailyWords_shouldIgnoreBrokenRecentContentWhenBuildingExcludeList() {
        LocalDate date = LocalDate.of(2026, 5, 31);
        when(dailyContentRepository.findByContentDateAndContentType(eq(date), eq("daily_words_v3")))
                .thenReturn(Optional.empty());
        when(dailyContentRepository.findByContentTypeAndContentDateBetweenOrderByContentDateDesc(
                eq("daily_words_v3"), any(LocalDate.class), any(LocalDate.class)))
                .thenReturn(List.of(new DailyContent(date.minusDays(1), "daily_words_v3", "{broken")));
        when(dailyContentRepository.findByContentTypeAndContentDateBetweenOrderByContentDateDesc(
                eq("daily_words_v2"), any(LocalDate.class), any(LocalDate.class)))
                .thenReturn(List.of());
        when(dailyContentRepository.findByContentTypeAndContentDateBetweenOrderByContentDateDesc(
                eq("daily_words_v1"), any(LocalDate.class), any(LocalDate.class)))
                .thenReturn(List.of());
        when(aiCompletionProvider.chatCompletion(any(), anyBoolean(), isNull()))
                .thenReturn("""
                        text before
                        {"words":[
                          {"id":1,"word":"privacy","pronunciation":"/p/","translation":"gizlilik","meanings":[{"translation":"gizlilik","sense":"personal data","exampleSentence":"Privacy matters.","exampleTranslation":"Gizlilik önemlidir."},{"translation":"mahremiyet","sense":"private life","exampleSentence":"Respect privacy.","exampleTranslation":"Mahremiyete saygı duy."}],"partOfSpeech":"Noun","definition":"Private information.","exampleSentence":"Privacy matters.","exampleTranslation":"Gizlilik önemlidir.","synonyms":["confidentiality"],"difficulty":"Easy"},
                          {"id":2,"word":"update","pronunciation":"/u/","translation":"güncellemek","meanings":[{"translation":"güncellemek","sense":"make current","exampleSentence":"Update the app.","exampleTranslation":"Uygulamayı güncelle."},{"translation":"güncelleme","sense":"new version","exampleSentence":"The update is small.","exampleTranslation":"Güncelleme küçük."}],"partOfSpeech":"Verb","definition":"Make newer.","exampleSentence":"Update the app.","exampleTranslation":"Uygulamayı güncelle.","synonyms":["refresh"],"difficulty":"Easy"},
                          {"id":3,"word":"reliable","pronunciation":"/r/","translation":"güvenilir","meanings":[{"translation":"güvenilir","sense":"can be trusted","exampleSentence":"It is reliable.","exampleTranslation":"Güvenilirdir."},{"translation":"sağlam","sense":"works well","exampleSentence":"The signal is reliable.","exampleTranslation":"Sinyal sağlam."}],"partOfSpeech":"Adjective","definition":"Can be trusted.","exampleSentence":"It is reliable.","exampleTranslation":"Güvenilirdir.","synonyms":["dependable"],"difficulty":"Medium"},
                          {"id":4,"word":"device","pronunciation":"/d/","translation":"cihaz","meanings":[{"translation":"cihaz","sense":"electronic tool","exampleSentence":"The device is new.","exampleTranslation":"Cihaz yeni."},{"translation":"araç","sense":"tool","exampleSentence":"Use this device.","exampleTranslation":"Bu aracı kullan."}],"partOfSpeech":"Noun","definition":"A tool.","exampleSentence":"The device is new.","exampleTranslation":"Cihaz yeni.","synonyms":["tool"],"difficulty":"Medium"},
                          {"id":5,"word":"shortcut","pronunciation":"/s/","translation":"kısayol","meanings":[{"translation":"kısayol","sense":"quick way","exampleSentence":"Use a shortcut.","exampleTranslation":"Kısayol kullan."},{"translation":"kısa yol","sense":"faster route","exampleSentence":"This shortcut helps.","exampleTranslation":"Bu kısa yol yardımcı olur."}],"partOfSpeech":"Noun","definition":"A quicker way.","exampleSentence":"Use a shortcut.","exampleTranslation":"Kısayol kullan.","synonyms":["quick route"],"difficulty":"Hard"}
                        ]}
                        trailing text
                        """);

        List<Map<String, Object>> words = dailyWordsService.getDailyWords(date);

        assertEquals(5, words.size());
        assertEquals("privacy", words.get(0).get("word"));
        verify(dailyContentRepository).save(any(DailyContent.class));
    }
}
