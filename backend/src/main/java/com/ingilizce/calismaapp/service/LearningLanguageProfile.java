package com.ingilizce.calismaapp.service;

final class LearningLanguageProfile {

    private static final String MARKET_FOCUS = "Turkish speakers learning English";
    private static final String SOURCE_LANGUAGE = "Turkish";
    private static final String TARGET_LANGUAGE = "English";
    private static final String FEEDBACK_LANGUAGE = "Turkish";

    private LearningLanguageProfile() {
    }

    static String marketFocus() {
        return MARKET_FOCUS;
    }

    static String sourceLanguage() {
        return SOURCE_LANGUAGE;
    }

    static String targetLanguage() {
        return TARGET_LANGUAGE;
    }

    static String feedbackLanguage() {
        return FEEDBACK_LANGUAGE;
    }

    static String sourceToTargetLabel() {
        return SOURCE_LANGUAGE + " to " + TARGET_LANGUAGE;
    }

    static String targetToSourceLabel() {
        return TARGET_LANGUAGE + " to " + SOURCE_LANGUAGE;
    }

    static String promptPolicyBlock() {
        return """
            LANGUAGE POLICY:
            - Product focus: %s.
            - Source/native language: %s.
            - Target/practice language: %s.
            - Feedback language: %s unless an immersion flow explicitly asks otherwise.
            - Keep legacy JSON keys unchanged for app compatibility.
            """.formatted(MARKET_FOCUS, SOURCE_LANGUAGE, TARGET_LANGUAGE, FEEDBACK_LANGUAGE);
    }
}
