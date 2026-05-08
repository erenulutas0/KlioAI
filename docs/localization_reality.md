# Localization Reality

KlioAI's current product focus is Turkish speakers learning English.

This is a deliberate market constraint for the current production version. The UI can evolve later, but AI-generated learning content must stay consistent with this focus until source/target language parameters are introduced end to end.

## Current Language Profile

- Source/native language: Turkish
- Target/practice language: English
- Feedback language: Turkish unless an immersion flow explicitly asks otherwise
- Legacy JSON keys such as `turkishTranslation` and `turkishMeaning` remain unchanged for app compatibility

## Implementation Rule

Backend prompts should read language assumptions from `LearningLanguageProfile` instead of scattering hardcoded language decisions across services.

## Next Step

When KlioAI is ready for additional markets, introduce explicit request/user settings:

- `sourceLanguage`
- `targetLanguage`
- `feedbackLanguage`

After that, rename or version legacy payload fields through a compatibility layer instead of a breaking DB/API migration.
