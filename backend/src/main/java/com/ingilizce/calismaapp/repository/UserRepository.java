package com.ingilizce.calismaapp.repository;

import com.ingilizce.calismaapp.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.Optional;

@Repository
public interface UserRepository extends JpaRepository<User, Long> {
    Optional<User> findByEmail(String email);

    boolean existsByEmail(String email);

    /**
     * Stamps last_seen_at without loading the user or touching anything else on the row.
     *
     * <p>Its own transaction, because the only caller is {@link
     * com.ingilizce.calismaapp.service.LastSeenService} on the way into somebody's request:
     * a failure here has to roll back this one statement and nothing of theirs.
     */
    @Modifying
    @Transactional
    @Query("UPDATE User u SET u.lastSeenAt = :seenAt WHERE u.id = :userId")
    int markLastSeen(@Param("userId") Long userId, @Param("seenAt") LocalDateTime seenAt);
}
