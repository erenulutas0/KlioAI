package com.ingilizce.calismaapp.repository;

import com.ingilizce.calismaapp.entity.FeatureRating;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDateTime;
import java.util.List;

public interface FeatureRatingRepository extends JpaRepository<FeatureRating, Long> {

    long countByUserIdAndCreatedAtBetween(Long userId, LocalDateTime start, LocalDateTime end);

    /** Everything rated in a window, oldest first -- the order a digest reads in. */
    List<FeatureRating> findByCreatedAtBetweenOrderByCreatedAtAsc(LocalDateTime start, LocalDateTime end);
}
