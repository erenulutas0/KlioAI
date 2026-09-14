package com.ingilizce.calismaapp.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;

/**
 * The daily feedback digest, at 21:00 Istanbul by default: the last 24 hours of ratings and
 * tickets, to Telegram. See FeedbackDigestService for what is in it.
 */
@Service
public class FeedbackDigestScheduler {

    private static final Logger log = LoggerFactory.getLogger(FeedbackDigestScheduler.class);

    @Value("${app.feedback.digest.enabled:true}")
    private boolean enabled = true;

    @Value("${app.feedback.digest.zone:Europe/Istanbul}")
    private String zone = "Europe/Istanbul";

    /** A one-line "nothing today" message, so silence can be told apart from a broken digest. */
    @Value("${app.feedback.digest.send-when-empty:true}")
    private boolean sendWhenEmpty = true;

    private final FeedbackDigestService digestService;
    private final TelegramNotifier telegram;

    public FeedbackDigestScheduler(FeedbackDigestService digestService, TelegramNotifier telegram) {
        this.digestService = digestService;
        this.telegram = telegram;
    }

    @Scheduled(cron = "${app.feedback.digest.cron:0 0 21 * * *}",
            zone = "${app.feedback.digest.zone:Europe/Istanbul}")
    public void sendDaily() {
        if (!enabled) {
            return;
        }
        try {
            // The window is on the JVM's clock, because that is the clock rows are stamped
            // with; only the date in the title is the reader's.
            LocalDateTime end = LocalDateTime.now();
            run(end.minusHours(24), end, LocalDate.now(ZoneId.of(zone)));
        } catch (RuntimeException e) {
            log.warn("Feedback digest failed: {}", e.getClass().getSimpleName());
        }
    }

    /** Returns true when a message was sent. */
    boolean run(LocalDateTime start, LocalDateTime end, LocalDate day) {
        FeedbackDigestService.Digest digest = digestService.build(start, end, day);
        if (digest.empty() && !sendWhenEmpty) {
            return false;
        }
        if (!telegram.isConfigured()) {
            // Still readable: docker logs is where a digest goes when there is nowhere else.
            log.info("Feedback digest (Telegram not configured):\n{}", digest.text());
            return false;
        }
        boolean sent = telegram.send(digest.text());
        log.info("Feedback digest sent={} empty={}", sent, digest.empty());
        return sent;
    }
}
