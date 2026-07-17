package com.ingilizce.calismaapp.repository;

import com.ingilizce.calismaapp.entity.DailyContent;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

public interface DailyContentRepository extends JpaRepository<DailyContent, Long> {
    Optional<DailyContent> findByContentDateAndContentType(LocalDate contentDate, String contentType);

    List<DailyContent> findByContentTypeAndContentDateBetweenOrderByContentDateDesc(
            String contentType,
            LocalDate startDate,
            LocalDate endDate);
}
