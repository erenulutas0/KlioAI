package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.entity.SupportTicket;
import com.ingilizce.calismaapp.repository.SupportTicketRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

/**
 * Feedback is the only signal the instrumentation cannot produce.
 *
 * <p>For three months this app served hardcoded template sentences as if a model had written
 * them, and every one of those calls was recorded as a success. A dashboard can say the
 * request returned 200; only a person can say the sentence was nonsense.
 *
 * <p>That signal used to be on a seven-day fuse: {@code cleanupExpired} hard-deleted tickets
 * on every create and every read, so a report could be gone before anyone looked at it.
 */
class SupportTicketRetentionTest {

    @InjectMocks
    private SupportTicketService supportTicketService;

    @Mock
    private SupportTicketRepository supportTicketRepository;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
        when(supportTicketRepository.save(any(SupportTicket.class)))
                .thenAnswer(inv -> inv.getArgument(0));
        when(supportTicketRepository.findByUserIdOrderByCreatedAtDesc(anyLong()))
                .thenReturn(List.of());
    }

    @Test
    void creatingATicketNeverDeletesAnything() {
        supportTicketService.createTicket(1L, "BUG", "title", "message", "tr");

        verify(supportTicketRepository, never()).deleteByExpiresAtBefore(any());
    }

    @Test
    void listingTicketsNeverDeletesAnything() {
        supportTicketService.listTickets(1L);

        verify(supportTicketRepository, never()).deleteByExpiresAtBefore(any());
    }

    @Test
    void anExpiredTicketIsHiddenFromTheSenderButStillExists() {
        // The sender keeps a short, tidy list; the report itself is retained for whoever has
        // to act on it. Those are different requirements and were conflated.
        SupportTicket old = new SupportTicket();
        old.setUserId(1L);
        old.setType(SupportTicket.TicketType.CONTENT_REPORT);
        old.setTitle("old report");
        old.setMessage("the sentence made no sense");
        old.setExpiresAt(LocalDateTime.now().minusDays(1));

        SupportTicket fresh = new SupportTicket();
        fresh.setUserId(1L);
        fresh.setType(SupportTicket.TicketType.CONTENT_REPORT);
        fresh.setTitle("new report");
        fresh.setMessage("still wrong");
        fresh.setExpiresAt(LocalDateTime.now().plusDays(6));

        when(supportTicketRepository.findByUserIdOrderByCreatedAtDesc(1L))
                .thenReturn(List.of(fresh, old));

        var payload = supportTicketService.listTickets(1L);

        @SuppressWarnings("unchecked")
        List<Object> listed = (List<Object>) payload.get("tickets");
        assertEquals(1, listed.size(), "only the unexpired ticket is shown to its sender");
        verify(supportTicketRepository, never()).deleteByExpiresAtBefore(any());
    }

    @Test
    void theInboxShowsExpiredReportsThatTheSendersOwnListHides() {
        // The two views answer different questions. "What did I send lately?" should stay
        // short. "What have people told us is broken?" must not quietly drop older reports —
        // a bad generated sentence is not less wrong eight days after someone flagged it.
        SupportTicket old = new SupportTicket();
        old.setUserId(1L);
        old.setType(SupportTicket.TicketType.CONTENT_REPORT);
        old.setTitle("old report");
        old.setMessage("the sentence made no sense");
        old.setExpiresAt(LocalDateTime.now().minusDays(1));

        when(supportTicketRepository.findByCreatedAtAfterOrderByCreatedAtDesc(any(), any()))
                .thenReturn(List.of(old));

        var payload = supportTicketService.inbox(null, 30, 100);

        @SuppressWarnings("unchecked")
        List<Object> listed = (List<Object>) payload.get("tickets");
        assertEquals(1, listed.size(), "an expired report is still in the inbox");
        assertEquals(1, payload.get("count"));
        assertEquals(Map.of("CONTENT_REPORT", 1L), payload.get("countByType"));
    }

    @Test
    void theInboxCarriesTheContextBecauseThatIsTheActionableHalf() {
        SupportTicket reported = new SupportTicket();
        reported.setUserId(1L);
        reported.setType(SupportTicket.TicketType.CONTENT_REPORT);
        reported.setTitle("Content report: sentence on translation_practice");
        reported.setMessage("bu cümle saçma");
        reported.setContextJson("{\"content\":\"Maya noticed evaluate during the trip.\"}");

        when(supportTicketRepository.findByTypeAndCreatedAtAfterOrderByCreatedAtDesc(
                eq(SupportTicket.TicketType.CONTENT_REPORT), any(), any()))
                .thenReturn(List.of(reported));

        var payload = supportTicketService.inbox("CONTENT_REPORT", 30, 100);

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> listed = (List<Map<String, Object>>) payload.get("tickets");
        assertEquals("{\"content\":\"Maya noticed evaluate during the trip.\"}",
                listed.get(0).get("context"),
                "without the offending text the report cannot be acted on");
    }

    @Test
    void theCollectedContextIsStoredWithTheReport() {
        // A report without context cannot be reproduced, and a tester should not have to
        // write a bug report to be useful.
        String context = "{\"surface\":\"translation_practice\",\"content\":"
                + "\"Maya noticed evaluate during the trip.\",\"appVersion\":\"1.1.9+417\"}";

        supportTicketService.createTicket(
                1L, "CONTENT_REPORT", "Content report", "makes no sense", "tr", context);

        ArgumentCaptor<SupportTicket> captor = ArgumentCaptor.forClass(SupportTicket.class);
        verify(supportTicketRepository).save(captor.capture());
        assertEquals(context, captor.getValue().getContextJson());
        assertEquals(SupportTicket.TicketType.CONTENT_REPORT, captor.getValue().getType());
    }

    @Test
    void anOversizedContextIsTrimmedRatherThanLosingTheReport() {
        String huge = "x".repeat(9000);

        supportTicketService.createTicket(1L, "BUG", "t", "m", "tr", huge);

        ArgumentCaptor<SupportTicket> captor = ArgumentCaptor.forClass(SupportTicket.class);
        verify(supportTicketRepository).save(captor.capture());
        assertEquals(4000, captor.getValue().getContextJson().length(),
                "a long context is truncated; refusing the whole report would lose it");
    }

    @Test
    void aReportWithoutContextIsStillAccepted() {
        supportTicketService.createTicket(1L, "BUG", "t", "m", "tr", null);

        ArgumentCaptor<SupportTicket> captor = ArgumentCaptor.forClass(SupportTicket.class);
        verify(supportTicketRepository).save(captor.capture());
        assertNull(captor.getValue().getContextJson());
    }
}
