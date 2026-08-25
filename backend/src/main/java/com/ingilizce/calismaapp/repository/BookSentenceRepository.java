package com.ingilizce.calismaapp.repository;

import com.ingilizce.calismaapp.entity.BookSentence;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface BookSentenceRepository extends JpaRepository<BookSentence, Long> {

    /**
     * A window of the book, which is how the reader loads it: a learner opens
     * at the sentence they stopped on, not at the beginning, and a novel is
     * several thousand sentences.
     */
    @Query("SELECT s FROM BookSentence s WHERE s.book.id = :bookId "
            + "AND s.sentenceIndex >= :from AND s.sentenceIndex < :to "
            + "ORDER BY s.sentenceIndex ASC")
    List<BookSentence> findWindow(@Param("bookId") Long bookId,
            @Param("from") int from,
            @Param("to") int to);

    long countByBookId(Long bookId);

    @Modifying
    @Query("DELETE FROM BookSentence s WHERE s.book.id = :bookId")
    void deleteByBookId(@Param("bookId") Long bookId);

    /**
     * How much of a book is still waiting, without loading any of it.
     *
     * <p>Separate from {@link #findUntranslated} because the two questions have
     * very different costs: asking how many are left should not drag several
     * thousand sentences into memory to count them.
     */
    @Query("SELECT COUNT(s) FROM BookSentence s WHERE s.book.id = :bookId "
            + "AND s.translation IS NULL")
    long countUntranslated(@Param("bookId") Long bookId);

    /** Sentences still waiting for a translation, oldest position first. */
    @Query("SELECT s FROM BookSentence s WHERE s.book.id = :bookId "
            + "AND s.translation IS NULL ORDER BY s.sentenceIndex ASC")
    List<BookSentence> findUntranslated(@Param("bookId") Long bookId);
}
