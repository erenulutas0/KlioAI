package com.ingilizce.calismaapp.repository;

import com.ingilizce.calismaapp.entity.SupportTicket;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDateTime;
import java.util.List;

public interface SupportTicketRepository extends JpaRepository<SupportTicket, Long> {
    long countByUserIdAndCreatedAtBetween(Long userId, LocalDateTime start, LocalDateTime end);

    List<SupportTicket> findByUserIdOrderByCreatedAtDesc(Long userId);

    /**
     * The inbox side: everything anyone wrote, newest first, regardless of expiry.
     *
     * <p>{@link #findByUserIdOrderByCreatedAtDesc} is what a sender sees about themselves.
     * This is what the person who has to act on the reports sees, and it deliberately does
     * not filter on {@code expiresAt} — a report is not less true a week after it was
     * written.
     */
    List<SupportTicket> findByCreatedAtAfterOrderByCreatedAtDesc(LocalDateTime since, Pageable pageable);

    List<SupportTicket> findByTypeAndCreatedAtAfterOrderByCreatedAtDesc(
            SupportTicket.TicketType type, LocalDateTime since, Pageable pageable);

    /**
     * Never called. Kept so the tests that assert it is never called can name it — the
     * seven-day hard delete this used to power is the thing those tests exist to prevent
     * coming back.
     */
    void deleteByExpiresAtBefore(LocalDateTime cutoff);
}
