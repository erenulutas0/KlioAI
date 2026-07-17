# Localization Reality

KlioAI's product focus is global English learning.

Growth and implementation tracking for the global source-language expansion now
lives in `docs/GLOBAL_GROWTH_LOCALIZATION_PLAN.md`.

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

## Grammar Strategy

Grammar checking is intentionally English-only in the current product shape. Native/source language and feedback language settings do not change the grammar target; the user submits an English sentence and the backend checks that English sentence.

`GET /api/grammar/status` reports this as:

- `service`: `AI Grammar Checker`
- `targetLanguage`: `English`
- `strategy`: `english-learning-only`

## Current Client Wiring

The Flutter client now sends a supported AI language profile with quota-protected AI requests:

- `sourceLanguage`: selected in Settings -> Learning Profile, currently limited to Turkish or English and defaulting to Turkish
- `targetLanguage`: English
- `feedbackLanguage`: Turkish or English based on the selected app UI language

This keeps the mature Turkish-to-English learning path stable by default while making the source/native language explicit. English UI users can also receive AI feedback in English.

## Next Step

Before expanding beyond the current Turkish/English support window, keep evolving the Learning Profile surface carefully:

- Source language can be user-selected.
- Target/practice language remains English-only for now.
- Feedback language follows app UI language for now.

After that, rename or version legacy payload fields through a compatibility layer instead of a breaking DB/API migration.
