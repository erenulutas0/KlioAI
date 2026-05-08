# Localization Reality

KlioAI's product focus is global English learning.

Current production language support is intentionally limited to Turkish and English. Public copy should not imply that KlioAI is only for Turkish users, but the app should not advertise unsupported UI/source-language coverage yet.

## Current Language Profile

- Supported app UI languages: English, Turkish
- Supported AI language profile values: English, Turkish
- Default source/native language: Turkish
- Target/practice language: English
- Default feedback language: Turkish unless an immersion flow explicitly asks otherwise
- Legacy JSON keys such as `turkishTranslation` and `turkishMeaning` remain unchanged for app compatibility

## Implementation Rule

Backend prompts should read language assumptions from `LearningLanguageProfile` instead of scattering hardcoded language decisions across services. New prompt work should accept a profile where practical, normalize unsupported languages back to the current Turkish/English support window, and fall back to the default profile for compatibility.

Request-level language profiles are supported for core AI flows:

- sentence generation
- translation check
- speaking evaluation
- dictionary
- reading
- writing

## Current Client Wiring

The Flutter client now sends a supported AI language profile with quota-protected AI requests:

- `sourceLanguage`: Turkish
- `targetLanguage`: English
- `feedbackLanguage`: Turkish or English based on the selected app UI language

This keeps the mature Turkish-to-English learning path stable while allowing English UI users to receive AI feedback in English.

## Next Step

Add an explicit learning-language settings surface before expanding beyond the current Turkish/English support window:

- Native/source language
- Target/practice language
- Feedback language

After that, rename or version legacy payload fields through a compatibility layer instead of a breaking DB/API migration.
