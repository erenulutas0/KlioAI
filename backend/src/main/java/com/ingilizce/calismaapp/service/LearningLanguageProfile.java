package com.ingilizce.calismaapp.service;

import java.util.Locale;
import java.util.Objects;
import java.util.Set;

public record LearningLanguageProfile(
        String sourceLanguage,
        String targetLanguage,
        String feedbackLanguage,
        String englishLevel,
        String learningGoal
) {

    private static final String DEFAULT_SOURCE_LANGUAGE = "Turkish";
    private static final String DEFAULT_TARGET_LANGUAGE = "English";
    private static final String DEFAULT_ENGLISH_LEVEL = "B1";
    private static final String DEFAULT_LEARNING_GOAL = "Speaking";
    private static final Set<String> SUPPORTED_SOURCE_LANGUAGES = Set.of(
            "Turkish",
            "English",
            "Spanish",
            "Portuguese",
            "Indonesian",
            "German",
            "French");
    private static final Set<String> SUPPORTED_FEEDBACK_LANGUAGES = Set.of(
            "Turkish",
            "English",
            "Spanish",
            "Portuguese",
            "Indonesian",
            "German",
            "French");
    private static final Set<String> SUPPORTED_LEVELS = Set.of("A1", "A2", "B1", "B2", "C1", "C2");
    private static final Set<String> SUPPORTED_GOALS = Set.of("Speaking", "Vocabulary", "Exam", "Work", "Travel");

    public static final LearningLanguageProfile DEFAULT = new LearningLanguageProfile(
            "Turkish",
            "English",
            "Turkish",
            DEFAULT_ENGLISH_LEVEL,
            DEFAULT_LEARNING_GOAL
    );

    public LearningLanguageProfile {
        sourceLanguage = normalizeSourceLanguage(sourceLanguage);
        targetLanguage = normalizeTargetLanguage(targetLanguage);
        feedbackLanguage = normalizeFeedbackLanguage(feedbackLanguage, sourceLanguage);
        englishLevel = normalizeEnglishLevel(englishLevel);
        learningGoal = normalizeLearningGoal(learningGoal);
    }

    public static LearningLanguageProfile defaultProfile() {
        return DEFAULT;
    }

    public static LearningLanguageProfile of(
            String sourceLanguage,
            String targetLanguage,
            String feedbackLanguage
    ) {
        return of(
                sourceLanguage,
                targetLanguage,
                feedbackLanguage,
                DEFAULT_ENGLISH_LEVEL,
                DEFAULT_LEARNING_GOAL
        );
    }

    public static LearningLanguageProfile of(
            String sourceLanguage,
            String targetLanguage,
            String feedbackLanguage,
            String englishLevel,
            String learningGoal
    ) {
        return new LearningLanguageProfile(
                sourceLanguage,
                targetLanguage,
                feedbackLanguage,
                englishLevel,
                learningGoal
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
            - Learner English level: %s CEFR.
            - Learner goal: %s.
            - Adapt vocabulary, examples, feedback detail, and scenario framing to the level and goal.
            - Keep legacy JSON keys unchanged for app compatibility.
            """.formatted(sourceLanguage, targetLanguage, feedbackLanguage, englishLevel, learningGoal);
    }

    private static String normalizeSourceLanguage(String value) {
        String normalized = canonicalLanguageName(value);
        return SUPPORTED_SOURCE_LANGUAGES.contains(normalized) ? normalized : DEFAULT_SOURCE_LANGUAGE;
    }

    private static String normalizeTargetLanguage(String value) {
        String normalized = canonicalLanguageName(value);
        return DEFAULT_TARGET_LANGUAGE.equals(normalized) ? normalized : DEFAULT_TARGET_LANGUAGE;
    }

    private static String normalizeFeedbackLanguage(String value, String fallback) {
        String normalized = canonicalLanguageName(value);
        return SUPPORTED_FEEDBACK_LANGUAGES.contains(normalized) ? normalized : fallback;
    }

    private static String normalizeEnglishLevel(String value) {
        String normalized = Objects.toString(value, "").trim().toUpperCase(Locale.ROOT);
        return SUPPORTED_LEVELS.contains(normalized) ? normalized : DEFAULT_ENGLISH_LEVEL;
    }

    private static String normalizeLearningGoal(String value) {
        String normalized = Objects.toString(value, "").trim().toLowerCase(Locale.ROOT);
        String canonical = switch (normalized) {
            case "speaking", "speak", "conversation", "konusma", "konuşma" -> "Speaking";
            case "vocabulary", "words", "kelime", "kelimeler" -> "Vocabulary";
            case "exam", "ielts", "toefl", "yds", "sinav", "sınav" -> "Exam";
            case "work", "career", "business", "is", "iş" -> "Work";
            case "travel", "trip", "seyahat", "gezi" -> "Travel";
            default -> "";
        };
        return SUPPORTED_GOALS.contains(canonical) ? canonical : DEFAULT_LEARNING_GOAL;
    }

    private static String canonicalLanguageName(String value) {
        // Locale.ROOT is required here: on a JVM whose default locale is Turkish,
        // toLowerCase() maps 'I' -> 'ı' (dotless), so "Indonesian".toLowerCase()
        // never matches the "indonesian" case below and silently falls through to
        // the Turkish/English default, corrupting every non-Turkish AI request.
        String normalized = Objects.toString(value, "").trim().toLowerCase(Locale.ROOT);
        return switch (normalized) {
            case "tr", "tr-tr", "turkish", "turkce", "türkçe" -> "Turkish";
            case "en", "en-us", "en-gb", "english" -> "English";
            case "es", "es-es", "es-mx", "spanish", "espanol", "español" -> "Spanish";
            case "pt", "pt-br", "pt-pt", "portuguese", "portugues", "português" -> "Portuguese";
            case "id", "id-id", "indonesian", "bahasa indonesia" -> "Indonesian";
            case "de", "de-de", "german", "deutsch" -> "German";
            case "fr", "fr-fr", "french", "francais", "français" -> "French";
            default -> "";
        };
    }
}
