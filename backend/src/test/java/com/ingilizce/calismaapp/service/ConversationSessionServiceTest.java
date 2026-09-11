package com.ingilizce.calismaapp.service;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.redis.core.ListOperations;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.serializer.GenericJackson2JsonRedisSerializer;
import org.springframework.data.redis.serializer.SerializationException;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class ConversationSessionServiceTest {

    private static final String KEY = "chat:session:user:42:messages";

    @Mock
    private RedisTemplate<String, Object> redisTemplate;

    @Mock
    private ListOperations<String, Object> listOperations;

    private ConversationSessionService service;

    @BeforeEach
    void setUp() {
        service = new ConversationSessionService(redisTemplate);
        lenient().when(redisTemplate.opsForList()).thenReturn(listOperations);
    }

    /** A message as it is stored: a JSON string. */
    private static String stored(String role, String content) {
        return "{\"role\":\"" + role + "\",\"content\":\"" + content + "\"}";
    }

    /**
     * The conversation memory never worked in production.
     *
     * <p>Turns were pushed as {@code Map.of(...)}, which the template's
     * GenericJackson2JsonRedisSerializer writes as plain JSON with no {@code @class} and then
     * refuses to read back. The failure was logged at debug and the history came back empty on
     * every turn: on a device a waiter greeted the learner and offered them red wine three
     * turns running, after they had ordered it. Every other test here mocks the template, so no
     * value ever went through that serializer -- which is how the old tests passed while pinning
     * the bug. This one sends what recordTurn stores through it, as Redis would, and reads it
     * back through recentMessages.
     */
    @Test
    void aTurnStoredThroughTheRealSerializerReadsBack() {
        GenericJackson2JsonRedisSerializer serializer = new GenericJackson2JsonRedisSerializer();
        List<Object> redis = new ArrayList<>();
        when(listOperations.rightPush(eq(KEY), any())).thenAnswer(invocation -> {
            redis.add(serializer.deserialize(serializer.serialize(invocation.getArgument(1))));
            return (long) redis.size();
        });
        when(listOperations.range(KEY, -6, -1)).thenAnswer(invocation -> List.copyOf(redis));

        service.recordTurn(42L, "A glass of red wine, please.",
                "Sure, a glass of \"Chianti\" it is.\nAnything to eat?");

        List<Map<String, String>> history = service.recentMessages(42L);
        assertEquals(2, history.size());
        assertEquals(Map.of("role", "user", "content", "A glass of red wine, please."), history.get(0));
        assertEquals(Map.of("role", "assistant", "content", "Sure, a glass of \"Chianti\" it is.\nAnything to eat?"),
                history.get(1));
    }

    @Test
    void historyWrittenTheOldWayIsClearedRatherThanFailingForTwoHours() {
        // A list pushed as Map.of before the fix cannot be read back, and one bad entry fails
        // the whole range. Clearing it lets the next turns build a history that works.
        when(listOperations.range(KEY, -6, -1))
                .thenThrow(new SerializationException("missing type id property '@class'"));

        assertTrue(service.recentMessages(42L).isEmpty());
        verify(redisTemplate).delete(KEY);
    }

    @Test
    void recentMessages_ShouldReadStoredTurns_AndSkipAnythingUnusable() {
        when(listOperations.range(KEY, -6, -1)).thenReturn(List.of(
                stored("user", "Hi"),
                stored("assistant", "Hey! How's your day?"),
                stored("user", ""),
                "not json at all",
                Map.of("role", "user", "content", "a map, if a serializer ever hands one back"),
                42));

        List<Map<String, String>> messages = service.recentMessages(42L);

        assertEquals(3, messages.size());
        assertEquals("user", messages.get(0).get("role"));
        assertEquals("Hi", messages.get(0).get("content"));
        assertEquals("assistant", messages.get(1).get("role"));
        assertEquals("a map, if a serializer ever hands one back", messages.get(2).get("content"));
    }

    @Test
    void recentMessages_ShouldDegradeToEmpty_WhenRedisFails() {
        when(listOperations.range(anyString(), eq(-6L), eq(-1L)))
                .thenThrow(new RuntimeException("redis down"));

        assertTrue(service.recentMessages(42L).isEmpty());
        // Redis being down is not a reason to throw away a history it may still have.
        verify(redisTemplate, never()).delete(anyString());
    }

    @Test
    void recentMessages_ShouldDegradeToEmpty_WithoutRedisOrUser() {
        assertTrue(new ConversationSessionService(null).recentMessages(42L).isEmpty());
        assertTrue(service.recentMessages(null).isEmpty());
    }

    @Test
    void recordTurn_ShouldPushTrimAndRefreshTtl() {
        service.recordTurn(42L, "Hello", "Hi there!");

        verify(listOperations).rightPush(KEY, stored("user", "Hello"));
        verify(listOperations).rightPush(KEY, stored("assistant", "Hi there!"));
        verify(listOperations).trim(KEY, -12, -1);
        verify(redisTemplate).expire(KEY, Duration.ofHours(2));
    }

    @Test
    void recordTurn_ShouldSkipOnlyWhenThereIsNothingToStore() {
        // This test used to assert that a turn with a blank assistant reply stored nothing at
        // all - it pinned the bug rather than the behaviour. Dropping the learner's message
        // because the model returned nothing left the next reply answering a history in which
        // they had never spoken. What is genuinely not worth storing is a turn with no
        // content on either side, or one with no user to store it against.
        service.recordTurn(42L, "   ", null);
        service.recordTurn(null, "Hello", "Hi");

        verify(listOperations, never()).rightPush(anyString(), any());
    }

    @Test
    void sessionMessageCount_ShouldReturnStoredSizeAndDegradeToZero() {
        when(listOperations.size(KEY)).thenReturn(8L);
        assertEquals(8, service.sessionMessageCount(42L));

        when(listOperations.size(KEY)).thenThrow(new RuntimeException("redis down"));
        assertEquals(0, service.sessionMessageCount(42L));

        assertEquals(0, service.sessionMessageCount(null));
        assertEquals(0, new ConversationSessionService(null).sessionMessageCount(42L));
    }

    @Test
    void sessionMessageCount_ShouldHandleNullSize() {
        when(listOperations.size(KEY)).thenReturn(null);
        assertEquals(0, service.sessionMessageCount(42L));
    }

    @Test
    void aBlankReplyStillKeepsWhatTheLearnerSaid() {
        // One guard used to cover the whole turn, so an empty completion discarded the
        // learner's own message with it. They spoke again and the model answered from a
        // history in which they had never said the first thing. Their half is the one that
        // cannot be recovered - the model can be asked again, the learner cannot be asked to
        // re-type something they believe they already said.
        service.recordTurn(42L, "I went to the stadium yesterday.", "");

        verify(listOperations).rightPush(KEY, stored("user", "I went to the stadium yesterday."));
        verify(listOperations, never()).rightPush(KEY, stored("assistant", ""));
        verify(redisTemplate).expire(KEY, Duration.ofHours(2));
    }

    @Test
    void aTurnWithNeitherHalfIsNotRecorded() {
        service.recordTurn(42L, "  ", null);

        verify(listOperations, never()).rightPush(anyString(), any());
    }

    @Test
    void aCompleteTurnStillRecordsBothHalvesInOrder() {
        service.recordTurn(42L, "Hi", "Hey! How's your day?");

        org.mockito.InOrder order = org.mockito.Mockito.inOrder(listOperations);
        order.verify(listOperations).rightPush(KEY, stored("user", "Hi"));
        order.verify(listOperations).rightPush(KEY, stored("assistant", "Hey! How's your day?"));
    }
}
