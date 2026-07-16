# KlioAI Global Growth and Localization Plan

Last update: 2026-07-03

This is the working checklist for turning KlioAI from a Turkish-first English
learning app into a global English-learning product without breaking the current
production path.

## Product Positioning

KlioAI should not try to become "Duolingo for every language" yet. The sharper
position is:

> AI-powered English practice personalized to the learner's native language.

That keeps the target language stable as English while allowing users from
different countries to receive explanations, translations, examples, onboarding,
and store messaging in their own language.

## Current Reality

- Target/practice language is English.
- App UI supports Turkish and English.
- Learning Profile currently supports Turkish, English, Spanish, Portuguese,
  Indonesian, German, and French as source languages.
- Learning Profile also stores English level (`A1`-`C2`) and learning goal
  (`Speaking`, `Vocabulary`, `Exam`, `Work`, `Travel`) from onboarding or
  Settings.
- Backend AI requests accept `sourceLanguage`, fixed `targetLanguage=English`,
  `feedbackLanguage`, `englishLevel`, and `learningGoal` in core flows.
- The old Turkish-first data model is still visible in many names:
  `turkishMeaning`, `turkishTranslation`, `turkishFullTranslation`,
  `EN_TO_TR`, `TR_TO_EN`, and `NeuralGameMode.turkishTranslation`.
- This naming is compatibility debt, not an immediate product blocker.

## Strategy

1. Keep English as the only target language for now.
2. Add native/source language support gradually.
3. Do not rename database columns or API fields in one large breaking migration.
4. Add neutral aliases first, keep old Turkish keys as backward-compatible
   fallbacks, and move Flutter reads/writes to neutral fields over time.
5. Do not buy paid ads until onboarding, analytics, and store listings can tell
   whether a user from each market actually activates.

## Initial Target Markets

Start with markets where English learning demand is broad and product messaging
can stay simple:

- Turkey: current strongest path.
- Global English UI: broad testing/default listing.
- Brazil/Portugal: Portuguese source-language path.
- LATAM/Spain: Spanish source-language path.
- Indonesia: Indonesian source-language path.

Arabic can be valuable, but RTL layout and cultural/content QA make it a later
step unless there is a specific launch reason.

## Implementation Checklist

### Phase 0 - Audit and Tracking

- [x] Create this living plan.
- [x] Confirm there are no empty Markdown files to remove.
- [x] Remove stale non-product Flutter worklog file.
- [x] Identify hardcoded Turkish compatibility fields across backend and Flutter.
- [x] Link `docs/localization_reality.md` to this plan.
- [x] Decide the first non-TR source language for implementation.

### Phase 1 - Compatibility Layer

- [x] Backend sentence generation should emit neutral fields in addition to old
      keys:
      - `sourceTranslation`
      - `sourceFullTranslation`
      - keep `turkishTranslation`
      - keep `turkishFullTranslation`
- [x] Flutter `SentencePractice` should prefer neutral fields and fall back to
      old Turkish keys.
- [x] Backend word/dictionary responses should emit `sourceMeaning` alongside
      `turkishMeaning`.
- [x] Flutter `Word` model should expose a neutral display meaning while keeping
      the local DB column stable.
- [x] Translation direction constants should gain neutral aliases:
      - `TARGET_TO_SOURCE`
      - `SOURCE_TO_TARGET`
      - keep `EN_TO_TR`
      - keep `TR_TO_EN`
- [x] Translation UI should display dynamic language labels instead of fixed
      `EN -> TR` and `TR -> EN`.

### Phase 2 - Language Profile Expansion

- [x] Extend supported source languages beyond Turkish/English:
      Spanish, Portuguese, Indonesian, German, French.
- [x] Add localized source-language labels in Flutter.
- [x] Add onboarding question: "What language do you speak?"
- [x] Add onboarding question: "What is your English level?"
- [x] Add onboarding question: "Why are you learning English?"
- [x] Add Settings controls for native/source language, English level, and
      learning goal.
