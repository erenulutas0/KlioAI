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
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertInstanceOf;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class DailyExamPackServiceTest {

    @Mock
    private DailyContentRepository dailyContentRepository;

    @Mock
    private AiCompletionProvider aiCompletionProvider;

    private DailyExamPackService service;
    private LocalDate date;

    @BeforeEach
    void setUp() {
        service = new DailyExamPackService(dailyContentRepository, aiCompletionProvider, new ObjectMapper());
        date = LocalDate.of(2026, 4, 15);
    }

    @Test
    void getDailyExamPack_shouldPersistRichFallback_WhenGroqKeyMissing() {
        when(dailyContentRepository.findByContentDateAndContentType(date, "daily_exam_yds_v1"))
                .thenReturn(Optional.empty());
        when(dailyContentRepository.save(any(DailyContent.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        Map<String, Object> payload = service.getDailyExamPack(date, "yds");

        assertEquals("yds", payload.get("exam"));
        assertEquals(date.toString(), payload.get("date"));
        assertEquals(Boolean.TRUE, payload.get("fallback"));

        List<?> topics = assertTopicList(payload);
        assertEquals(5, topics.size());
        for (Object topicEntry : topics) {
            Map<?, ?> topic = assertInstanceOf(Map.class, topicEntry);
            List<?> questions = assertInstanceOf(List.class, topic.get("questions"));
            assertEquals(5, questions.size());
        }

        verify(aiCompletionProvider, never()).chatCompletion(any(), anyBoolean(), any());

        ArgumentCaptor<DailyContent> captor = ArgumentCaptor.forClass(DailyContent.class);
        verify(dailyContentRepository).save(captor.capture());
        assertTrue(captor.getValue().getPayloadJson().contains("\"fallback\":true"));
        assertTrue(captor.getValue().getPayloadJson().contains("\"contentVersion\":\"v2\""));
    }

    @Test
    void getDailyExamPack_shouldNormalizePartialGroqPayload_AndTopUpMissingTopics() {
        ReflectionTestUtils.setField(service, "groqApiKey", "test-key");
        when(dailyContentRepository.findByContentDateAndContentType(date, "daily_exam_yds_v1"))
                .thenReturn(Optional.empty());
        when(dailyContentRepository.save(any(DailyContent.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));
        when(aiCompletionProvider.chatCompletion(any(), anyBoolean(), any()))
                .thenReturn("""
                        {
                          "exam": "yds",
                          "date": "2026-04-15",
                          "topics": [
                            {
                              "topic": "Grammar",
                              "questions": [
                                {
                                  "id": 9,
                                  "question": "Choose the correct option: He ____ abroad for three years before returning home.",
                                  "options": {
                                    "A": "worked",
                                    "B": "has worked",
                                    "C": "had worked",
                                    "D": "works",
                                    "E": "was working"
                                  },
                                  "answer": "C",
                                  "explanation": "Past perfect shows the earlier completed duration."
                                }
                              ]
                            }
                          ]
                        }
                        """);

        Map<String, Object> payload = service.getDailyExamPack(date, "yds");

        assertEquals(Boolean.TRUE, payload.get("fallback"));

        List<?> topics = assertTopicList(payload);
        assertEquals(5, topics.size());

        Map<?, ?> grammar = assertInstanceOf(Map.class, topics.get(0));
        List<?> grammarQuestions = assertInstanceOf(List.class, grammar.get("questions"));
        assertEquals(5, grammarQuestions.size());

        Map<?, ?> firstQuestion = assertInstanceOf(Map.class, grammarQuestions.get(0));
        assertEquals("Choose the correct option: He ____ abroad for three years before returning home.",
                firstQuestion.get("question"));
        assertEquals("C", firstQuestion.get("answer"));

        Map<?, ?> vocabulary = assertInstanceOf(Map.class, topics.get(1));
        List<?> vocabularyQuestions = assertInstanceOf(List.class, vocabulary.get("questions"));
        assertEquals(5, vocabularyQuestions.size());
        assertFalse(vocabularyQuestions.isEmpty());
    }

    @Test
    void getDailyExamPack_shouldRepairMalformedCachedPayload_OnRead() throws Exception {
        ObjectMapper mapper = new ObjectMapper();
        Map<String, Object> cached = Map.of(
                "exam", "yds",
                "topics", List.of(
                        Map.of(
                                "topic", "Vocabulary",
                                "questions", List.of(
                                        Map.of(
                                                "question", "Choose the closest meaning of 'scarce'.",
                                                "options", Map.of(
                                                        "A", "abundant",
                                                        "B", "limited",
                                                        "C", "noisy",
                                                        "D", "helpful",
                                                        "E", "strange"),
                                                "answer", "B",
                                                "explanation", "Scarce means limited in amount."
                                        )
                                )
                        )
                )
        );
        DailyContent entity = new DailyContent(date, "daily_exam_yds_v1", mapper.writeValueAsString(cached));
        when(dailyContentRepository.findByContentDateAndContentType(date, "daily_exam_yds_v1"))
                .thenReturn(Optional.of(entity));

        Map<String, Object> payload = service.getDailyExamPack(date, "yds");

        assertEquals(Boolean.TRUE, payload.get("fallback"));
        List<?> topics = assertTopicList(payload);
        assertEquals(5, topics.size());
        verify(dailyContentRepository, never()).save(any());
    }

    private List<?> assertTopicList(Map<String, Object> payload) {
        return assertInstanceOf(List.class, payload.get("topics"));
    }
}
