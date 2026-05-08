package com.ingilizce.calismaapp.service;

import java.util.Objects;
import java.util.Set;

public record LearningLanguageProfile(
        String sourceLanguage,
        String targetLanguage,
        String feedbackLanguage
) {

    private static final String DEFAULT_SOURCE_LANGUAGE = "Turkish";
    private static final String DEFAULT_TARGET_LANGUAGE = "English";
    private static final Set<String> SUPPORTED_LANGUAGES = Set.of("Turkish", "English");

    public static final LearningLanguageProfile DEFAULT = new LearningLanguageProfile(
            "Turkish",
            "English",
            "Turkish"
    );

    public LearningLanguageProfile {
        sourceLanguage = normalizeSupported(sourceLanguage, DEFAULT_SOURCE_LANGUAGE);
        targetLanguage = normalizeSupported(targetLanguage, DEFAULT_TARGET_LANGUAGE);
        feedbackLanguage = normalizeSupported(feedbackLanguage, sourceLanguage);
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

    private static String normalizeSupported(String value, String fallback) {
        String normalized = canonicalLanguageName(value);
        return SUPPORTED_LANGUAGES.contains(normalized) ? normalized : fallback;
    }

    private static String canonicalLanguageName(String value) {
        String normalized = Objects.toString(value, "").trim().toLowerCase();
        return switch (normalized) {
            case "tr", "tr-tr", "turkish", "turkce", "türkçe" -> "Turkish";
            case "en", "en-us", "en-gb", "english" -> "English";
            default -> "";
        };
    }
}
