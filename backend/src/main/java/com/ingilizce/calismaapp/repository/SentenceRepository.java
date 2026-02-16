package com.ingilizce.calismaapp.repository;

import com.ingilizce.calismaapp.entity.Sentence;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface SentenceRepository extends JpaRepository<Sentence, Long> {

    @Query("SELECT s FROM Sentence s WHERE s.word.id = :wordId")
    List<Sentence> findByWordId(@Param("wordId") Long wordId);

    @Query("SELECT s FROM Sentence s WHERE s.word.id IN :wordIds ORDER BY s.id ASC")
    List<Sentence> findByWordIdIn(@Param("wordIds") List<Long> wordIds);

    Optional<Sentence> findByIdAndWordUserId(Long id, Long userId);

    @Query("SELECT s FROM Sentence s WHERE s.word.id = :wordId AND s.sentence = :sentence AND (s.translation = :translation OR (s.translation IS NULL AND :translation IS NULL))")
    List<Sentence> findByWordIdAndSentenceAndTranslation(@Param("wordId") Long wordId,
                                                         @Param("sentence") String sentence,
                                                         @Param("translation") String translation);

    @Modifying
    @Query("DELETE FROM Sentence s WHERE s.word.id = :wordId")
    void deleteByWordId(@Param("wordId") Long wordId);

    // Global stats (Admin/Legacy)
    long countByDifficulty(String difficulty);

    // User Scoped Stats
    @Query("SELECT COUNT(s) FROM Sentence s WHERE s.difficulty = :difficulty AND s.word.userId = :userId")
    long countByDifficultyAndUserId(@Param("difficulty") String difficulty, @Param("userId") Long userId);

    @Query("SELECT COUNT(s) FROM Sentence s WHERE s.word.userId = :userId")
    long countByUserId(@Param("userId") Long userId);

    @Query("SELECT s FROM Sentence s JOIN FETCH s.word w")
    List<Sentence> findAllWithWord();

    @Query("SELECT s FROM Sentence s JOIN FETCH s.word w WHERE w.userId = :userId")
    List<Sentence> findAllWithWordByUserId(@Param("userId") Long userId);

    @Query(value = "SELECT s FROM Sentence s JOIN FETCH s.word w WHERE w.userId = :userId ORDER BY s.id DESC",
            countQuery = "SELECT COUNT(s) FROM Sentence s WHERE s.word.userId = :userId")
    Page<Sentence> findAllWithWordByUserId(@Param("userId") Long userId, Pageable pageable);
}
