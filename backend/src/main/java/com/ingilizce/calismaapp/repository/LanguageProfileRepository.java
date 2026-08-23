package com.ingilizce.calismaapp.repository;

import com.ingilizce.calismaapp.entity.LanguageProfile;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface LanguageProfileRepository extends JpaRepository<LanguageProfile, Long> {

    List<LanguageProfile> findByUserId(Long userId);

    List<LanguageProfile> findByUserIdOrderByCreatedAtAscIdAsc(Long userId);

    /**
     * The one active profile. The entity field is {@code active} (column {@code is_active}),
     * so this is spelled out as a query rather than derived from the method name.
     */
    @Query("SELECT p FROM LanguageProfile p WHERE p.userId = :userId AND p.active = true")
    Optional<LanguageProfile> findByUserIdAndIsActiveTrue(@Param("userId") Long userId);

    Optional<LanguageProfile> findByUserIdAndTargetLanguage(Long userId, String targetLanguage);

    Optional<LanguageProfile> findByIdAndUserId(Long id, Long userId);

    boolean existsByUserIdAndTargetLanguage(Long userId, String targetLanguage);

    /**
     * Clears the active flag on every profile of a user. Call before setting the new one so
     * "exactly one active per user" holds at the end of the transaction.
     */
    @Modifying
    @Query("UPDATE LanguageProfile p SET p.active = false WHERE p.userId = :userId AND p.active = true")
    int deactivateAllByUserId(@Param("userId") Long userId);
}
