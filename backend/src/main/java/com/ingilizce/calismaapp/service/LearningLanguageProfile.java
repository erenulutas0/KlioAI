package com.ingilizce.calismaapp.service;

import java.util.Objects;

public record LearningLanguageProfile(
        String sourceLanguage,
        String targetLanguage,
        String feedbackLanguage
) {

    private static final String DEFAULT_SOURCE_LANGUAGE = "Turkish";
    private static final String DEFAULT_TARGET_LANGUAGE = "English";

    public static final LearningLanguageProfile DEFAULT = new LearningLanguageProfile(
            "Turkish",
            "English",
            "Turkish"
    );

    public LearningLanguageProfile {
        sourceLanguage = normalize(sourceLanguage, DEFAULT_SOURCE_LANGUAGE);
        targetLanguage = normalize(targetLanguage, DEFAULT_TARGET_LANGUAGE);
        feedbackLanguage = normalize(feedbackLanguage, sourceLanguage);
    }

    public static LearningLanguageProfile defaultProfile() {
        return DEFAULT;
    }

    public static LearningLanguageProfile of(
            String sourceLanguage,
            String targetLanguage,
            String feedbackLanguage
    ) {
        return new LearningLanguageProfile(
                sourceLanguage,
                targetLanguage,
                feedbackLanguage
        );
    }

    public static String promptPolicyBlock() {
        return DEFAULT.toPromptPolicyBlock();
    }

    public String sourceToTargetLabel() {
        return sourceLanguage + " to " + targetLanguage;
    }

    public String targetToSourceLabel() {
        return targetLanguage + " to " + sourceLanguage;
    }

    public String toPromptPolicyBlock() {
        return """
            LANGUAGE POLICY:
            - Product focus: English learning.
            - Source/native language: %s.
            - Target/practice language: %s.
            - Feedback language: %s unless an immersion flow explicitly asks otherwise.
            - Keep legacy JSON keys unchanged for app compatibility.
            """.formatted(sourceLanguage, targetLanguage, feedbackLanguage);
    }

    private static String normalize(String value, String fallback) {
        String normalized = Objects.toString(value, "").trim();
        return normalized.isEmpty() ? fallback : normalized;
    }
}
