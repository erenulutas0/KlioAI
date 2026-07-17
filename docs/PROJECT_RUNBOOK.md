# Project Runbook

Last audit: 2026-05-24 Europe/Istanbul

This file holds stable project context. `AGENTS.md` is the short operating contract; this file is the architectural map.

## Product

KlioAI is an AI supported English learning app. The app is live in production but currently has little or no organic user traffic. The important near-term goal is to make auth, Google Play subscription, free AI quota, and core practice flows reliable before scaling acquisition.

## Stack

- Backend: Spring Boot 3.5.x, Java 17, Maven, Flyway, JPA/Hibernate.
- Database: PostgreSQL.
- Cache/security counters: Redis main plus Redis security instance.
- Frontend: Flutter in `flutter_vocabmaster/`.
- AI provider: Groq.
- Observability: Prometheus, Grafana, Alertmanager.
- Public API: `https://api.klioai.app`.
- Public static site: `https://klioai.app`.

## Backend Source Areas

- Config:
  - `backend/src/main/resources/application.properties`
  - `backend/src/main/resources/application-docker.properties`
  - `backend/src/main/resources/application-prod.properties`
- DB migrations:
  - `backend/src/main/resources/db/migration`
- Auth:
  - `backend/src/main/java/com/ingilizce/calismaapp/controller/AuthController.java`
  - `backend/src/main/java/com/ingilizce/calismaapp/security`
- AI entitlement/quota:
  - `AiEntitlementService`
  - `AiPlanTier`
  - `AiTokenQuotaService`
- Subscription:
  - `SubscriptionController`
  - `GooglePlaySubscriptionVerificationService`
  - `GooglePlaySubscriptionReconciliationService`
- Daily content:
  - `DailyWordService`
  - `DailyReadingService`
  - `DailyWritingTopicService`
  - `DailyExamPackService`

## Flutter Source Areas

- App entry/config:
  - `flutter_vocabmaster/lib/main.dart`
  - `flutter_vocabmaster/lib/config/app_config.dart`
  - `flutter_vocabmaster/lib/config/backend_config.dart`
- Auth/session:
  - `flutter_vocabmaster/lib/services/auth_service.dart`
  - `flutter_vocabmaster/lib/services/api_service.dart`
  - `flutter_vocabmaster/lib/providers/app_state_provider.dart`
- Subscription:
  - `flutter_vocabmaster/lib/services/subscription_service.dart`
  - `flutter_vocabmaster/lib/screens/subscription_page.dart`
- Theme/UI:
  - `flutter_vocabmaster/lib/theme/app_theme.dart`
  - `flutter_vocabmaster/lib/theme/theme_catalog.dart`
  - `flutter_vocabmaster/lib/theme/theme_provider.dart`
  - `flutter_vocabmaster/lib/widgets/modern_background.dart`
  - `flutter_vocabmaster/lib/widgets/modern_card.dart`
- Practice:
  - `flutter_vocabmaster/lib/screens/practice_page.dart`
  - reading, writing, speaking, translation, neural game, Word Galaxy screens.

## Current Product Policy

- Flutter login is Google-only. Email/password backend endpoints remain gated by prod config and should not be exposed in the app UI.
- Logout is available from the account/profile settings surface, not as a primary onboarding action.
- Free users can add words and sentences.
- Free users receive daily platform content such as daily words and cached daily reading/writing/exam content.
- AI-powered practice consumes quota.
- Current prod config gives all FREE users a small daily AI quota, not zero.
- Paid tiers receive larger daily token quotas.

## Current AI Routing

