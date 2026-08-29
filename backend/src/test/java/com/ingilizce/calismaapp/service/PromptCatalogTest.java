package com.ingilizce.calismaapp.service;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertTrue;

class PromptCatalogTest {

    @Test
    void generateSentences_ShouldIncludeCentralLanguagePolicy_AndKeepLegacyJsonKeys() {
        PromptCatalog.PromptDef promptDef = PromptCatalog.generateSentences();

        assertTrue(promptDef.systemPrompt().contains("Product focus: English learning"));
        assertTrue(promptDef.systemPrompt().contains("Never put the target word in quotation marks"));
        assertTrue(promptDef.systemPrompt().contains("Never write about the word itself"));
        assertTrue(promptDef.systemPrompt().contains("At least one item must be a question"));
        assertTrue(promptDef.systemPrompt().contains("Source/native language: Turkish"));
        assertTrue(promptDef.systemPrompt().contains("Target/practice language: English"));
        assertTrue(promptDef.systemPrompt().contains("Learner English level: B1 CEFR"));
        assertTrue(promptDef.systemPrompt().contains("Learner goal: Speaking"));
        assertTrue(promptDef.systemPrompt().contains("turkishTranslation"));
        assertTrue(promptDef.systemPrompt().contains("turkishFullTranslation"));
        assertTrue(promptDef.output() == PromptCatalog.PromptOutput.TEXT);
    }

    /// Guards the three rules added after live output produced
    /// "Maya noticed evaluate during the trip." (dictionary form dropped into a
    /// noun slot), "Please recover your answer a little more." (grammatical but
    /// meaningless collocation) and "Could all affect our decision today?"
    /// (subject deleted to satisfy the no-pronoun-start preference).
    @Test
    void generateSentences_ShouldDemandInflectionCollocationAndGrammaticality() {
        String prompt = PromptCatalog.generateSentences().systemPrompt();

        assertTrue(prompt.contains("Inflect the target word so the sentence is grammatical"));
        assertTrue(prompt.contains("Never drop the bare dictionary form"));
        assertTrue(prompt.contains("collocate naturally"));
        assertTrue(prompt.contains("grammatical but meaningless"));
        assertTrue(prompt.contains("needs a subject and a finite verb"));
        assertTrue(prompt.contains("GRAMMAR AND MEANING OUTRANK EVERY STYLE PREFERENCE"));
        assertTrue(prompt.contains("FINAL CHECK before returning"));
    }

    /// The pronoun-start constraint used to sit under HARD RULES, where it
    /// competed with grammaticality and won -- producing subjectless questions.
    /// It must stay a preference.
    @Test
    void generateSentences_ShouldKeepPronounStartRuleAsPreferenceNotHardRule() {
        String prompt = PromptCatalog.generateSentences().systemPrompt();

        int hardRules = prompt.indexOf("HARD RULES:");
        int stylePreferences = prompt.indexOf("STYLE PREFERENCES");
        int pronounRule = prompt.indexOf("no more than one item starts with I/he/she/they");

        assertTrue(hardRules >= 0);
        assertTrue(stylePreferences > hardRules);
        assertTrue(pronounRule > stylePreferences);
    }

    @Test
    void grammarPatternSetFor_ShouldReturnFiveConcretePatterns() {
        var patterns = PromptCatalog.grammarPatternSetFor("determine", 42L, false);

        assertTrue(patterns.size() == 5);
        assertTrue(patterns.stream().allMatch(pattern -> pattern != null && !pattern.isBlank()));
    }

