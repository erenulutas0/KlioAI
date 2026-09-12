package com.ingilizce.calismaapp.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.serializer.SerializationException;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;

/**
 * Redis-backed short-term speaking-chat memory (prompt strategy Phase 2, "conversation memory").
 *
 * Stores the last few user/assistant turns per user so the speaking partner can
 * follow up coherently instead of treating every message as a fresh conversation.
 * Degrades safely to stateless chat when Redis is unavailable.
 *
 * <p>Each message is stored as a JSON string, not as a map. It was a {@code Map.of(...)},
 * which the template's GenericJackson2JsonRedisSerializer writes without a type id (the class
 * is final) and then refuses to read back -- so every read failed, the failure was logged at
 * debug, and the model answered every turn of every conversation with no history at all.
 * On a device a waiter greeted the learner and offered them red wine three turns running,
 * after they had ordered it. A String goes through that serializer and back unchanged.
 */
@Service
public class ConversationSessionService {

    private static final Logger log = LoggerFactory.getLogger(ConversationSessionService.class);

    private static final String KEY_PREFIX = "chat:session:user:";
    private static final Duration SESSION_TTL = Duration.ofHours(2);

    /**
     * How long one conversation is remembered once it has its own memory.
     *
     * <p>Longer than the per-user memory, because what it is for is going back: the app keeps
     * every conversation in a history sheet, and a learner who opens one from yesterday should
     * find the character remembering it. Twelve messages a conversation is a few kilobytes.
     */
    private static final Duration THREAD_TTL = Duration.ofDays(7);

    /** What a thread id may be. The app sends a timestamp; anything else is not a key. */
    private static final Pattern THREAD_ID = Pattern.compile("[A-Za-z0-9_-]{1,64}");
    private static final int MAX_STORED_MESSAGES = 12;
    private static final int CONTEXT_MESSAGES = 6;

    private static final ObjectMapper JSON = new ObjectMapper();

    private final RedisTemplate<String, Object> redisTemplate;

    public ConversationSessionService(
            @Autowired(required = false) RedisTemplate<String, Object> redisTemplate) {
        this.redisTemplate = redisTemplate;
    }

    /**
     * Last few chat messages for prompt context, oldest first.
     * Each entry is a provider-ready map with "role" and "content" keys.
     */
    public List<Map<String, String>> recentMessages(Long userId) {
        return recentMessages(userId, null);
    }

    /**
     * The same, for one conversation.
     *
     * <p>Memory used to be one list per learner. Measured on a device: a learner ordered the
     * lasagne in one conversation, opened an older one from the history sheet -- the bill had
     * come, EUR 42 -- and said "It's too much, isn't it?". The waiter answered that the lasagne
     * was sold out and offered water: the newest conversation's memory, applied to the one on
     * the screen. Clearing the list on opening would only have swapped the wrong memory for
     * none. Each conversation keeps its own, and the one on the screen is the one remembered.
     *
     * @param threadId the app's id for the conversation, or null for the per-learner memory an
     *     older app still uses
     */
    public List<Map<String, String>> recentMessages(Long userId, String threadId) {
        if (userId == null || redisTemplate == null) {
            return List.of();
        }
        try {
            List<Object> stored = redisTemplate.opsForList().range(key(userId, threadId), -CONTEXT_MESSAGES, -1);
            if (stored == null || stored.isEmpty()) {
                return List.of();
            }
            List<Map<String, String>> messages = new ArrayList<>(stored.size());
            for (Object entry : stored) {
                Map<?, ?> map = decode(entry);
                if (map == null) {
                    continue;
                }
                Object role = map.get("role");
                Object content = map.get("content");
                if (role instanceof String roleText && content instanceof String contentText
                        && !roleText.isBlank() && !contentText.isBlank()) {
                    messages.add(Map.of("role", roleText, "content", contentText));
                }
            }
            return messages;
        } catch (SerializationException e) {
            // Written in a shape this template cannot read back -- every list written before
            // messages became strings. It is lost either way; clearing it lets the next turns
            // build a history that works, instead of failing the same way for two hours.
            log.warn("Conversation history for userId={} could not be read and was cleared: {}",
                    userId, e.toString());
            clear(key(userId, threadId), userId);
            return List.of();
        } catch (Exception e) {
            // A warning, not a debug line: this is the model answering with no memory of the
            // conversation, and at debug it went unnoticed for as long as it was happening.
            log.warn("Conversation history unavailable for userId={}: {}", userId, e.toString());
            return List.of();
        }
    }

