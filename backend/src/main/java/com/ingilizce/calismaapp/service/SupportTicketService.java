package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.entity.SupportTicket;
import com.ingilizce.calismaapp.repository.SupportTicketRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@Service
public class SupportTicketService {
    private static final int DAILY_LIMIT = 3;

    private final SupportTicketRepository supportTicketRepository;

    public SupportTicketService(SupportTicketRepository supportTicketRepository) {
        this.supportTicketRepository = supportTicketRepository;
    }

    @Transactional
    public Map<String, Object> createTicket(Long userId, String type, String title, String message, String locale) {
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
        ticket.setExpiresAt(LocalDateTime.now().plusDays(7));

        SupportTicket saved = supportTicketRepository.save(ticket);
        return ticketPayload(saved, DAILY_LIMIT - (usedToday + 1));
    }

    @Transactional
    public Map<String, Object> listTickets(Long userId) {
        cleanupExpired();
        List<SupportTicket> tickets = supportTicketRepository.findByUserIdOrderByCreatedAtDesc(userId);
        long usedToday = countToday(userId);
        return Map.of(
                "tickets", tickets.stream().map(this::toPayload).toList(),
                "remainingToday", Math.max(0, DAILY_LIMIT - usedToday),
                "dailyLimit", DAILY_LIMIT
        );
    }

    @Transactional
    public void cleanupExpired() {
        supportTicketRepository.deleteByExpiresAtBefore(LocalDateTime.now());
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
            return SupportTicket.TicketType.valueOf(raw.trim().toUpperCase());
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
