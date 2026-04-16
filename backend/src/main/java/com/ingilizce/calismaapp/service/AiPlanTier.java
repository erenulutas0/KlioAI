package com.ingilizce.calismaapp.service;

import java.util.Locale;

public enum AiPlanTier {
    FREE,
    FREE_TRIAL_7D,
    PREMIUM,
    PREMIUM_PLUS;

    public static AiPlanTier fromUserPlanCode(String raw) {
        if (raw == null || raw.isBlank()) {
            return FREE;
        }
        String normalized = raw.trim().toUpperCase(Locale.ROOT);
        return switch (normalized) {
            case "PREMIUM_PLUS", "PREMIUMPLUS", "PRO_PLUS", "PROPLUS" -> PREMIUM_PLUS;
            case "PREMIUM", "PRO", "PRO_MONTHLY", "PRO_ANNUAL" -> PREMIUM;
            case "FREE_TRIAL_7D", "TRIAL", "TRIAL_7D" -> FREE_TRIAL_7D;
            default -> FREE;
        };
    }

    public static AiPlanTier fromSubscriptionPlanName(String raw) {
        if (raw == null || raw.isBlank()) {
            return FREE;
        }
        String normalized = raw.trim().toUpperCase(Locale.ROOT);
        if (normalized.contains("PLUS")) {
            return PREMIUM_PLUS;
        }
        if (normalized.contains("PREMIUM") || normalized.contains("PRO")) {
            return PREMIUM;
        }
        return FREE;
    }
}
