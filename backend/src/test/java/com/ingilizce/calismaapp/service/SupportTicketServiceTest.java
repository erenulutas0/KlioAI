package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.entity.SupportTicket;
import com.ingilizce.calismaapp.repository.SupportTicketRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class SupportTicketServiceTest {

    @Mock
    private SupportTicketRepository supportTicketRepository;

    private SupportTicketService service;

    @BeforeEach
    void setUp() {
        service = new SupportTicketService(supportTicketRepository);
    }

    @Test
    void createTicket_shouldTrimInputsParseTypeAndReturnRemainingLimit() {
        when(supportTicketRepository.countByUserIdAndCreatedAtBetween(eq(42L), any(), any()))
                .thenReturn(1L);
        when(supportTicketRepository.save(any(SupportTicket.class)))
                .thenAnswer(invocation -> {
                    SupportTicket ticket = invocation.getArgument(0);
                    ReflectionTestUtils.setField(ticket, "id", 11L);
                    ReflectionTestUtils.setField(ticket, "createdAt", LocalDateTime.of(2026, 7, 5, 10, 0));
                    return ticket;
                });

        Map<String, Object> result = service.createTicket(
                42L,
                " bug ",
                "  Button problem  ",
                "  The upgrade button does not respond.  ",
                " tr ");

        assertEquals(11L, result.get("id"));
        assertEquals(42L, result.get("userId"));
        assertEquals("BUG", result.get("type"));
        assertEquals("Button problem", result.get("title"));
        assertEquals("The upgrade button does not respond.", result.get("message"));
        assertEquals("tr", result.get("locale"));
        assertEquals("OPEN", result.get("status"));
        assertEquals(1L, result.get("remainingToday"));
        assertEquals(3, result.get("dailyLimit"));

        ArgumentCaptor<SupportTicket> captor = ArgumentCaptor.forClass(SupportTicket.class);
        verify(supportTicketRepository).save(captor.capture());
        assertEquals(SupportTicket.TicketType.BUG, captor.getValue().getType());
        assertTrue(captor.getValue().getExpiresAt().isAfter(LocalDateTime.now().plusDays(6)));
    }

    @Test
    void createTicket_shouldAcceptAccountDeletionType() {
        when(supportTicketRepository.countByUserIdAndCreatedAtBetween(eq(42L), any(), any()))
                .thenReturn(0L);
        when(supportTicketRepository.save(any(SupportTicket.class)))
                .thenAnswer(invocation -> {
                    SupportTicket ticket = invocation.getArgument(0);
                    ReflectionTestUtils.setField(ticket, "id", 13L);
                    ReflectionTestUtils.setField(ticket, "createdAt", LocalDateTime.of(2026, 7, 8, 9, 0));
                    return ticket;
                });

        Map<String, Object> result = service.createTicket(
                42L,
                "account_deletion",
                "Delete my account",
                "Please delete my account and associated data.",
                "en");

        assertEquals("ACCOUNT_DELETION", result.get("type"));

        ArgumentCaptor<SupportTicket> captor = ArgumentCaptor.forClass(SupportTicket.class);
        verify(supportTicketRepository).save(captor.capture());
        assertEquals(SupportTicket.TicketType.ACCOUNT_DELETION, captor.getValue().getType());
    }

    @Test
    void createTicket_shouldDefaultBlankOrUnknownTypeToRequest() {
        when(supportTicketRepository.countByUserIdAndCreatedAtBetween(eq(7L), any(), any()))
                .thenReturn(0L);
        when(supportTicketRepository.save(any(SupportTicket.class)))
                .thenAnswer(invocation -> {
                    SupportTicket ticket = invocation.getArgument(0);
                    ReflectionTestUtils.setField(ticket, "id", 12L);
                    ReflectionTestUtils.setField(ticket, "createdAt", LocalDateTime.of(2026, 7, 5, 11, 0));
                    return ticket;
                });

        Map<String, Object> result = service.createTicket(7L, "unknown", "Title", "Message", null);

        assertEquals("REQUEST", result.get("type"));
        assertEquals(2L, result.get("remainingToday"));
    }

    @Test
    void createTicket_shouldBlockWhenDailyLimitReached() {
        when(supportTicketRepository.countByUserIdAndCreatedAtBetween(eq(42L), any(), any()))
                .thenReturn(3L);

        IllegalStateException ex = assertThrows(IllegalStateException.class,
                () -> service.createTicket(42L, "request", "Title", "Message", "en"));

        assertEquals("DAILY_LIMIT_REACHED", ex.getMessage());
    }

    @Test
    void listTickets_shouldCleanupExpiredAndReturnRemainingLimit() {
        SupportTicket first = ticket(21L, 42L, SupportTicket.TicketType.REQUEST, "First", "Message one");
        SupportTicket second = ticket(22L, 42L, SupportTicket.TicketType.COMPLAINT, "Second", "Message two");
        when(supportTicketRepository.findByUserIdOrderByCreatedAtDesc(42L))
                .thenReturn(List.of(first, second));
        when(supportTicketRepository.countByUserIdAndCreatedAtBetween(eq(42L), any(), any()))
                .thenReturn(2L);

        Map<String, Object> result = service.listTickets(42L);

        assertEquals(1L, result.get("remainingToday"));
        assertEquals(3, result.get("dailyLimit"));
        List<?> tickets = (List<?>) result.get("tickets");
        assertEquals(2, tickets.size());
        assertEquals("REQUEST", ((Map<?, ?>) tickets.get(0)).get("type"));
        assertEquals("COMPLAINT", ((Map<?, ?>) tickets.get(1)).get("type"));
        verify(supportTicketRepository).deleteByExpiresAtBefore(any(LocalDateTime.class));
    }

    private SupportTicket ticket(Long id,
                                 Long userId,
                                 SupportTicket.TicketType type,
                                 String title,
                                 String message) {
        SupportTicket ticket = new SupportTicket();
        ReflectionTestUtils.setField(ticket, "id", id);
        ReflectionTestUtils.setField(ticket, "createdAt", LocalDateTime.of(2026, 7, 5, 12, 0));
        ticket.setUserId(userId);
        ticket.setType(type);
        ticket.setTitle(title);
        ticket.setMessage(message);
        ticket.setLocale("en");
        ticket.setStatus(SupportTicket.TicketStatus.OPEN);
        ticket.setExpiresAt(LocalDateTime.of(2026, 7, 12, 12, 0));
        return ticket;
    }
}