- [x] Ensure AI prompt profiles use the selected source language in:
      Daily Words, sentence generation, translation checking, speaking, writing,
      reading, pronunciation, dictionary.
- [x] Ensure backend prompts use `englishLevel` and `learningGoal` where useful
      instead of treating them as payload-only metadata.

### Phase 3 - Store and Growth Readiness

- [x] Add Firebase activation events needed before paid ads:
      `onboarding_completed`, `word_added`, `first_ai_sentence_generated`,
      `first_speaking_started`, `pronunciation_report_completed`,
      `paywall_viewed`, `purchase_started`, `purchase_completed`.
- [x] Prepare localized Google Play listing copy for Turkish.
- [x] Prepare global English listing copy.
- [x] Prepare one test listing for Spanish or Portuguese.
- [x] Prepare screenshot captions per market.
- [ ] Run Play Store listing experiments before paid install campaigns.
- [ ] Define the first activation metric for Google Ads optimization.

### Phase 4 - Paid Acquisition Test

- [ ] Do not start until Phase 3 analytics are live.
- [ ] Start with small country/language-separated campaigns.
- [ ] Keep install campaigns separate from in-app action campaigns.
- [ ] Compare CPI, activation rate, first-session completion, and paywall view
      rate by market.
- [ ] Stop weak markets quickly; do not scale installs without retention.

## Technical Notes From Audit

High-impact compatibility areas:

- Backend:
  - `PracticeSentence` still exposes `turkishTranslation` and
    `turkishFullTranslation`.
  - `ChatbotController` accepts/normalizes old Turkish sentence keys.
  - Translation direction values still use `EN_TO_TR` and `TR_TO_EN`.
  - `CreateWordRequest` still uses `turkish`.
- Flutter:
  - `Word.turkishMeaning` is the main local word meaning field.
  - `SentencePractice.turkishTranslation` is the main local sentence translation
    field.
  - Local SQLite columns are named `turkishMeaning` and `turkishTranslation`.
  - Translation practice UI labels are fixed to `EN -> TR` and `TR -> EN`.
  - Settings source-language list is currently `Turkish`, `English`,
    `Spanish`, `Portuguese`, `Indonesian`, `German`, and `French`.
  - Learning Profile now persists `englishLevel` and `learningGoal` locally and
    sends them in AI request profile payloads.
  - Backend `LearningLanguageProfile` supports Spanish, Portuguese,
    Indonesian, German, and French as source/feedback languages while keeping
    target/practice language locked to English.

These are manageable if handled as aliases first. A direct rename would be too
risky for offline sync, cached local data, and deployed API compatibility.

## Advertising Positioning Ideas

Do not lead with generic "AI English app". Lead with a concrete job:

- Speak English and get instant pronunciation feedback.
- Turn saved words into real speaking practice.
- Practice English with AI conversations, not just flashcards.
- Learn vocabulary by using it in sentences, speech, and review.

Turkish positioning:

- Kelime ezberleme değil, kelimeyi konuşturma uygulaması.
- İngilizce konuşma, telaffuz ve kelime pratiğini tek günlük döngüde topla.

## Decision Log

- 2026-07-03: Keep English as the only target language for now.
- 2026-07-03: Expand by learner source language, not by adding many target
  languages.
- 2026-07-03: Use compatibility aliases before any DB/API rename.
- 2026-07-03: Avoid paid ads until activation analytics and localized store
  listings are ready.
- 2026-07-03: First non-TR source-language implementation batch is Spanish,
  Portuguese, Indonesian, German, and French. Arabic is deferred because RTL
  layout and content QA need a separate pass.
- 2026-07-03: First-run onboarding now skips feature tour only into Learning
  Profile setup, not past it; users can still accept defaults and continue.
- 2026-07-03: Backend prompt policy now includes CEFR level and learning goal,
  and sentence-generation cache keys include those profile dimensions.
