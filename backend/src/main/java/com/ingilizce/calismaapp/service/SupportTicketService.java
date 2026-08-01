package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.entity.SupportTicket;
import com.ingilizce.calismaapp.repository.SupportTicketRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

@Service
public class SupportTicketService {
    private static final Logger logger = LoggerFactory.getLogger(SupportTicketService.class);
    private static final int DAILY_LIMIT = 3;

    private final SupportTicketRepository supportTicketRepository;

    public SupportTicketService(SupportTicketRepository supportTicketRepository) {
        this.supportTicketRepository = supportTicketRepository;
    }

    @Transactional
    public Map<String, Object> createTicket(Long userId, String type, String title, String message, String locale) {
        return createTicket(userId, type, title, message, locale, null);
    }

    /**
     * @param contextJson what the app knew when the report was written — version, screen, and
     *                    for a content report the offending text. A tester should not have to
     *                    write a bug report to be useful; the app already knows where they
     *                    were, so it says so on their behalf.
     */
    @Transactional
    public Map<String, Object> createTicket(
            Long userId, String type, String title, String message, String locale, String contextJson) {
        cleanupExpired();
        long usedToday = countToday(userId);
        if (usedToday >= DAILY_LIMIT) {
            throw new IllegalStateException("DAILY_LIMIT_REACHED");
        }

        SupportTicket ticket = new SupportTicket();
        ticket.setUserId(userId);
        ticket.setType(parseType(type));
        ticket.setTitle(title.trim());
        ticket.setMessage(message.trim());
        ticket.setLocale(locale == null ? null : locale.trim());
        // Truncated rather than rejected: an oversized context is still worth most of its
        // value, and refusing the whole report over it would lose the report.
        ticket.setContextJson(contextJson == null || contextJson.isBlank()
                ? null
                : (contextJson.length() > 4000 ? contextJson.substring(0, 4000) : contextJson));
        ticket.setExpiresAt(LocalDateTime.now().plusDays(7));

        SupportTicket saved = supportTicketRepository.save(ticket);

        // Logged at WARN, not INFO, and with the context inline. Someone telling us the
        // generated content is wrong is the only signal that catches a generator serving
        // nonsense with a 200, and it should be visible in the same place we already look
        // when something is broken rather than waiting in a table to be queried.
        if (saved.getType() == SupportTicket.TicketType.CONTENT_REPORT) {
            logger.warn("Content report from user={} title='{}' note='{}' context={}",
                    userId, saved.getTitle(), saved.getMessage(), saved.getContextJson());
        } else {
            logger.info("Support ticket type={} from user={}", saved.getType(), userId);
        }

        return ticketPayload(saved, DAILY_LIMIT - (usedToday + 1));
    }

    @Transactional
    public Map<String, Object> listTickets(Long userId) {
        cleanupExpired();
        // Filter rather than delete: the sender sees the same short list they always did,
        // while the report itself is kept.
        LocalDateTime now = LocalDateTime.now();
        List<SupportTicket> tickets = supportTicketRepository
                .findByUserIdOrderByCreatedAtDesc(userId)
                .stream()
                .filter(t -> t.getExpiresAt() == null || t.getExpiresAt().isAfter(now))
                .toList();
        long usedToday = countToday(userId);
        return Map.of(
                "tickets", tickets.stream().map(this::toPayload).toList(),
                "remainingToday", Math.max(0, DAILY_LIMIT - usedToday),
                "dailyLimit", DAILY_LIMIT
        );
    }

    @Transactional
    /**
     * Expiry now hides a ticket from the sender's own list; it no longer destroys it.
     *
     * <p>This used to call {@code deleteByExpiresAtBefore} on every create and every read, so
     * a report was permanently gone seven days after it was written. That is the wrong
     * trade for the one signal the instrumentation cannot produce: a learner telling us the
     * generated content was wrong. The dashboard reported three months of hardcoded template
     * sentences as successful requests; a person saying "this sentence is nonsense" is the
     * only thing that would have caught it, and it was on a seven-day fuse.
     *
     * <p>The sender still sees a tidy list — {@link #listTickets} filters on the same date —
     * so nothing changes for them. What changes is that the report survives long enough to
     * be acted on.
     */
    public void cleanupExpired() {
        // Intentionally empty. Kept as a method so the read paths that called it keep
        // compiling and so this comment sits where the deletion used to be.
    }

