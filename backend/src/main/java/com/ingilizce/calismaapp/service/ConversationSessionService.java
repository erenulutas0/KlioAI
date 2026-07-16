package com.ingilizce.calismaapp.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Redis-backed short-term speaking-chat memory (prompt strategy Phase 2, "conversation memory").
 *
 * Stores the last few user/assistant turns per user so the speaking partner can
 * follow up coherently instead of treating every message as a fresh conversation.
 * Degrades safely to stateless chat when Redis is unavailable.
 */
@Service
public class ConversationSessionService {

    private static final Logger log = LoggerFactory.getLogger(ConversationSessionService.class);

    private static final String KEY_PREFIX = "chat:session:user:";
    private static final Duration SESSION_TTL = Duration.ofHours(2);
    private static final int MAX_STORED_MESSAGES = 12;
    private static final int CONTEXT_MESSAGES = 6;

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
        if (userId == null || redisTemplate == null) {
            return List.of();
        }
        try {
            List<Object> stored = redisTemplate.opsForList().range(key(userId), -CONTEXT_MESSAGES, -1);
            if (stored == null || stored.isEmpty()) {
                return List.of();
            }
            List<Map<String, String>> messages = new ArrayList<>(stored.size());
            for (Object entry : stored) {
                if (!(entry instanceof Map<?, ?> map)) {
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
        } catch (Exception e) {
            log.debug("Conversation history unavailable for userId={}: {}", userId, e.toString());
            return List.of();
        }
    }

    /**
     * Total stored messages for the active session (bounded by {@link #MAX_STORED_MESSAGES}).
     * Used to derive the conversation phase.
     */
    public int sessionMessageCount(Long userId) {
        if (userId == null || redisTemplate == null) {
            return 0;
        }
        try {
            Long size = redisTemplate.opsForList().size(key(userId));
            return size == null ? 0 : size.intValue();
        } catch (Exception e) {
            log.debug("Conversation size unavailable for userId={}: {}", userId, e.toString());
            return 0;
        }
    }

    /**
     * Appends one completed user/assistant turn and refreshes the session TTL.
     */
    public void recordTurn(Long userId, String userMessage, String assistantReply) {
        if (userId == null || redisTemplate == null
                || userMessage == null || userMessage.isBlank()
                || assistantReply == null || assistantReply.isBlank()) {
            return;
        }
        try {
            String key = key(userId);
            redisTemplate.opsForList().rightPush(key, Map.of("role", "user", "content", userMessage));
            redisTemplate.opsForList().rightPush(key, Map.of("role", "assistant", "content", assistantReply));
            redisTemplate.opsForList().trim(key, -MAX_STORED_MESSAGES, -1);
            redisTemplate.expire(key, SESSION_TTL);
        } catch (Exception e) {
            log.debug("Could not record conversation turn for userId={}: {}", userId, e.toString());
        }
    }

    private String key(Long userId) {
        return KEY_PREFIX + userId + ":messages";
    }
}
