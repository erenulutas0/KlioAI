# Localization Reality

KlioAI's product focus is global English learning.

The most mature language path today is Turkish source/native language to English target language. That is an implementation maturity note, not a market-positioning limit. Public copy should not imply that KlioAI is only for Turkish users.

## Current Language Profile

- Default source/native language: Turkish
- Target/practice language: English
- Default feedback language: Turkish unless an immersion flow explicitly asks otherwise
- Legacy JSON keys such as `turkishTranslation` and `turkishMeaning` remain unchanged for app compatibility

## Implementation Rule

Backend prompts should read language assumptions from `LearningLanguageProfile` instead of scattering hardcoded language decisions across services. New prompt work should accept a profile where practical, and only fall back to the default profile for compatibility.

## Next Step

Wire explicit request/user settings into all AI flows:

- `sourceLanguage`
- `targetLanguage`
- `feedbackLanguage`

After that, rename or version legacy payload fields through a compatibility layer instead of a breaking DB/API migration.
