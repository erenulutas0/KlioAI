package com.ingilizce.calismaapp.repository;

import com.ingilizce.calismaapp.entity.Book;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface BookRepository extends JpaRepository<Book, Long> {

    Optional<Book> findBySlug(String slug);

    /**
     * The shelf for one language. Ordered by level then title so a learner sees
     * the easiest books first rather than the most recently imported.
     */
    List<Book> findByLanguageOrderByLevelAscTitleAsc(String language);
}
