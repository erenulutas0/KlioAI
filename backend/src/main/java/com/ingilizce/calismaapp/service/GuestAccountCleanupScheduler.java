package com.ingilizce.calismaapp.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;

/**
 * The nightly sweep of guest accounts nobody ever converted, at 03:30 Istanbul by default.
 * See {@link GuestAccountCleanupService} for what is deleted and in which order.
 */
@Service
public class GuestAccountCleanupScheduler {

    private static final Logger log = LoggerFactory.getLogger(GuestAccountCleanupScheduler.class);

    @Value("${app.guest.cleanup.enabled:true}")
    private boolean enabled = true;

    /**
     * How long an unconverted guest is kept after it was last used -- not after it was
     * created, which would have deleted accounts people were still using. Thirty days matches
     * the life of the refresh token that is a guest's only key: past that they cannot get back
     * into the account anyway, because there is no email, no password and no Google account on
     * it. Someone who tried the app, closed it and came back a fortnight later still finds
     * their words where they left them.
     */
    @Value("${app.guest.cleanup.retention-days:30}")
    private int retentionDays = 30;

    @Value("${app.guest.cleanup.batch-size:200}")
    private int batchSize = 200;

    /**
     * The ceiling on one night's work. A backlog is drained over several nights rather than in
     * one run that holds the database down for an hour; at the defaults this is 5000 accounts,
     * far more than a day produces.
     */
    @Value("${app.guest.cleanup.max-batches:25}")
    private int maxBatches = 25;

    private final GuestAccountCleanupService cleanupService;

    public GuestAccountCleanupScheduler(GuestAccountCleanupService cleanupService) {
        this.cleanupService = cleanupService;
    }

    @Scheduled(cron = "${app.guest.cleanup.cron:0 30 3 * * *}",
            zone = "${app.guest.cleanup.zone:Europe/Istanbul}")
    public void purgeExpiredGuests() {
        if (!enabled) {
            return;
        }
        try {
            run(LocalDateTime.now().minusDays(retentionDays));
        } catch (RuntimeException e) {
            // A failed sweep is tonight's rows still being there tomorrow night, nothing worse,
            // and it must not take the scheduler thread down with it.
            log.warn("Guest account cleanup failed: {}", e.toString());
        }
    }

    /** Returns how many guest accounts were deleted. */
    int run(LocalDateTime cutoff) {
        int deleted = 0;
        for (int batch = 0; batch < maxBatches; batch++) {
            int batchDeleted = cleanupService.purgeBatch(cutoff, batchSize);
            if (batchDeleted == 0) {
                break;
            }
            deleted += batchDeleted;
        }
        if (deleted > 0) {
            log.info("Guest account cleanup removed {} account(s) created before {}", deleted, cutoff);
        }
        return deleted;
    }
}
