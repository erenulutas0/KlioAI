package com.ingilizce.calismaapp.service;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertTrue;

class PromptCatalogTest {

    @Test
    void generateSentences_ShouldIncludeCentralLanguagePolicy_AndKeepLegacyJsonKeys() {
        PromptCatalog.PromptDef promptDef = PromptCatalog.generateSentences();

        assertTrue(promptDef.systemPrompt().contains("Product focus: English learning"));
        assertTrue(promptDef.systemPrompt().contains("Source/native language: Turkish"));
        assertTrue(promptDef.systemPrompt().contains("Target/practice language: English"));
        assertTrue(promptDef.systemPrompt().contains("turkishTranslation"));
        assertTrue(promptDef.systemPrompt().contains("turkishFullTranslation"));
    }

    @Test
    void generateSentences_ShouldAcceptCustomLanguageProfile() {
        LearningLanguageProfile profile = LearningLanguageProfile.of("tr", "en", "en");

        PromptCatalog.PromptDef promptDef = PromptCatalog.generateSentences(profile);

        assertTrue(promptDef.systemPrompt().contains("Source/native language: Turkish"));
        assertTrue(promptDef.systemPrompt().contains("Target/practice language: English"));
        assertTrue(promptDef.systemPrompt().contains("Feedback language: English"));
    }

    @Test
    void speakingEvaluation_ShouldUseConfiguredFeedbackLanguage() {
        PromptCatalog.PromptDef promptDef = PromptCatalog.evaluateSpeakingTest();

        assertTrue(promptDef.systemPrompt().contains("Feedback language: Turkish"));
        assertTrue(promptDef.systemPrompt().contains("detailed feedback in Turkish"));
    }

    @Test
    void speakingEvaluation_ShouldAcceptCustomFeedbackLanguage() {
        LearningLanguageProfile profile = LearningLanguageProfile.of("Turkish", "English", "English");

        PromptCatalog.PromptDef promptDef = PromptCatalog.evaluateSpeakingTest(profile);

        assertTrue(promptDef.systemPrompt().contains("Feedback language: English"));
        assertTrue(promptDef.systemPrompt().contains("detailed feedback in English"));
    }

    @Test
    void languageProfile_ShouldFallbackUnsupportedLanguagesToCurrentSupportedPair() {
        LearningLanguageProfile profile = LearningLanguageProfile.of("Spanish", "French", "German");

        assertTrue(profile.toPromptPolicyBlock().contains("Source/native language: Turkish"));
        assertTrue(profile.toPromptPolicyBlock().contains("Target/practice language: English"));
        assertTrue(profile.toPromptPolicyBlock().contains("Feedback language: Turkish"));
    }
}