    /** One stored message as a map, or null if it is not one. */
    private static Map<?, ?> decode(Object entry) {
        if (entry instanceof Map<?, ?> map) {
            return map;
        }
        if (entry instanceof String text) {
            try {
                Object parsed = JSON.readValue(text, Map.class);
                return parsed instanceof Map<?, ?> map ? map : null;
            } catch (Exception e) {
                return null;
            }
        }
        return null;
    }

    /** One message as the JSON string it is stored as. See the class comment for why a string. */
    private static String encode(String role, String content) {
        Map<String, String> message = new LinkedHashMap<>();
        message.put("role", role);
        message.put("content", content);
        try {
            return JSON.writeValueAsString(message);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("A two-string map cannot fail to serialize", e);
        }
    }

    /**
     * Total stored messages for the active session (bounded by {@link #MAX_STORED_MESSAGES}).
     * Used to derive the conversation phase.
     */
    public int sessionMessageCount(Long userId) {
        return sessionMessageCount(userId, null);
    }

    /** The same, for one conversation. See {@link #recentMessages(Long, String)}. */
    public int sessionMessageCount(Long userId, String threadId) {
        if (userId == null || redisTemplate == null) {
            return 0;
        }
        try {
            Long size = redisTemplate.opsForList().size(key(userId, threadId));
            return size == null ? 0 : size.intValue();
        } catch (Exception e) {
            log.debug("Conversation size unavailable for userId={}: {}", userId, e.toString());
            return 0;
        }
    }

    /**
     * Records what was said, whichever half of it exists.
     *
     * <p>A blank assistant reply used to discard the learner's own message along with it,
     * because one guard covered the whole turn. The learner then spoke again and the model
     * answered from a history in which they had never said the first thing — out of context,
     * for a reason invisible from either end. Their message is the half that cannot be
     * recovered: the model can be asked again, the learner cannot be asked to re-type
     * something they believe they already said.
     */
    public void recordTurn(Long userId, String userMessage, String assistantReply) {
        recordTurn(userId, null, userMessage, assistantReply);
    }

    /** The same, for one conversation. See {@link #recentMessages(Long, String)}. */
    public void recordTurn(Long userId, String threadId, String userMessage, String assistantReply) {
        if (userId == null || redisTemplate == null) {
            return;
        }
        boolean hasUserMessage = userMessage != null && !userMessage.isBlank();
        boolean hasAssistantReply = assistantReply != null && !assistantReply.isBlank();
        if (!hasUserMessage && !hasAssistantReply) {
            return;
        }
        try {
            String key = key(userId, threadId);
            if (hasUserMessage) {
                redisTemplate.opsForList().rightPush(key, encode("user", userMessage));
            }
            if (hasAssistantReply) {
                redisTemplate.opsForList().rightPush(key, encode("assistant", assistantReply));
            }
            redisTemplate.opsForList().trim(key, -MAX_STORED_MESSAGES, -1);
            redisTemplate.expire(key, validThread(threadId) != null ? THREAD_TTL : SESSION_TTL);
        } catch (Exception e) {
            log.debug("Could not record conversation turn for userId={}: {}", userId, e.toString());
        }
    }

    /**
     * Forgets everything the model has been told so far.
     *
     * <p>The client starts a fresh thread when the learner switches scene or
     * speaker, or asks for a new conversation, and clears its own screen. The
     * model's memory lived here and was never cleared with it, so after moving
     * from the cafe scene to free chat the next reply was still shaped by six
     * lines of barista -- and a comment on the client swore the server kept no
     * history at all, which had been true before this class existed.
     */
    public void clearSession(Long userId) {
        if (userId == null || redisTemplate == null) {
            return;
        }
        clear(key(userId, null), userId);
    }

    private void clear(String key, Long userId) {
        try {
            redisTemplate.delete(key);
        } catch (Exception e) {
            log.debug("Could not clear conversation for userId={}: {}", userId, e.toString());
        }
    }

    /**
     * The per-learner list, or one conversation's. A thread id that is not a plain token falls
     * back to the per-learner list: the id becomes part of a Redis key, and a learner's own
     * memory is the worst an odd id should be able to reach.
     */
    private String key(Long userId, String threadId) {
        String thread = validThread(threadId);
        return thread == null
                ? KEY_PREFIX + userId + ":messages"
                : KEY_PREFIX + userId + ":thread:" + thread + ":messages";
    }

    private static String validThread(String threadId) {
        if (threadId == null) {
            return null;
        }
        String trimmed = threadId.trim();
        return THREAD_ID.matcher(trimmed).matches() ? trimmed : null;
    }
}
