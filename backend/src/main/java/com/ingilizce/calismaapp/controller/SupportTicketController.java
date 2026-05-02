package com.ingilizce.calismaapp.controller;

import com.ingilizce.calismaapp.service.SupportTicketService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api/support/tickets")
public class SupportTicketController {

    private final SupportTicketService supportTicketService;

    public SupportTicketController(SupportTicketService supportTicketService) {
        this.supportTicketService = supportTicketService;
    }

    @GetMapping
    public ResponseEntity<Map<String, Object>> listTickets(@RequestHeader("X-User-Id") Long userId) {
        return ResponseEntity.ok(supportTicketService.listTickets(userId));
    }

    @PostMapping
    public ResponseEntity<Map<String, Object>> createTicket(
            @RequestHeader("X-User-Id") Long userId,
            @RequestBody Map<String, String> payload) {
        String title = safe(payload.get("title"));
        String message = safe(payload.get("message"));
        if (title.isBlank() || message.isBlank()) {
            return ResponseEntity.badRequest().body(Map.of(
                    "error", "title and message are required"
            ));
        }

        try {
            Map<String, Object> created = supportTicketService.createTicket(
                    userId,
                    payload.get("type"),
                    title,
                    message,
                    payload.get("locale"));
            return ResponseEntity.status(HttpStatus.CREATED).body(created);
        } catch (IllegalStateException ex) {
            if ("DAILY_LIMIT_REACHED".equals(ex.getMessage())) {
                return ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS).body(Map.of(
                        "error", "daily ticket limit reached",
                        "dailyLimit", 3
                ));
            }
            throw ex;
        }
    }

    private String safe(String value) {
        return value == null ? "" : value.trim();
    }
}
