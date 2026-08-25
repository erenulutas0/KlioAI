package com.ingilizce.calismaapp.repository;

import com.ingilizce.calismaapp.entity.BookProgress;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface BookProgressRepository extends JpaRepository<BookProgress, Long> {

    Optional<BookProgress> findByUserIdAndBookId(Long userId, Long bookId);

    List<BookProgress> findByUserId(Long userId);
}
