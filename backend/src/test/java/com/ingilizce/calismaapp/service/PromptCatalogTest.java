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
        LearningLanguageProfile profile = LearningLanguageProfile.of("Spanish", "English", "Spanish");

        PromptCatalog.PromptDef promptDef = PromptCatalog.generateSentences(profile);

        assertTrue(promptDef.systemPrompt().contains("Source/native language: Spanish"));
        assertTrue(promptDef.systemPrompt().contains("Target/practice language: English"));
        assertTrue(promptDef.systemPrompt().contains("Feedback language: Spanish"));
    }

    @Test
    void speakingEvaluation_ShouldUseConfiguredFeedbackLanguage() {
        PromptCatalog.PromptDef promptDef = PromptCatalog.evaluateSpeakingTest();

        assertTrue(promptDef.systemPrompt().contains("Feedback language: Turkish"));
        assertTrue(promptDef.systemPrompt().contains("detailed feedback in Turkish"));
    }

    @Test
    void speakingEvaluation_ShouldAcceptCustomFeedbackLanguage() {
        LearningLanguageProfile profile = LearningLanguageProfile.of("German", "English", "German");

        PromptCatalog.PromptDef promptDef = PromptCatalog.evaluateSpeakingTest(profile);

        assertTrue(promptDef.systemPrompt().contains("Feedback language: German"));
        assertTrue(promptDef.systemPrompt().contains("detailed feedback in German"));
    }
}