    /**
     * The inbox. Everything anyone reported, newest first, with the context attached.
     *
     * <p>A feedback mechanism whose reports nobody reads is decoration. The reports were
     * already being written to a table; this is the part that makes writing them worth
     * anything.
     *
     * @param type  optional filter, e.g. CONTENT_REPORT; null or blank means everything
     * @param days  how far back to look
     * @param limit hard cap on rows returned
     */
    @Transactional(readOnly = true)
    public Map<String, Object> inbox(String type, int days, int limit) {
        LocalDateTime since = LocalDateTime.now().minusDays(Math.max(1, days));
        Pageable page = PageRequest.of(0, Math.max(1, Math.min(limit, 500)));

        List<SupportTicket> tickets;
        if (type == null || type.isBlank()) {
            tickets = supportTicketRepository.findByCreatedAtAfterOrderByCreatedAtDesc(since, page);
        } else {
            tickets = supportTicketRepository.findByTypeAndCreatedAtAfterOrderByCreatedAtDesc(
                    parseType(type), since, page);
        }

        Map<String, Long> byType = new LinkedHashMap<>();
        for (SupportTicket ticket : tickets) {
            byType.merge(ticket.getType().name(), 1L, Long::sum);
        }

        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("tickets", tickets.stream().map(this::toInboxPayload).toList());
        payload.put("count", tickets.size());
        payload.put("countByType", byType);
        payload.put("sinceDays", Math.max(1, days));
        return payload;
    }

    /** Like {@link #toPayload} but carries the context, which is the actionable half. */
    private Map<String, Object> toInboxPayload(SupportTicket ticket) {
        Map<String, Object> payload = new LinkedHashMap<>(toPayload(ticket));
        payload.put("context", ticket.getContextJson());
        return payload;
    }

    private long countToday(Long userId) {
        LocalDate today = LocalDate.now();
        LocalDateTime start = LocalDateTime.of(today, LocalTime.MIN);
        LocalDateTime end = LocalDateTime.of(today, LocalTime.MAX);
        return supportTicketRepository.countByUserIdAndCreatedAtBetween(userId, start, end);
    }

    private SupportTicket.TicketType parseType(String raw) {
        if (raw == null || raw.isBlank()) {
            return SupportTicket.TicketType.REQUEST;
        }
        try {
            // Locale.ROOT avoids the Turkish-locale "i" -> "İ" uppercasing bug: on a
            // tr_TR JVM, "account_deletion".toUpperCase() (default locale) produces
            // "ACCOUNT_DELETİON", which never matches any enum constant and silently
            // falls back to REQUEST below.
            return SupportTicket.TicketType.valueOf(raw.trim().toUpperCase(Locale.ROOT));
        } catch (IllegalArgumentException ignored) {
            return SupportTicket.TicketType.REQUEST;
        }
    }

    private Map<String, Object> ticketPayload(SupportTicket ticket, long remainingToday) {
        Map<String, Object> payload = new LinkedHashMap<>(toPayload(ticket));
        payload.put("remainingToday", remainingToday);
        payload.put("dailyLimit", DAILY_LIMIT);
        return payload;
    }

    private Map<String, Object> toPayload(SupportTicket ticket) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("id", ticket.getId());
        payload.put("userId", ticket.getUserId());
        payload.put("type", ticket.getType().name());
        payload.put("title", ticket.getTitle());
        payload.put("message", ticket.getMessage());
        payload.put("locale", ticket.getLocale());
        payload.put("status", ticket.getStatus().name());
        payload.put("createdAt", ticket.getCreatedAt());
        payload.put("expiresAt", ticket.getExpiresAt());
        return payload;
    }
}
