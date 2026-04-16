package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.config.AiTokenQuotaProperties;
import com.ingilizce.calismaapp.entity.User;
import com.ingilizce.calismaapp.repository.UserRepository;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;

@Service
public class AiEntitlementService {

    public record Entitlement(
            AiPlanTier planTier,
            String planCode,
            boolean aiAccessEnabled,
            long dailyTokenLimit,
            boolean trialActive,
            int trialDaysRemaining) {
    }

    private final UserRepository userRepository;
    private final AiTokenQuotaProperties quotaProperties;

    public AiEntitlementService(UserRepository userRepository,
                                AiTokenQuotaProperties quotaProperties) {
        this.userRepository = userRepository;
        this.quotaProperties = quotaProperties;
    }

    public Entitlement resolve(Long userId) {
        if (userId == null) {
            return buildForTier(AiPlanTier.FREE, false, 0);
        }

        User user = userRepository.findById(userId).orElse(null);
        if (user == null) {
            return buildForTier(AiPlanTier.FREE, false, 0);
        }

        if (user.isSubscriptionActive()) {
            AiPlanTier tier = AiPlanTier.fromUserPlanCode(user.getAiPlanCode());
            if (tier == AiPlanTier.FREE || tier == AiPlanTier.FREE_TRIAL_7D) {
                // Legacy users may have active subscription but no explicit plan code yet.
                tier = AiPlanTier.PREMIUM;
            }
            return buildForTier(tier, false, 0);
        }

        if (!user.isTrialEligible()) {
            return buildForTier(AiPlanTier.FREE, false, 0);
        }

        int trialDurationDays = Math.max(0, quotaProperties.getTrialDurationDays());
        if (trialDurationDays > 0 && user.getCreatedAt() != null) {
            LocalDate createdDateUtc = user.getCreatedAt().toLocalDate();
            LocalDate todayUtc = LocalDate.now(ZoneOffset.UTC);
            long elapsedDays = Math.max(0L, ChronoUnit.DAYS.between(createdDateUtc, todayUtc));
            long remaining = trialDurationDays - elapsedDays;
            if (remaining > 0) {
                return buildForTier(AiPlanTier.FREE_TRIAL_7D, true, (int) Math.min(Integer.MAX_VALUE, remaining));
            }
        }

        return buildForTier(AiPlanTier.FREE, false, 0);
    }

    private Entitlement buildForTier(AiPlanTier tier, boolean trialActive, int trialDaysRemaining) {
        long limit = switch (tier) {
            case FREE -> Math.max(0L, quotaProperties.getFreeDailyTokenQuotaPerUser());
            case FREE_TRIAL_7D -> Math.max(0L, quotaProperties.getTrialDailyTokenQuotaPerUser());
            case PREMIUM -> Math.max(0L, quotaProperties.getPremiumDailyTokenQuotaPerUser());
            case PREMIUM_PLUS -> Math.max(0L, quotaProperties.getPremiumPlusDailyTokenQuotaPerUser());
        };
        return new Entitlement(
                tier,
                tier.name(),
                limit > 0,
                limit,
                trialActive,
                Math.max(0, trialDaysRemaining));
    }
}