    @Test
    void generateSentences_ShouldAcceptCustomLanguageProfile() {
        LearningLanguageProfile profile = LearningLanguageProfile.of("tr", "en", "en", "B2", "Work");

        PromptCatalog.PromptDef promptDef = PromptCatalog.generateSentences(profile);

        assertTrue(promptDef.systemPrompt().contains("Source/native language: Turkish"));
        assertTrue(promptDef.systemPrompt().contains("Target/practice language: English"));
        assertTrue(promptDef.systemPrompt().contains("Feedback language: English"));
        assertTrue(promptDef.systemPrompt().contains("Learner English level: B2 CEFR"));
        assertTrue(promptDef.systemPrompt().contains("Learner goal: Work"));
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
    void languageProfile_ShouldSupportGlobalSourceLanguagesAndKeepEnglishTarget() {
        LearningLanguageProfile profile = LearningLanguageProfile.of("Spanish", "French", "German");

        assertTrue(profile.toPromptPolicyBlock().contains("Source/native language: Spanish"));
        assertTrue(profile.toPromptPolicyBlock().contains("Target/practice language: English"));
        assertTrue(profile.toPromptPolicyBlock().contains("Feedback language: German"));
    }

    @Test
    void languageProfile_ShouldNormalizeLevelAndGoal() {
        LearningLanguageProfile profile = LearningLanguageProfile.of("es", "en", "es", "c1", "travel");

        assertTrue(profile.toPromptPolicyBlock().contains("Source/native language: Spanish"));
        assertTrue(profile.toPromptPolicyBlock().contains("Learner English level: C1 CEFR"));
        assertTrue(profile.toPromptPolicyBlock().contains("Learner goal: Travel"));
    }

    @Test
    void interferenceNotesFor_ShouldReturnDistinctNonEmptyNotes_ForEverySupportedSourceLanguage() {
        // Asked of the supported set, not of a list typed in here. The list
        // that used to stand in this place named six languages under a method
        // called ...ForAllSevenSourceLanguages, so it could only ever check
        // what someone had remembered to add to it: a language could join the
        // profile with no transfer notes at all and nothing would say so.
        // English is the one exception, and it is asserted separately below.
        java.util.Set<String> languages = new java.util.HashSet<>(
                LearningLanguageProfile.supportedSourceLanguages());
        languages.remove("English");
        assertTrue(languages.size() > 1, "the supported set is empty or trivial, so this checks nothing");

        java.util.Set<String> seen = new java.util.HashSet<>();
        for (String language : languages) {
            String notes = PromptCatalog.interferenceNotesFor(language);
            assertTrue(notes.contains("COMMON " + language.toUpperCase(java.util.Locale.ROOT) + "-SPEAKER TRANSFER ERRORS"),
                    "Expected labeled block for " + language);
            assertTrue(seen.add(notes), "Expected unique notes per language, duplicate for " + language);
        }
    }

    @Test
    void interferenceNotesFor_ShouldReturnEmptyString_ForEnglishOrUnknownSource() {
        assertTrue(PromptCatalog.interferenceNotesFor("English").isEmpty());
        assertTrue(PromptCatalog.interferenceNotesFor("Klingon").isEmpty());
        assertTrue(PromptCatalog.interferenceNotesFor(null).isEmpty());
    }

    @Test
    void checkEnglishTranslation_ShouldIncludeInterferenceNotes_ForNonTurkishSource() {
        LearningLanguageProfile profile = LearningLanguageProfile.of("German", "English", "German");

        PromptCatalog.PromptDef promptDef = PromptCatalog.checkEnglishTranslation(profile);

        assertTrue(promptDef.systemPrompt().contains("COMMON GERMAN-SPEAKER TRANSFER ERRORS"));
        assertTrue(promptDef.systemPrompt().contains("verb to second position"));
    }

    @Test
    void checkEnglishTranslation_ShouldIncludeInterferenceNotes_ForTurkishSource() {
        PromptCatalog.PromptDef promptDef = PromptCatalog.checkEnglishTranslation();

        assertTrue(promptDef.systemPrompt().contains("COMMON TURKISH-SPEAKER TRANSFER ERRORS"));
        assertTrue(promptDef.systemPrompt().contains("no articles"));
    }
}
