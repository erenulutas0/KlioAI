package com.ingilizce.calismaapp.repository;

import com.ingilizce.calismaapp.entity.ReviewEvent;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.Instant;
import java.util.List;

/**
 * Read and append only. There is deliberately no update or delete path: the value of this
 * table is that it is a record of what actually happened.
 */
public interface ReviewEventRepository extends JpaRepository<ReviewEvent, Long> {

    /** A learner's history, newest first. The training input for a per-user scheduler. */
    List<ReviewEvent> findByUserIdOrderByCreatedAtDesc(Long userId);

    /** One word's history, oldest first, which is the order a forgetting curve is read in. */
    List<ReviewEvent> findByUserIdAndWordIdOrderByCreatedAtAsc(Long userId, Long wordId);

    long countByUserId(Long userId);

    /**
     * Grades in a window, used for retention reporting.
     *
     * <p>Ordered ascending because every consumer so far walks time forwards.
     */
    @Query("SELECT e FROM ReviewEvent e WHERE e.userId = :userId "
            + "AND e.createdAt >= :from AND e.createdAt < :to ORDER BY e.createdAt ASC")
    List<ReviewEvent> findInWindow(
            @Param("userId") Long userId,
            @Param("from") Instant from,
            @Param("to") Instant to);
}