- Utility/default model: `openai/gpt-oss-20b`.
- Speech/quality model: `openai/gpt-oss-120b` (changed 2026-07-08 from
  `llama-3.3-70b-versatile`: better quality, ~4x cheaper input, and eligible
  for Groq's prompt-caching discount on growing conversation history).
- Speech scopes include speaking generation and evaluation.
- Backend contains degrade-safe handling for malformed JSON from Groq in several flows. Do not remove fallback paths without replacing their tests.

## Database Notes

Latest observed migrations:

- `V016__add_ai_plan_code_to_users.sql`
- `V017__add_trial_eligible_to_users.sql`
- `V018__create_support_tickets.sql`
- `V019__create_device_push_tokens.sql`
- `V020__add_daily_reminder_preference_to_device_push_tokens.sql`
- `V021__align_subscription_plan_metadata.sql`
- `V022__normalize_subscription_plan_display_metadata.sql`
- `V023__align_free_plan_ai_token_metadata.sql`
- `V024__notification_preferences_and_delivery_log.sql`

High-traffic relationships:

- `words.user_id -> users.id`
- `sentences.word_id -> words.id`
- `word_reviews.word_id -> words.id`
- `refresh_token_sessions.user_id -> users.id`
- `payment_transactions.user_id -> users.id`
- `payment_transactions.plan_id -> subscription_plans.id`

Before production schema-sensitive changes, verify Flyway parity on the VPS or target environment.

## Daily Streak Crediting (2026-07-09)

- `ProgressService.updateStreak(userId)` is the server source of truth for
  `UserProgress.currentStreak` (idempotent per calendar day, server
  `LocalDate.now()` — no per-user timezone yet, a known limitation).
- It used to be called from exactly two places: `SRSService.submitReview`
  and `WordService.addWord`. A user who only did reading, writing, speaking
  chat, translation practice, or pronunciation practice on a given day never
  touched it and could lose their streak despite genuinely practicing.
- Fixed by hooking it into `ChatbotController.consumeAiTokens(...)`, the
  single shared method every successful AI practice action already calls
  (sentence generation, translation check, chat, speech transcription,
  speaking generate/evaluate, dictionary x4, reading generation,
  writing topic/evaluate, exam generation, pronunciation text generation —
  see the method's call sites for the full list). Decoupled from AI token
  quota bookkeeping (credits even if `AiTokenQuotaService` is absent) and
  best-effort (a streak-update failure never breaks the API response).
- **Known gap, not yet covered:** `GrammarController` does not go through
  `ChatbotController` and has no equivalent call — a grammar-check-only day
  still does not credit the streak. Left out of this pass since
  `GrammarController` also does not consume the token quota at all
  (pre-existing, separate gap); revisit together.

## TTS Endpoint Posture (2026-07-08)

- `/api/tts/synthesize` is protected: text-length cap
  (`app.tts.max-text-length`, default 400 chars), request rate limiting via
  the shared `AiRateLimitService` under scope `tts-synthesize` (subject =
  optional `X-User-Id` header, else client IP), and a deterministic
  (model,text)-keyed disk audio cache
  (`app.tts.cache-enabled`/`cache-dir`/`cache-max-entries`) so identical
  short phrases are synthesized once per container lifetime.
- Historical note: prod `enforce-auth=true` means `/api/tts` requires a JWT,
  but the Flutter client historically sent no auth headers, so backend TTS
  silently returned 401 in production and users only ever heard the on-device
  `flutter_tts` fallback. The client now sends `Authorization`/`X-User-Id`
  when a session exists; this takes effect with the next Play release.
- `POST /api/progress/award-xp` is unconditionally ADMIN-only with a 1..1000
  clamp; legitimate user XP flows only through server-computed paths (SRS
  reviews, words, sentences, achievements).

## Release Risk Register

- Google Play subscription restore/purchase flow is the current highest priority.
- 2026-05-24 production diagnosis: backend is healthy after redeploy, Flyway is at `V023`, FREE plan metadata says 1500 daily AI tokens, but the affected account has no active local subscription and no completed Google IAP transaction row.
- Google Play product catalog and track/tester alignment must match Flutter product IDs.
- Runtime env may differ from repo defaults. Always check effective prod env before assuming quota or billing behavior.
- Trial-abuse protection should restrict trial/free advantages, not basic Google login. Current default is 4 trial grants per IP per 24 hours.
- RTDN push-event ingestion foundation exists and is disabled by default; Play Console Pub/Sub wiring and prod env enablement remain rollout tasks.
- FCM push notification foundation exists and Firebase Admin delivery is enabled in production. Scheduled daily reminders remain disabled until preference UI and fresh-device smoke checks pass.
- Google Sign-In release parity depends on Firebase/Google OAuth fingerprints for Play-distributed builds.
- Secrets were previously exposed in session history; keep provider rotation and artifact hygiene in mind.

## Verification Strategy

- For backend behavior, prefer targeted JUnit tests around the touched controller/service first.
- For Flutter behavior, prefer targeted service/unit tests and `flutter analyze` on touched files.
- For billing, code tests are not enough. Also verify Play Console product activation, tester track, service-account permissions, and a real purchase/restore token path.

## Production Backend Deploy

Use the versioned deploy helper instead of retyping the VPS steps by hand:

```powershell
pwsh -File scripts/check-backend-vps-deploy-target.ps1
pwsh -File scripts/deploy-backend-vps.ps1 -Label <short-change-label>
```

The default mode is a dry run and only prints the plan. Before the first real
scripted deploy, run the read-only target check:

```powershell
pwsh -File scripts/check-backend-vps-deploy-target.ps1 -Execute
```

This verifies the remote compose service, build context, backend source shape,
container name, and internal health without changing files.

To actually deploy after local tests pass:

```powershell
pwsh -File scripts/deploy-backend-vps.ps1 -Label <short-change-label> -NoCache -Execute
```

What the script does:

- packages `backend/` source while excluding local caches, build output, and
  test logs
- uploads the archive to `/opt/vocabmaster/uploads`
- backs up the current remote backend source under
  `/opt/vocabmaster/backups/deploy`
- replaces the remote backend source
- rebuilds and recreates only the backend service from
  `/opt/vocabmaster/deploy/docker-compose.app.yml`
- waits for `vocabmaster-backend` to become healthy
- runs public `/actuator/health` smoke unless `-SkipPublicSmoke` is passed

Current production compose build context is:

```text
/opt/vocabmaster/backend-src/backend
```

If the remote backend source path differs from that default, pass
`-RemoteBackendPath`.
