# KlioAI

KlioAI is an AI-assisted English learning app currently focused on Turkish-speaking learners. It is built for vocabulary growth, sentence practice, speaking, grammar, writing, and spaced review. The product combines structured study flows with interactive practice modes so learners can save words, create sentences, review them, and use AI feedback inside a single mobile experience.

## Product Overview

KlioAI focuses on practical Turkish-to-English learning rather than passive memorization. Users can build a personal word bank, attach sentences to words, repeat content through classic and neural review modes, and use AI-powered practice tools for speaking, grammar, writing, and sentence generation.

Core learning experiences:

- Word and sentence management with offline-friendly local storage.
- Daily words, XP, streaks, and progress tracking.
- Classic review mode for direct repetition.
- Neural review game for association-based vocabulary practice.
- Word Universe for visual word mapping, theme-based exploration, and sentence attachment.
- AI speaking, grammar, writing, translation, and sentence support.
- Theme customization across the app.
- In-app support ticket flow with daily ticket limits.
- Google sign-in and Google Play subscription verification.

## Market Focus

The current production learning experience is Turkish native language to English target language. The UI may contain English product copy, but AI learning flows should not be marketed as broad multilingual support until source, target, and feedback language parameters are implemented end to end.

## Architecture

The project is split into a Flutter mobile client and a Spring Boot backend.

```text
flutter_vocabmaster/   Flutter mobile application
backend/               Spring Boot API, persistence, security, subscriptions
docs/                  Project notes and public documentation
scripts/               Local verification and operational helper scripts
```

Mobile app:

- Flutter and Dart.
- Local persistence for offline-first learning flows.
- Google sign-in.
- Google Play Billing integration.
- Theme-aware UI components and localized product text.

Backend:

- Java and Spring Boot.
- PostgreSQL persistence with Flyway migrations.
- Redis-backed rate limiting, auth/session controls, and AI quota tracking.
- JWT authentication with refresh-token rotation.
- Google Play subscription verification.
- AI proxy and quota enforcement for protected AI features.

## Security And Privacy

Production secrets are not committed to this repository. Runtime credentials must be provided through environment variables, secret files, or the deployment environment.

The repository includes `.env.example` as a configuration template only. Real values such as JWT secrets, database passwords, Redis passwords, AI provider keys, and Google Play service account credentials must stay outside Git.

Security-sensitive controls currently include:

- Google-only account authentication.
- Server-side Google Play subscription verification.
- AI token quotas by plan.
- Rate limiting for authentication, AI calls, and support tickets.
- Refresh-token rotation and session invalidation support.
- Support ticket daily limits to reduce abuse.

## Local Development

Flutter app:

```powershell
cd flutter_vocabmaster
flutter pub get
flutter analyze --no-fatal-infos
flutter test --reporter=compact
```

Backend:

```powershell
cd backend
mvn test
```

Before production builds, verify that the backend environment is populated from real secret storage and that mobile release builds do not bundle provider secrets.

## Release Notes

KlioAI is prepared for Google Play distribution with updated app branding, launcher assets, English localization work, subscription verification, support ticketing, and improved review experiences.
