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

    // Legacy SRS
    List<Word> findByNextReviewDateLessThanEqual(LocalDate date);

    List<Word> findByReviewCountGreaterThan(int count);
    List<Word> findByUserIdAndReviewCountGreaterThan(Long userId, int count);
}
