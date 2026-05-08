package com.ingilizce.calismaapp.service;

import java.util.Objects;

record LearningLanguageProfile(
        String sourceLanguage,
        String targetLanguage,
        String feedbackLanguage
) {

    private static final String DEFAULT_SOURCE_LANGUAGE = "Turkish";
    private static final String DEFAULT_TARGET_LANGUAGE = "English";

    static final LearningLanguageProfile DEFAULT = new LearningLanguageProfile(
            "Turkish",
            "English",
            "Turkish"
    );

    LearningLanguageProfile {
        sourceLanguage = normalize(sourceLanguage, DEFAULT_SOURCE_LANGUAGE);
        targetLanguage = normalize(targetLanguage, DEFAULT_TARGET_LANGUAGE);
        feedbackLanguage = normalize(feedbackLanguage, sourceLanguage);
    }

    static LearningLanguageProfile defaultProfile() {
        return DEFAULT;
    }

    static LearningLanguageProfile of(
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

    static String promptPolicyBlock() {
        return DEFAULT.toPromptPolicyBlock();
    }

    String sourceToTargetLabel() {
        return sourceLanguage + " to " + targetLanguage;
    }

    String targetToSourceLabel() {
        return targetLanguage + " to " + sourceLanguage;
    }

    String toPromptPolicyBlock() {
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
