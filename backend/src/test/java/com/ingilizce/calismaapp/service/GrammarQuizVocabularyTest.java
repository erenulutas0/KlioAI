package com.ingilizce.calismaapp.service;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

import java.util.List;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * A generic tense drill teaches a rule in isolation. The same rule over the learner's own
 * vocabulary exercises both at once — and gives the answer an identifiable word, so a right
 * or wrong response can reach the review scheduler instead of only moving a quiz score.
 *
 * <p>The risk being guarded here is the one that already bit this codebase once: forcing a
 * word into a sentence it does not fit. "Maya noticed evaluate during the trip" was
 * grammatical in shape with the target jammed into the wrong slot, and a grammar quiz that
 * did the same would be teaching the mistake it claims to test.
 */
class GrammarQuizVocabularyTest {

    @InjectMocks
    private AiProxyService aiProxyService;

    @Mock
    private AiCompletionProvider aiCompletionProvider;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
        // A usable quiz, not an empty one. These tests assert on the prompt that goes out,
        // and the service now retries once when too few questions survive the
        // duplicate-option guard - an empty stub would trigger that retry and the
        // single-call verify below would fail for a reason none of these tests are about.
        when(aiCompletionProvider.chatCompletionWithUsage(any(), anyBoolean(), any(), any(), any()))
                .thenReturn(AiCompletionProvider.CompletionResult.of(threeUsableQuestions(), 0, 0, 0));
    }

    private static String threeUsableQuestions() {
        String question = "{\"question\":\"She ---- it.\",\"options\":[\"a\",\"b\",\"c\",\"d\"],"
                + "\"correctAnswer\":\"a\",\"targetWord\":\"\"}";
        return "{\"topic\":\"Tenses\",\"questions\":["
                + String.join(",", question, question.replace("She", "He"), question.replace("She", "They"))
                + "]}";
    }

    private String promptSentTo(List<String> vocabulary) {
        aiProxyService.generateGrammarQuiz(
                "Present Perfect", "B1", LearningLanguageProfile.defaultProfile(), 0, vocabulary);

        ArgumentCaptor<List<java.util.Map<String, String>>> captor =
                ArgumentCaptor.forClass(List.class);
        verify(aiCompletionProvider).chatCompletionWithUsage(
                captor.capture(), anyBoolean(), any(), any(), any());
        return captor.getValue().get(1).get("content");
    }

    @Test
    void theLearnersWordsReachThePrompt() {
        String prompt = promptSentTo(List.of("recover", "symptom", "delay"));

        assertTrue(prompt.contains("LEARNER'S OWN VOCABULARY"));
        assertTrue(prompt.contains("recover"));
        assertTrue(prompt.contains("symptom"));
        assertTrue(prompt.contains("delay"));
    }

    @Test
    void aWordThatDoesNotFitMustBeDroppedRatherThanForced() {
        String prompt = promptSentTo(List.of("recover"));

        assertTrue(prompt.contains("leave it out"),
                "the model must be told to drop a word it cannot use naturally");
        assertTrue(prompt.contains("A forced sentence teaches the learner a mistake."),
                "the reason has to be in the prompt, not only in our heads");
        assertTrue(prompt.contains("Inflect it as the sentence requires"),
                "the dictionary form must not be dropped in unchanged");
    }

    @Test
    void theTargetWordIsRequestedBackSoTheAnswerCanBeCredited() {
        String prompt = promptSentTo(List.of("recover", "delay"));

        assertTrue(prompt.contains("targetWord"),
                "without this field the answer cannot be attached to a word");
    }

    @Test
    void theWordBelongsInTheSentenceNotTheOptions() {
        // Putting the learner's word among the answer choices would test recognition of the
        // word rather than the grammar point, and would make the credit meaningless.
        String prompt = promptSentTo(List.of("recover"));

        assertTrue(prompt.contains("belongs in the sentence, not in the answer options"));
    }

    @Test
    void anEmptyVocabularyStillProducesAnOrdinaryQuiz() {
        // A brand-new user has no words. The quiz must still generate.
        String prompt = promptSentTo(List.of());

        assertFalse(prompt.contains("LEARNER'S OWN VOCABULARY"));
        assertTrue(prompt.contains("GRAMMAR TOPIC: Present Perfect"));
    }

    @Test
    void theOlderSignatureStillWorks() {
        assertDoesNotThrow(() -> aiProxyService.generateGrammarQuiz(
                "Modals", "B2", LearningLanguageProfile.defaultProfile(), 1));
    }
}
