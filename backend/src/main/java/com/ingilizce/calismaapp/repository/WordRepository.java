package com.ingilizce.calismaapp.repository;

import com.ingilizce.calismaapp.entity.Word;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

@Repository
public interface WordRepository extends JpaRepository<Word, Long> {

    // Legacy support (Admin/Global) or migration
    List<Word> findByLearnedDate(LocalDate date);

    // User Scoped Methods
    List<Word> findByUserId(Long userId);
    Page<Word> findByUserId(Long userId, Pageable pageable);
    long countByUserId(Long userId);

    List<Word> findByUserIdAndLearnedDate(Long userId, LocalDate date);

    Optional<Word> findByIdAndUserId(Long id, Long userId);

    @Query("SELECT DISTINCT w FROM Word w LEFT JOIN FETCH w.sentences WHERE w.id = :id AND w.userId = :userId")
    Optional<Word> findByIdAndUserIdWithSentences(@Param("id") Long id, @Param("userId") Long userId);

    Optional<Word> findByUserIdAndEnglishWord(Long userId, String englishWord);

    @Query("SELECT w FROM Word w WHERE w.userId = :userId AND w.learnedDate BETWEEN :startDate AND :endDate ORDER BY w.learnedDate DESC")
    List<Word> findByUserIdAndDateRange(@Param("userId") Long userId, @Param("startDate") LocalDate startDate,
            @Param("endDate") LocalDate endDate);

    // Kept for backward compatibility but should be replaced
    @Query("SELECT w FROM Word w WHERE w.learnedDate BETWEEN :startDate AND :endDate ORDER BY w.learnedDate DESC")
    List<Word> findByDateRange(@Param("startDate") LocalDate startDate, @Param("endDate") LocalDate endDate);

    @Query("SELECT DISTINCT w.learnedDate FROM Word w WHERE w.userId = :userId ORDER BY w.learnedDate DESC")
    List<LocalDate> findDistinctDatesByUserId(@Param("userId") Long userId);

    @Query("SELECT DISTINCT w.learnedDate FROM Word w ORDER BY w.learnedDate DESC")
    List<LocalDate> findAllDistinctDates();

    // SRS Queries - User Scoped
    List<Word> findByUserIdAndNextReviewDateLessThanEqual(Long userId, LocalDate date);

    /**
     * How many words are due, without loading them.
     *
     * <p>Used by the daily reminder, which needs the number to put in the message and
     * nothing else. Fetching every due row per user per night to call {@code size()} on it
     * would be a lot of object graph for one integer.
     */
    long countByUserIdAndNextReviewDateLessThanEqual(Long userId, LocalDate date);

    // Legacy SRS
    List<Word> findByNextReviewDateLessThanEqual(LocalDate date);

    List<Word> findByReviewCountGreaterThan(int count);
    List<Word> findByUserIdAndReviewCountGreaterThan(Long userId, int count);

    // Profile Scoped Methods (V028). The user-scoped methods above stay: other code calls
    // them, and a word's profile is always owned by the same user, so both keys are required
    // here rather than trusting the profile id on its own. Spelled out as queries because
    // Word exposes a getLanguageProfileId() JSON getter that would confuse derivation.

    @Query("SELECT w FROM Word w WHERE w.userId = :userId AND w.languageProfile.id = :profileId")
    List<Word> findByUserIdAndLanguageProfileId(@Param("userId") Long userId, @Param("profileId") Long profileId);

    @Query(value = "SELECT w FROM Word w WHERE w.userId = :userId AND w.languageProfile.id = :profileId",
            countQuery = "SELECT COUNT(w) FROM Word w WHERE w.userId = :userId AND w.languageProfile.id = :profileId")
    Page<Word> findByUserIdAndLanguageProfileId(@Param("userId") Long userId, @Param("profileId") Long profileId,
            Pageable pageable);

    @Query("SELECT COUNT(w) FROM Word w WHERE w.userId = :userId AND w.languageProfile.id = :profileId")
    long countByUserIdAndLanguageProfileId(@Param("userId") Long userId, @Param("profileId") Long profileId);

    @Query("SELECT w FROM Word w WHERE w.userId = :userId AND w.languageProfile.id = :profileId AND w.learnedDate = :date")
    List<Word> findByUserIdAndLanguageProfileIdAndLearnedDate(@Param("userId") Long userId,
            @Param("profileId") Long profileId, @Param("date") LocalDate date);

    @Query("SELECT w FROM Word w WHERE w.userId = :userId AND w.languageProfile.id = :profileId AND w.learnedDate BETWEEN :startDate AND :endDate ORDER BY w.learnedDate DESC")
    List<Word> findByUserIdAndLanguageProfileIdAndDateRange(@Param("userId") Long userId,
            @Param("profileId") Long profileId, @Param("startDate") LocalDate startDate,
            @Param("endDate") LocalDate endDate);

    @Query("SELECT DISTINCT w.learnedDate FROM Word w WHERE w.userId = :userId AND w.languageProfile.id = :profileId ORDER BY w.learnedDate DESC")
    List<LocalDate> findDistinctDatesByUserIdAndLanguageProfileId(@Param("userId") Long userId,
            @Param("profileId") Long profileId);

    @Query("SELECT w FROM Word w WHERE w.userId = :userId AND w.languageProfile.id = :profileId AND w.nextReviewDate <= :date")
    List<Word> findByUserIdAndLanguageProfileIdAndNextReviewDateLessThanEqual(@Param("userId") Long userId,
            @Param("profileId") Long profileId, @Param("date") LocalDate date);

    @Query("SELECT COUNT(w) FROM Word w WHERE w.userId = :userId AND w.languageProfile.id = :profileId AND w.nextReviewDate <= :date")
    long countByUserIdAndLanguageProfileIdAndNextReviewDateLessThanEqual(@Param("userId") Long userId,
            @Param("profileId") Long profileId, @Param("date") LocalDate date);

    @Query("SELECT w FROM Word w WHERE w.userId = :userId AND w.languageProfile.id = :profileId AND w.reviewCount > :count")
    List<Word> findByUserIdAndLanguageProfileIdAndReviewCountGreaterThan(@Param("userId") Long userId,
            @Param("profileId") Long profileId, @Param("count") int count);

    /** Words of a user that no profile claims; should be empty after the V028 backfill. */
    @Query("SELECT w FROM Word w WHERE w.userId = :userId AND w.languageProfile IS NULL")
    List<Word> findByUserIdAndLanguageProfileIsNull(@Param("userId") Long userId);
}
