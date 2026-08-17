# KlioAI

**An English learning app built around the words you actually keep.**

Most vocabulary apps hand you a fixed word list. KlioAI is built the other way round: you
collect the words you meet, and every other feature — spaced review, example sentences,
grammar drills, speaking practice — is generated from *your* list.

Live on Google Play · Flutter client, Spring Boot backend · Turkish → English

[**Google Play**](https://play.google.com/store/apps/details?id=com.VocabMaster)

---

## The app

| | | |
|:--:|:--:|:--:|
| ![Home](docs/screenshots/home.png) | ![Review](docs/screenshots/review.png) | ![Word Galaxy](docs/screenshots/word-galaxy.png) |
| **Home** — daily words, streak, and what is due today | **Review** — recall first, then grade yourself | **Word Galaxy** — your vocabulary as a map |
| ![Practice](docs/screenshots/practice.png) | ![Speaking](docs/screenshots/speaking.png) | ![Translation](docs/screenshots/translation.png) |
| **Practice** — translation, reading, writing, grammar | **Speaking** — talk to a chosen voice, transcribed by Whisper | **Levels** — every generator is CEFR-aware |

---

## How the learning loop works

**1. Collect.** Add a word by hand, from the built-in dictionary, or from the daily word
set. Sentences attach to words, so vocabulary and context stay together.

**2. Review.** Cards are scheduled with SM-2 spaced repetition. The card shows the word
first and hides the meaning behind a deliberate tap — grading yourself before you have seen
the answer is the part that makes the schedule mean anything. Hard / Good / Easy feed back
into the interval.

**3. Practise.** Translation, reading, writing and grammar drills are generated at your CEFR
level. Grammar questions are built around words already in your list, so a tense drill is
also a vocabulary review.

**4. Speak.** Pick a voice and hold a conversation. Speech is transcribed with Whisper and
answered by the same model that runs the rest of the app.

Every graded recall — from classic review, Word Galaxy, translation practice or a grammar
quiz — is written to an append-only event log, so the schedule reflects everything the
learner did, not just what happened on one screen.

---

## Architecture

```text
flutter_vocabmaster/   Flutter mobile application
backend/               Spring Boot API, persistence, security, subscriptions
docs/                  Project notes and public documentation
scripts/               Local verification and operational helper scripts
```

**Mobile** — Flutter/Dart, offline-first local persistence, Google sign-in, Google Play
Billing, theme-aware components, English and Turkish throughout.

**Backend** — Java 21 / Spring Boot, PostgreSQL with Flyway migrations, Redis for rate
limiting and AI quota accounting, JWT auth with refresh-token rotation, server-side Google
Play subscription verification.

**AI** — Groq (`gpt-oss-120b` / `gpt-oss-20b`) for generation, `whisper-large-v3-turbo` for
speech, self-hosted [Piper](https://github.com/rhasspy/piper) for text-to-speech. Every AI
call is proxied, quota-checked and metered server-side; no provider key ever reaches the
device.

**Notifications** — a single hourly job serves every timezone: each device is released on
its own local evening, and only if there is something genuinely due and the learner has not
already practised that day.

Tests: 924 backend, 320 client.

---

## Engineering notes

The interesting problems in this project were not the features. They were the failures that
looked like success. A few, with the commits that fixed them:

**Three months of hardcoded fallback sentences, reported as 100% healthy.**
The AI provider metric counted an empty completion as a success, because the HTTP request
had in fact worked — it just came back with nothing, and the caller quietly substituted a
template. "Answered with nothing" is now its own outcome with its own counter, distinct from
both success and error.

**Whisper transcribing an empty room.**
Recording silence produced fluent, confident text that was auto-sent to the tutor. Four
fixes went into the model's *output* — the wording, its confidence score, a confidence field
the API response did not contain — before the actual cause turned up in the *input*: a
priming prompt reading "English learning conversation. Transcribe the learner's English
speech exactly." Whisper's `prompt` parameter is prior transcript text, not an instruction,
so with no audio the model simply continued the sentence. The transcript began with the
prompt's own words. A microphone-level dynamic-range gate now stops silent clips before
they are ever uploaded.

**A daily reminder that reached nobody.**
The scheduler ran hourly for days reporting `considered=0`. The settings screen wrote the
reminder preference to one table; the sender read a denormalised copy in another that was
only ever written at device registration. The switch was on, the preference said true, and
nothing was sent.

**A free tier below the cost of a single request.**
One short conversation reported `1858/1500 tokens` and every AI feature went dark for the
day. The limit was declared in three property files and the one that actually won —
`application-prod.properties` — hardcoded it, so the other two read as authoritative and
were dead text.

The shape repeats: one fact stored in two places, and the read path holding the stale one.
None of these failed loudly. Each needed either production data or a phone in hand, which is
why the app now logs the *inputs* to its decisions and not only their outcomes, and why
learners can flag bad generated content in one tap from any screen that shows it.

---

## Security and privacy

No production secret is committed to this repository. `.env.example` is a template; real
JWT secrets, database and Redis passwords, AI provider keys and Google Play service-account
credentials are supplied at runtime through environment variables or mounted secret files.

- Google-only account authentication
- Server-side Google Play subscription verification — the client cannot grant itself entitlements
- Per-plan AI token quotas, enforced in the backend
- Rate limiting on authentication, AI calls and support tickets
- Refresh-token rotation with session invalidation
- Support-ticket daily limits

---

## Local development

Client:

```bash
cd flutter_vocabmaster
flutter pub get
flutter analyze --no-fatal-infos
flutter test --reporter=compact
```

Backend:

```bash
cd backend
mvn test
```

Full stack, with `.env` populated from your own secret storage:

```bash
docker compose up -d
```

Before a production build, verify the backend environment is populated from real secret
storage and that release builds bundle no provider secrets.

---

## Status

Published on Google Play and under active development. The current focus is retention and
content quality: an offline evaluation harness for the AI generators, and closing the loop
between what learners report and what gets fixed.
