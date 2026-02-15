package com.ingilizce.calismaapp.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.LocalDate;
import java.time.ZoneOffset;

/**
 * Pre-warms daily content generation once per day so users don't trigger expensive AI calls.
 */
@Component
public class DailyContentScheduler {

    private static final Logger log = LoggerFactory.getLogger(DailyContentScheduler.class);

    private final DailyWordsService dailyWordsService;
    private final DailyExamPackService dailyExamPackService;

    public DailyContentScheduler(DailyWordsService dailyWordsService,
                                 DailyExamPackService dailyExamPackService) {
        this.dailyWordsService = dailyWordsService;
        this.dailyExamPackService = dailyExamPackService;
    }

    /**
     * Run shortly after midnight UTC.
     */
    @Scheduled(cron = "0 5 0 * * *", zone = "UTC")
    public void generateDailyContentUtc() {
        LocalDate todayUtc = LocalDate.now(ZoneOffset.UTC);
        try {
            dailyWordsService.getDailyWords(todayUtc);
        } catch (Exception e) {
            log.warn("Daily words prewarm failed: {}", e.toString());
        }
        try {
            dailyExamPackService.getDailyExamPack(todayUtc, "yds");
        } catch (Exception e) {
            log.warn("Daily exam pack prewarm failed: {}", e.toString());
        }
    }
}

