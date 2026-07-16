package com.ingilizce.calismaapp.service;

import org.junit.jupiter.api.Test;

import java.util.Locale;

import static org.junit.jupiter.api.Assertions.assertEquals;

class AiPlanTierTest {

    @Test
    void fromUserPlanCode_ShouldMapAllKnownCodes() {
        assertEquals(AiPlanTier.PREMIUM_PLUS, AiPlanTier.fromUserPlanCode("PREMIUM_PLUS"));
        assertEquals(AiPlanTier.PREMIUM_PLUS, AiPlanTier.fromUserPlanCode("premiumplus"));
        assertEquals(AiPlanTier.PREMIUM_PLUS, AiPlanTier.fromUserPlanCode("PRO_PLUS"));
        assertEquals(AiPlanTier.PREMIUM, AiPlanTier.fromUserPlanCode("PREMIUM"));
        assertEquals(AiPlanTier.PREMIUM, AiPlanTier.fromUserPlanCode("pro"));
        assertEquals(AiPlanTier.PREMIUM, AiPlanTier.fromUserPlanCode("PRO_MONTHLY"));
        assertEquals(AiPlanTier.PREMIUM, AiPlanTier.fromUserPlanCode("PRO_ANNUAL"));
        assertEquals(AiPlanTier.FREE_TRIAL_7D, AiPlanTier.fromUserPlanCode("FREE_TRIAL_7D"));
        assertEquals(AiPlanTier.FREE_TRIAL_7D, AiPlanTier.fromUserPlanCode("trial"));
        assertEquals(AiPlanTier.FREE, AiPlanTier.fromUserPlanCode(null));
        assertEquals(AiPlanTier.FREE, AiPlanTier.fromUserPlanCode("  "));
        assertEquals(AiPlanTier.FREE, AiPlanTier.fromUserPlanCode("something-unknown"));
    }

    @Test
    void fromUserPlanCode_ShouldRoundTripEveryEnumName() {
        // The verify/reconcile paths persist tier.name() into User.aiPlanCode;
        // every enum name must map back to itself or paying users lose tier.
        for (AiPlanTier tier : AiPlanTier.values()) {
            assertEquals(tier, AiPlanTier.fromUserPlanCode(tier.name()),
                    "Enum name must round-trip: " + tier.name());
        }
    }

    @Test
    void fromSubscriptionPlanName_ShouldMapKnownPlanFamilies() {
        assertEquals(AiPlanTier.PREMIUM_PLUS, AiPlanTier.fromSubscriptionPlanName("PREMIUM_PLUS"));
        assertEquals(AiPlanTier.PREMIUM_PLUS, AiPlanTier.fromSubscriptionPlanName("Pro Plus Annual"));
        assertEquals(AiPlanTier.PREMIUM, AiPlanTier.fromSubscriptionPlanName("PREMIUM"));
        assertEquals(AiPlanTier.PREMIUM, AiPlanTier.fromSubscriptionPlanName("PRO_MONTHLY"));
        assertEquals(AiPlanTier.PREMIUM, AiPlanTier.fromSubscriptionPlanName("PRO_ANNUAL"));
        assertEquals(AiPlanTier.FREE, AiPlanTier.fromSubscriptionPlanName(null));
        assertEquals(AiPlanTier.FREE, AiPlanTier.fromSubscriptionPlanName("Starter"));
    }

    @Test
    void mappings_ShouldSurviveTurkishDefaultLocale() {
        // Same dotted/dotless-I bug class fixed across the codebase: "trial"
        // uppercased under tr-TR becomes "TRİAL" without Locale.ROOT.
        Locale original = Locale.getDefault();
        try {
            Locale.setDefault(new Locale("tr", "TR"));
            assertEquals(AiPlanTier.FREE_TRIAL_7D, AiPlanTier.fromUserPlanCode("trial"));
            assertEquals(AiPlanTier.PREMIUM, AiPlanTier.fromSubscriptionPlanName("premium"));
        } finally {
            Locale.setDefault(original);
        }
    }
}
