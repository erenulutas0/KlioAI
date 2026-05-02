package com.ingilizce.calismaapp.repository;

import com.ingilizce.calismaapp.entity.SupportTicket;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDateTime;
import java.util.List;

public interface SupportTicketRepository extends JpaRepository<SupportTicket, Long> {
    long countByUserIdAndCreatedAtBetween(Long userId, LocalDateTime start, LocalDateTime end);

    List<SupportTicket> findByUserIdOrderByCreatedAtDesc(Long userId);

    void deleteByExpiresAtBefore(LocalDateTime cutoff);
}
