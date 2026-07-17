package com.ingilizce.calismaapp.service;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.Locale;

import static org.junit.jupiter.api.Assertions.assertEquals;

/**
 * Regression coverage for the Turkish-locale "dotted/dotless I" bug: JDK
 * {@code String.toUpperCase()}/{@code toLowerCase()} without an explicit
 * {@link Locale} use the JVM's default locale. On a JVM whose default locale
 * is Turkish, {@code "Indonesian".toLowerCase()} does not produce
 * "indonesian" (capital 'I' maps to dotless 'ı' instead of 'i'), so any
 * case-normalization here that skipped {@link Locale#ROOT} would silently
 * fail to match and fall back to the Turkish/English default - corrupting
 * every non-Turkish AI request. GitHub Actions/CI runners default to en_US,
 * so this class of bug is invisible in ordinary CI runs; these tests force
 * a Turkish default locale to make the regression reproducible everywhere.
 */
class LearningLanguageProfileTest {

    private Locale originalDefaultLocale;

    @BeforeEach
    void forceTurkishDefaultLocale() {
        originalDefaultLocale = Locale.getDefault();
        Locale.setDefault(new Locale("tr", "TR"));
    }

    @AfterEach
    void restoreDefaultLocale() {
        Locale.setDefault(originalDefaultLocale);
    }

    @Test
    void of_ShouldResolveIndonesianSourceLanguage_OnTurkishLocaleJvm() {
        LearningLanguageProfile profile = LearningLanguageProfile.of(
                "Indonesian", "English", "Indonesian", "B1", "Speaking");

        assertEquals("Indonesian", profile.sourceLanguage());
        assertEquals("Indonesian", profile.feedbackLanguage());
    }

    @Test
    void of_ShouldResolveAllSupportedSourceLanguages_OnTurkishLocaleJvm() {
        assertEquals("Turkish", LearningLanguageProfile.of("Turkish", "English", "Turkish").sourceLanguage());
        assertEquals("English", LearningLanguageProfile.of("English", "English", "English").sourceLanguage());
        assertEquals("Spanish", LearningLanguageProfile.of("Spanish", "English", "Spanish").sourceLanguage());
        assertEquals("Portuguese", LearningLanguageProfile.of("Portuguese", "English", "Portuguese").sourceLanguage());
        assertEquals("Indonesian", LearningLanguageProfile.of("Indonesian", "English", "Indonesian").sourceLanguage());
        assertEquals("German", LearningLanguageProfile.of("German", "English", "German").sourceLanguage());
        assertEquals("French", LearningLanguageProfile.of("French", "English", "French").sourceLanguage());
    }

    @Test
    void of_ShouldAcceptUppercaseIeltsLearningGoal_OnTurkishLocaleJvm() {
        LearningLanguageProfile profile = LearningLanguageProfile.of(
                "English", "English", "English", "B2", "IELTS");

        assertEquals("Exam", profile.learningGoal());
    }

    @Test
    void of_ShouldNormalizeEnglishLevelCaseInsensitively_OnTurkishLocaleJvm() {
        LearningLanguageProfile profile = LearningLanguageProfile.of(
                "English", "English", "English", "b2", "Speaking");

        assertEquals("B2", profile.englishLevel());
    }

    @Test
    void of_ShouldFallBackToDefaultsForUnsupportedValues() {
        LearningLanguageProfile profile = LearningLanguageProfile.of(
                "Klingon", "Spanish", "Klingon", "Z9", "Adventuring");

        assertEquals("Turkish", profile.sourceLanguage());
        assertEquals("English", profile.targetLanguage());
        assertEquals("Turkish", profile.feedbackLanguage());
        assertEquals("B1", profile.englishLevel());
        assertEquals("Speaking", profile.learningGoal());
    }
}
