package com.ingilizce.calismaapp.service;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertTrue;

class PromptCatalogTest {

    @Test
    void generateSentences_ShouldIncludeCentralLanguagePolicy_AndKeepLegacyJsonKeys() {
        PromptCatalog.PromptDef promptDef = PromptCatalog.generateSentences();

        assertTrue(promptDef.systemPrompt().contains("Product focus: Turkish speakers learning English"));
        assertTrue(promptDef.systemPrompt().contains("Source/native language: Turkish"));
        assertTrue(promptDef.systemPrompt().contains("Target/practice language: English"));
        assertTrue(promptDef.systemPrompt().contains("turkishTranslation"));
        assertTrue(promptDef.systemPrompt().contains("turkishFullTranslation"));
    }

    @Test
    void speakingEvaluation_ShouldUseConfiguredFeedbackLanguage() {
        PromptCatalog.PromptDef promptDef = PromptCatalog.evaluateSpeakingTest();

        assertTrue(promptDef.systemPrompt().contains("Feedback language: Turkish"));
        assertTrue(promptDef.systemPrompt().contains("detailed feedback in Turkish"));
    }
}
