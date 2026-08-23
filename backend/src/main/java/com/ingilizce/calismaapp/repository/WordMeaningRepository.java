package com.ingilizce.calismaapp.repository;

import com.ingilizce.calismaapp.entity.WordMeaning;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface WordMeaningRepository extends JpaRepository<WordMeaning, Long> {

    @Query("SELECT m FROM WordMeaning m WHERE m.word.id = :wordId ORDER BY m.position ASC, m.id ASC")
    List<WordMeaning> findByWordIdOrderByPosition(@Param("wordId") Long wordId);

    @Query("SELECT m FROM WordMeaning m WHERE m.word.id IN :wordIds ORDER BY m.word.id ASC, m.position ASC, m.id ASC")
    List<WordMeaning> findByWordIdIn(@Param("wordIds") List<Long> wordIds);

    @Query("SELECT m FROM WordMeaning m WHERE m.id = :id AND m.word.id = :wordId")
    Optional<WordMeaning> findByIdAndWordId(@Param("id") Long id, @Param("wordId") Long wordId);

    /** Ownership check in one hop: the meaning, its word and the caller must line up. */
    @Query("SELECT m FROM WordMeaning m WHERE m.id = :id AND m.word.id = :wordId AND m.word.userId = :userId")
    Optional<WordMeaning> findByIdAndWordIdAndUserId(@Param("id") Long id,
                                                     @Param("wordId") Long wordId,
                                                     @Param("userId") Long userId);

    @Query("SELECT COUNT(m) FROM WordMeaning m WHERE m.word.id = :wordId")
    long countByWordId(@Param("wordId") Long wordId);

    @Query("SELECT COALESCE(MAX(m.position), -1) FROM WordMeaning m WHERE m.word.id = :wordId")
    int findMaxPositionByWordId(@Param("wordId") Long wordId);
}
