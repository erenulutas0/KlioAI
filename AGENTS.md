# AGENTS.md

Last audit: 2026-04-16 (UTC)  
Workspace: `C:\flutter-project-main`

## Session Checkpoint (2026-02-18 EOD)

- State: release-prep green, prod rollout'a yakin.
- Gates: `verify-rollout.ps1` nonprod/prod preflight PASS.
- Neural game: implemented + tested (`bloc`, `page smoke`, `results persistence`).
- Google Play: live verify path implemented, dry-run tooling ready (`scripts/smoke-google-play-live-verify.ps1`).
- Daily exam pack fallback hardening applied:
  - `DailyExamPackService` now normalizes malformed/partial AI JSON into a stable 5-topic x 5-question payload.
  - deterministic fallback packs are persisted to `daily_content`, so same-day scheduler retries no longer fall back to one duplicated weak question.
- Auth surface simplification + trial abuse hardening applied:
  - Facebook login button removed from the Flutter login surface; auth entry is now email + Google only.
  - Flutter auth and refresh requests now carry stable install `deviceId` via body + `X-Device-Id`.
  - backend now persists `users.trial_eligible` and evaluates fresh-account trial grants through `TrialAbuseProtectionService` (device/IP heuristic gate).
  - Flutter practice fallback now respects `trialEligible=false`, so blocked accounts do not regain AI access from `createdAt < 7 days` alone.
- Open blockers before production cut:
  - staging/prod `V017` migration verification
  - RTDN webhook + refund/cancel event ingestion (scheduled reconciliation foundation is now implemented)

This file is the working runbook for Codex sessions on this repo.

Read order on every session:
1. `AGENTS.md`
2. `TODO.md`

Session update rule:
1. Update `TODO.md` after each meaningful task state change.
2. Update `AGENTS.md` when architecture/schema/infra or release risk changes.
3. Before ending a session, both files must match real state.

## 1) Product and stack

- Product: AI-powered English learning app.
- Backend: Spring Boot 3.4.5, Java 17, Maven, Flyway, JPA/Hibernate.
- DB: PostgreSQL 15 (`EnglishApp`).
- Cache/rate limits/quota: Redis 7 (`redis` + `redis-security`).
- Frontend: Flutter.
- Observability: Prometheus + Grafana + Alertmanager.

Primary config files:
- `backend/src/main/resources/application.properties`
- `backend/src/main/resources/application-docker.properties`
- `backend/src/main/resources/application-prod.properties`

## 2) Current AI business policy (implemented)

Source of truth:
- `backend/src/main/java/com/ingilizce/calismaapp/service/AiEntitlementService.java`
- `backend/src/main/java/com/ingilizce/calismaapp/service/AiPlanTier.java`
- `backend/src/main/java/com/ingilizce/calismaapp/service/AiTokenQuotaService.java`

Policy:
- New users: `FREE_TRIAL_7D` -> `25000` token/day.
- Trial end: `FREE` -> AI disabled (`0` token/day).
- Paid plan `PREMIUM` -> `50000` token/day.
- Paid plan `PREMIUM_PLUS` -> `100000` token/day.

Entitlement metadata is exposed by:
- `GET /api/chatbot/quota/status`
- payload includes `planCode`, `trialActive`, `trialDaysRemaining`, `aiAccessEnabled`.
- AI endpoint guard behavior:
  - quota exhausted -> `429`
  - AI access disabled (post-trial FREE) -> `403` with `reason=ai-access-disabled` and `upgradeRequired=true`

Flutter paywall handling (implemented):
- API layer maps `403 + upgradeRequired` to `ApiUpgradeRequiredException`.
- Shared handler routes to subscription screen:
  - `flutter_vocabmaster/lib/services/ai_paywall_handler.dart`
- Wired screens:
  - `ai_bot_chat_page.dart`
  - `exam_chat_page.dart`
  - `dictionary_page.dart`
  - `quick_dictionary_page.dart`
  - `translation_practice_page.dart`
  - `reading_practice_page.dart`
  - `writing_practice_page.dart`
- Subscription purchase flow now mobile-IAP only (no iyzico web fallback).

## 3) Model routing policy (implemented)

Source of truth:
- `backend/src/main/java/com/ingilizce/calismaapp/config/AiModelRoutingProperties.java`
- `backend/src/main/java/com/ingilizce/calismaapp/service/AiModelRoutingService.java`

Default routing:
- Speech-critical scopes -> `llama-3.3-70b-versatile`
  - `chat`
  - `speaking-generate`
  - `speaking-evaluate`
- Utility scopes -> `openai/gpt-oss-20b`
  - dictionary/grammar/reading/writing/exam/sentence generation flows unless mapped as speech.

Runtime config keys:
- `APP_AI_MODEL_ROUTING_ENABLED`
- `APP_AI_MODEL_ROUTING_SPEECH_MODEL`
- `APP_AI_MODEL_ROUTING_UTILITY_MODEL`
- `APP_AI_MODEL_ROUTING_SPEECH_SCOPES`

## 3.5) Google Play verification path

Source of truth:
- `backend/src/main/java/com/ingilizce/calismaapp/config/GooglePlaySubscriptionProperties.java`
- `backend/src/main/java/com/ingilizce/calismaapp/config/GooglePlaySubscriptionReconciliationProperties.java`
- `backend/src/main/java/com/ingilizce/calismaapp/service/GooglePlaySubscriptionVerificationService.java`
- `backend/src/main/java/com/ingilizce/calismaapp/service/GooglePlaySubscriptionReconciliationService.java`
- `backend/src/main/java/com/ingilizce/calismaapp/controller/SubscriptionController.java`

Behavior:
- If `app.subscription.mock-verification-enabled=true`: legacy mock verify flow remains.
- If mock is disabled: backend verifies purchase token with Google Android Publisher API.
- Product/base-plan keys are mapped to internal plans via `app.subscription.google-play.product-plan-map`.
- On successful verify:
  - user subscription end is updated (Google expiry preferred),
  - `ai_plan_code` is updated from resolved plan,
  - `payment_transactions` is written/updated with provider `GOOGLE_IAP`.
- Scheduled lifecycle reconciliation is available via:
  - `app.subscription.google-play.reconciliation.enabled`
  - `app.subscription.google-play.reconciliation.cron`
  - `app.subscription.google-play.reconciliation.max-users-per-run`
- Reconciliation checks latest Google IAP transaction per user against Android Publisher state and syncs local entitlement for cancel/revoke/expire drift.

## 3.6) Flutter localization and language gating (in progress)

Source of truth:
- `flutter_vocabmaster/lib/l10n/app_localizations.dart`
- `flutter_vocabmaster/lib/providers/language_provider.dart`
- `flutter_vocabmaster/lib/screens/language_selection_page.dart`
- `flutter_vocabmaster/lib/screens/settings_page.dart`
- `flutter_vocabmaster/lib/main.dart`
- `flutter_vocabmaster/lib/widgets/navigation_menu_panel.dart`

Behavior:
- First app open now enforces language selection before auth routing (`LanguageSelectionPage`).
- Supported UI languages: `en`, `de`, `tr`, `ar`, `zh`.
- Device locale is used as initial recommendation (industry-standard behavior); user choice is persistent.
- Persisted keys:
  - `app_language_code`
  - `app_language_selected`
  - `app_language_prompt_seen`
- `MaterialApp` now uses explicit `locale`, delegates, and `supportedLocales`.
- In-app language switching is available from drawer menu (`language` item -> picker bottom sheet) and dedicated `SettingsPage`.
- Localization coverage completed for startup/auth shell + navigation + practice shell; full-screen text migration is still ongoing.

## 4) DB schema and relationships

Migration folder:
- `backend/src/main/resources/db/migration`

Latest repo migration:
- `V017__add_trial_eligible_to_users.sql`

New schema element:
- `users.ai_plan_code` (default `FREE`).
- `users.trial_eligible` (default `true`).

Behavior in migration:
- Adds `ai_plan_code` column.
- Backfills active subscribers to `PREMIUM`.

Core FK map (high-traffic domain):
- `words.user_id -> users.id`
- `sentences.word_id -> words.id`
- `word_reviews.word_id -> words.id`
- `sentence_practices.user_id -> users.id`
- `user_progress.user_id -> users.id`
- `refresh_token_sessions.user_id -> users.id`
- `payment_transactions.user_id -> users.id`
- `payment_transactions.plan_id -> subscription_plans.id`

Note:
- Local running container DB was previously verified at `V016` on 2026-02-17.
- `V017` is now required for the trial-eligibility path; staging/prod migration parity still needs explicit verification before release cut.
- Still verify staging/prod DB migration state separately before release cut.

## 5) Redis architecture

Main redis:
- host alias: `app-redis-main`
- usage: app cache, leaderboard, non-security data.

Security redis:
- host alias: `app-redis-security`
- usage: auth rate-limit, AI rate-limit, token quota counters.

Key patterns:
- Trial abuse protection:
  - `auth:trial:device:{deviceId}`
  - `auth:trial:ip:{ip}`
- Token quota:
  - `ai:tokens:day:{yyyy-mm-dd}:{userId}`
  - `ai:tokens:day:scope:{yyyy-mm-dd}:{scope}:{userId}`
- AI rate limit:
  - `ai:rl:user:{scope}:{userId}`
  - `ai:rl:ip:{scope}:{ip}`
  - `ai:rl:penalty:ban:{subject}`
  - `ai:rl:penalty:strike:{subject}`
- Auth rate limit:
  - `auth:rl:cnt:{domainKey}`
  - `auth:rl:block:{domainKey}`

## 6) Release readiness and critical issues

Current verification:
- Primary VPS baseline provisioning (2026-03-30):
  - clean Ubuntu 24.04 host prepared for production runtime.
  - Docker + Docker Compose v2 installed and enabled.
  - `ufw` active with inbound allowlist limited to `22/80/443`; temporary app exposure additionally allows `8082/tcp` until reverse proxy is added.
  - `fail2ban` active for `sshd`.
  - temporary single-host PostgreSQL container is running healthy on `127.0.0.1:5432` only:
    - compose: `/opt/vocabmaster/deploy/docker-compose.postgres.yml`
    - DB: `EnglishApp`
    - app role: `englishapp`
  - daily logical backup cron added on host:
    - script: `/opt/vocabmaster/backups/backup-postgres.sh`
    - cron file: `/etc/cron.d/vocabmaster-postgres-backup`
  - primary app runtime is now also deployed on the same VPS:
    - compose: `/opt/vocabmaster/deploy/docker-compose.app.yml`
    - service env split:
      - `/opt/vocabmaster/secrets/backend.env`
      - `/opt/vocabmaster/secrets/redis.env`
      - `/opt/vocabmaster/secrets/redis-security.env`
    - backend is healthy on `http://84.46.251.95:8082`
    - redis + redis-security are healthy
    - `/actuator/health` returns `200` + `UP`
  - deploy incidents resolved:
    - first-pass remote `POSTGRES_APP_PASSWORD` was empty, causing Flyway SCRAM auth failure until rotated and synced
    - Compose `$VAR` interpolation initially blanked Redis runtime passwords; fixed with `$$VAR` escaping and service-specific env files
    - prod strict CORS validation rejected loopback origins copied from local `.env`; temporary host CORS origin is now `http://84.46.251.95:8082`
    - Redis warning about memory overcommit was resolved with persistent `vm.overcommit_memory=1`
  - reverse proxy layer added on the same VPS:
    - compose: `/opt/vocabmaster/deploy/docker-compose.proxy.yml`
    - Caddy config: `/opt/vocabmaster/caddy/Caddyfile`
    - public app entrypoint is now `http://84.46.251.95`
    - Caddy reverse proxy to `vocabmaster-backend:8082` verified with `200 UP` on `/actuator/health`
    - public `8082/tcp` firewall exposure removed after proxy cutover
    - temporary prod CORS origin is now `http://84.46.251.95` until final HTTPS domain is available
  - SSH access hardening progress:
    - user-provided ED25519 public key was added to `/root/.ssh/authorized_keys`
    - password login is still intentionally enabled until key-based access is validated from the user side
  - domain cutover progress (2026-03-31):
    - `api.klioai.app` is now configured on Caddy and automatic Let's Encrypt issuance succeeded
    - HTTP on `api.klioai.app` redirects to HTTPS
    - `https://api.klioai.app/actuator/health` returns `200` + `UP`
    - backend prod CORS origin list is now domain-based:
      - `https://klioai.app`
      - `https://api.klioai.app`
    - apex domain `klioai.app` is now resolvable and also has automatic Let's Encrypt TLS
    - routing behavior:
      - `http://klioai.app` -> `308` to `https://klioai.app`
      - `https://klioai.app` -> `301` to `https://api.klioai.app`
    - current temporary public posture:
      - backend lives at `https://api.klioai.app`
      - apex now serves a real static landing page on `https://klioai.app`
  - post-domain hardening (2026-04-01):
    - Flutter non-debug default backend is now `https://api.klioai.app` when no explicit `BACKEND_URL` is provided
    - Flutter no longer bundles `.env` as an asset; release builds should not ship local env contents
    - `GroqApiClient` embedded `.env` key path is disabled in release builds
    - Android main manifest now has `usesCleartextTraffic=false`; debug manifest keeps cleartext enabled for local development only
    - backend host port publish was removed from app compose; backend is now internal-only (`8082/tcp` on Docker network, no host binding)
    - `APP_SECURITY_JWT_SECRET` was rotated on VPS runtime env files; existing JWT sessions are invalidated
    - Docker log rotation added to app/proxy/postgres services
    - basic runtime smoke check added on host:
      - script: `/opt/vocabmaster/deploy/runtime-smoke.sh`
      - cron: `/etc/cron.d/vocabmaster-runtime-smoke` (every 5 minutes)
      - logrotate: `/etc/logrotate.d/vocabmaster-runtime-smoke`
    - backup restore smoke succeeded from generated dump:
      - restored dump into temp DB and verified `flyway_schema_history=17`, `users=1`
  - landing page rollout (2026-04-01):
    - static site source added under:
      - `site/klioai-landing/index.html`
      - `site/klioai-landing/styles.css`
    - deployed static files on VPS to:
      - `/opt/vocabmaster/frontend/klioai-site`
    - Caddy apex host (`klioai.app`) now serves the landing page directly over HTTPS
    - API host remains unchanged:
      - `https://api.klioai.app`
  - public legal pages added (2026-04-01):
    - static pages:
      - `site/klioai-landing/privacy.html`
      - `site/klioai-landing/terms.html`
    - deployed and verified:
      - `https://klioai.app/privacy.html`
      - `https://klioai.app/terms.html`
  - runtime and security recheck (2026-04-04):
    - direct SSH validation confirmed all runtime containers are still healthy:
      - `vocabmaster-caddy`
      - `vocabmaster-backend`
      - `vocabmaster-redis`
      - `vocabmaster-redis-security`
      - `vocabmaster-postgres`
    - on-host runtime smoke re-run PASS
    - PostgreSQL still accepts connections and current counts remain:
      - `flyway_schema_history=17`
      - `users=1`
    - Redis auth revalidated against live container envs:
      - main redis -> `PONG`
      - security redis -> `PONG`
    - public checks remain healthy:
      - `https://api.klioai.app/actuator/health` -> `200`
      - protected AI probe without JWT -> expected `401`
    - VPS file-permission hardening applied:
      - `/opt/vocabmaster/secrets` -> `700`
      - `/opt/vocabmaster/caddy` -> `700`
      - `/opt/vocabmaster/backups` -> `700`
      - `/opt/vocabmaster/backups/backup-postgres.sh` -> `700`
    - diagnostic conclusion:
      - current production issue is not backend/Postgres/Redis reachability
      - remaining AI instability is more likely app-session/auth related (stale JWT after 2026-04-01 secret rotation) and/or Groq JSON generation failures in `DailyExamPackService`
  - auth diagnostic hardening (2026-04-04):
    - device-side login failure referencing `sanda-sheathiest-uncredulously.ngrok-free.dev` indicates at least one installed app build was still targeting an old ngrok endpoint
    - current repo config does not persist custom backend URLs in storage; likely source is stale build-time `BACKEND_URL` injection, not live server config
    - Flutter auth layer now handles non-JSON backend responses more explicitly:
      - `auth_service.dart` login/register/google-login parse failures now include URL/body context
      - `google_login_error_message_formatter.dart` now recognizes stale offline ngrok responses and tells the user to install a fresh build targeting `https://api.klioai.app`
  - release dotenv safety fix (2026-04-04):
    - direct `dotenv.env` access could still throw `NotInitializedError` in release because `.env` is intentionally no longer bundled
    - added `flutter_vocabmaster/lib/config/dotenv_safe.dart`
    - `app_config.dart`, `backend_config.dart`, `auth_service.dart`, and `groq_api_client.dart` now use safe dotenv fallback access so release builds can boot without `.env`
  - Google Play service-account permission fix (2026-04-04):
    - backend container runs as non-root `spring:spring` (`uid/gid=999`)
    - bind-mounted `/run/secrets/google-play-service-account.json` inherited host mode `600 root:root`, which caused `/api/subscription/verify/google` to fail with `MISCONFIGURED: Unable to read Google service account file`
    - fixed by changing host file mode to `644` on:
      - `/opt/vocabmaster/secrets/google-play-service-account.json`
    - backend restart + container check confirmed the mounted file is now readable and `APP_SUBSCRIPTION_GOOGLE_PLAY_SERVICE_ACCOUNT_FILE` remains `/run/secrets/google-play-service-account.json`
  - subscription sync/app-state fix (2026-04-04):
    - production user `eerenulutass@gmail.com` currently exists as `user_id=3` with:
      - `subscription_end_date = NULL`
      - `ai_plan_code = FREE`
      - no `payment_transactions` row yet
    - observed symptom:
      - Play purchase flow can return `itemAlreadyOwned` while backend/app entitlement remains unsynced
    - Flutter fixes applied:
      - `AuthService.refreshProfile()` now pulls `/api/users/{id}` instead of returning cached local data
      - `SubscriptionPage` refreshes profile + `AppStateProvider` after subscription status becomes active
      - `PracticePage` no longer unlocks/locks based on naive non-null `subscriptionEndDate`; it now checks a real active expiry
  - practice entitlement gate alignment (2026-04-04):
    - `PracticePage` had still been treating paid subscription state as the main unlock signal, which conflicted with the backend entitlement policy for `FREE_TRIAL_7D`
    - `AppStateProvider` now pulls `/api/chatbot/quota/status` while refreshing user data and merges:
      - `aiAccessEnabled`
      - `planCode`
      - `trialActive`
      - quota snapshot fields
      into cached `userInfo`
    - practice unlock/overlay decisions now follow AI entitlement first, so users with active free-tier AI access are no longer shown a false PRO paywall
    - additional defensive fallback now exists when quota snapshot has not landed yet:
      - allow access from `trialDaysRemaining`
      - allow access from `isSubscriptionActive`
      - infer early trial from `createdAt < 7 days`
    - `PracticePage` also triggers a one-shot entitlement refresh on entry if no snapshot is cached yet
    - final UX simplification:
      - `PracticePage` no longer shows a page-level or card-level subscription lock
      - rationale: free-tier AI users must be able to open practice; backend AI endpoints already enforce paywall/quota rules when real access is denied
  - store ownership/account-switch sync hardening (2026-04-04):
    - subscription page now performs a silent restore/sync attempt on open for non-active accounts
    - `itemAlreadyOwned` messaging now routes to account-sync language instead of surfacing a raw already-owned error
    - goal: reduce false-negative subscription UX when a Play account already owns the product but the current app account has not yet been re-linked
  - subscription restore lazy-proxy fix (2026-04-05):
    - repeated Google verify on an existing purchase token had a backend failure path:
      - `PaymentTransactionRepository.findByTransactionId(...)` returned a tx with lazy `plan`
      - `SubscriptionController.verifyGooglePurchase(...)` then accessed `tx.getPlan().getName()` outside an active session
      - symptom on device: `Dogrulama hatasi: could not initialize proxy [SubscriptionPlan#...] - no Session`
    - fix:
      - verify flow now uses `findByTransactionIdWithUserAndPlan(...)`
      - already-verified purchase tokens can be rebound to the currently signed-in app user during restore/account switching
    - `UserController.getUserProfile(...)` now returns a flat map instead of raw JPA `User`
    - Flutter subscription status checks now use `/api/users/{id}/subscription/status` rather than the raw profile endpoint
  - production data reset (2026-04-04):
    - full backup created before wipe:
      - `/opt/vocabmaster/backups/pre-nuke/EnglishApp_pre_nuke_20260404T180918Z.dump`
    - truncated/reset user-generated tables and flushed both Redis instances for a clean restart
    - retained reference/schema tables only:
      - `flyway_schema_history`
      - `subscription_plans`
      - `badges`
    - post-reset counts:
      - `users=0`
      - `words=0`
      - `sentences=0`
      - `payment_transactions=0`
      - `refresh_token_sessions=0`
      - `daily_content=0`
      - `subscription_plans=5`
      - `badges=14`
    - host runtime smoke remained PASS after cleanup
  - current infra posture is acceptable for early production bootstrap, but long-term target remains dedicated DB host separation.
- Runtime incident recheck (2026-03-04):
  - backend container was running but repeatedly failed startup with `UnknownHostException: postgres` because `postgres`/`redis`/`redis-security` services were down (`Exited (255)`).
  - recovered by restarting dependency services (`docker compose up -d postgres redis redis-security backend`).
  - post-recovery checks PASS:
    - `docker compose ps` -> backend/postgres/redis/redis-security all `healthy`.
    - `/actuator/health` -> `200` + `UP`.
    - smoke probe (`/api/chatbot/dictionary/lookup-detailed`) -> `HTTP 200`.
- Uptime hardening (2026-03-04):
  - added `restart: unless-stopped` to `postgres`, `redis`, and `redis-security` in `docker-compose.yml` to reduce repeat outage risk after Docker daemon restarts.
- Security header parity hardening (2026-03-04):
  - docker profile now enables `app.security.headers.*` defaults (`application-docker.properties`), so runtime emits `Referrer-Policy`, `Permissions-Policy`, `Content-Security-Policy`, and HSTS when `X-Forwarded-Proto=https`.
  - `scripts/smoke-security-cors-headers.ps1` now uses PowerShell 7-safe `Invoke-WebRequest -SkipHttpErrorCheck`.
  - `verify-rollout.ps1` now passes explicit disallowed origin (`http://evil.example.com`) when running security smoke with `SecuritySmokeAllowedOrigin`.
  - recheck PASS:
    - `pwsh -File scripts/smoke-security-cors-headers.ps1 -BaseUrl http://localhost:8082 -AllowedOrigin http://localhost:8080 -DisallowedOrigin http://evil.example.com`
    - `pwsh -File scripts/verify-rollout.ps1 -Mode nonprod-smoke -ProjectName flutter-project-main -SecuritySmokeAllowedOrigin http://localhost:8080`
- Flutter regression/test recheck (2026-03-04):
  - fixed responsive overflow in `WordOfTheDayModal` header and completion row.
  - updated widget tests to localization-aware assertions (`daily_word_card_test.dart`, `word_of_the_day_modal_test.dart`).
  - full Flutter suite PASS: `flutter test -r compact`.
  - backend full suite recheck PASS: `mvn -q "-Dmaven.repo.local=C:\\flutter-project-main\\backend\\.m2-repo" test` (`578 tests, 0 failures`).
- TesterCommunity triage (2026-03-17):
  - Google Sign-In external-test failure is now treated as a release blocker until Firebase/Google OAuth fingerprints are corrected.
  - repo upload keystore SHA-1 does not match the Android OAuth client fingerprint currently bundled in `flutter_vocabmaster/android/app/google-services.json`.
  - likely impact: local/debug sign-in can appear healthy while Play-distributed/internal-test builds fail with native Google Sign-In developer error (`ApiException: 10`).
  - code-side mitigation shipped:
    - clearer Google login failure messaging with email-login fallback hint,
    - first-run app tour now active from splash,
    - app tour replay available from settings.
- Google Sign-In closed-test recheck (2026-03-18):
  - local repo verification confirmed the exact mismatch:
    - upload keystore SHA-1 = `DD:C9:FB:90:3C:F4:BF:D0:E7:E6:E6:88:C5:23:0F:D1:6A:37:A4:D7`
    - bundled `google-services.json` Android OAuth SHA-1 = `5D:5F:25:F4:73:C0:3F:AB:6B:98:57:BC:A9:80:50:17:68:B6:20:82`
  - new guard script added:
    - `scripts/check-google-signin-android-config.ps1`
  - `verify-rollout.ps1 -Mode local-gate` now runs the Google Sign-In Android config check before backend/test gates.
- Closed-test auth networking finding (2026-03-18):
  - Flutter release app was still loading bundled `.env` with `BACKEND_URL=http://192.168.1.102:8082`, causing tester devices outside the local network to time out on `/api/auth/register`.
  - `flutter_vocabmaster/lib/config/app_config.dart` now prefers `--dart-define` overrides for `BACKEND_URL`/host config before `.env`, so release builds can target public/staging backend safely.
- Auth URL validation hardening (2026-03-19):
  - Flutter config layer now validates backend root URLs before composing auth/API requests.
  - invalid `BACKEND_URL` values now fail fast when they contain whitespace, malformed host content, unsupported scheme, or accidental extra path/query/fragment content.
  - reported bad-shape symptom included auth URL composition with `exit_with_errorlevel.bat`; this is now treated as invalid config instead of being passed into request URI construction.
- Cross-account session isolation fix (2026-03-21):
  - Flutter `AppStateProvider` now clears session-scoped in-memory state on account switch/logout before hydrating the next signed-in user.
  - this prevents previous account words/xp/streak/profile-derived stats from leaking into the next account on the same device session.
  - logout paths now explicitly clear provider state before auth/local cache teardown.
- Auth refresh incident fix (2026-03-18):
  - backend `POST /api/auth/refresh` could throw `LazyInitializationException` while issuing the next access token from a detached `RefreshTokenSession.user` proxy.
  - downstream effect: refresh request returned `500`, client retried with the now-rotated old token, and backend escalated to `REUSE_DETECTED`, revoking the session chain.
  - fix shipped: `AuthController.refresh` now reloads the user from `UserRepository` before calling `JwtTokenService.issueAccessToken(...)`.
- Security attack probe recheck (2026-03-04) PASS:
  - unauthorized quota `401`, spoofed user header `403`, tampered JWT `401`, SQLi login payload `401`, brute-force throttling `...401,401,429,429`, non-admin admin endpoint access `403`.
- `mvn -q test` PASS (2026-02-17).
- Backend rebuilt from latest workspace (`docker compose up -d --build backend`).
- Flyway runtime check PASS with `V016`.
- `verify-rollout.ps1 -Mode nonprod-smoke` PASS after rebuild.
- Free-launch preflight (`-SkipPaymentChecks -SkipAlertmanagerChecks`) PASS after rebuild.
- Google live-mode controller tests PASS (`SubscriptionControllerGoogleLiveModeTest`).
- Full suite + rollout gates rechecked PASS after Google verify + paywall response hardening.
- `scripts/check-runtime-prod-flags.ps1` now also guards Flutter release safety:
  - verifies subscription demo flag default is `false`,
  - scans workflow/script files for `SUBSCRIPTION_DEMO_MODE=true`.
- Runtime prod guard re-run with Docker access PASS (post guard hardening).
- `verify-rollout.ps1` re-run PASS:
  - `nonprod-smoke`
  - `prod-preflight -SkipPaymentChecks -SkipAlertmanagerChecks`
- Full `prod-preflight` (skip olmadan) validated with complete env set:
  - First run surfaced missing vars: `ALERTMANAGER_*`, `APP_SECURITY_AUTH_GOOGLE_CLIENT_IDS`.
  - Re-run with all required vars present -> PASS.
- Flutter API contract test PASS:
  - `flutter test test/api_service_contract_test.dart`
- Entitlement/paywall backend test set PASS:
  - `mvn -q "-Dtest=AiEntitlementServiceTest,ChatbotControllerTest,SubscriptionControllerGoogleLiveModeTest" test`
- Iyzico is no longer required for production preflight/composition:
  - `docker-compose.prod.yml` no longer requires `IYZICO_*`.
  - `validate-prod-alert-routing.ps1` no longer blocks on payment env vars.
  - compose overlay validation is now relaxed only when `SkipAlertmanagerChecks` is set.
- Local `.env` now has `ALERTMANAGER_*` set.
- Local `.env` now has Google Play package + service-account host-path configured and host file present.
- Full `prod-preflight` passes with Google Play settings enabled.
- Critical paywall consistency fix applied in `ChatbotController`:
  - AI endpoints now pass through shared `enforceAiAccess(...)` gate.
  - Post-trial FREE users now consistently receive `403` with `reason=ai-access-disabled` and `upgradeRequired=true`.
  - Cache-hit path (`generate-sentences`) and grammar endpoint are also covered.
- New E2E smoke script added and validated:
  - `scripts/smoke-ai-entitlement-flow.ps1`
  - verifies full flow: `FREE_TRIAL_7D (25k)` -> forced trial expiry -> paywall -> `PREMIUM (50k)` -> `PREMIUM_PLUS (100k)`.
- `verify-rollout.ps1 -Mode nonprod-smoke` now includes `ai-entitlement-smoke` step and passed.
- Re-validated rollout gates after backend rebuild:
  - `verify-rollout.ps1 -Mode nonprod-smoke -ProjectName flutter-project-main` PASS
  - `verify-rollout.ps1 -Mode prod-preflight -ProjectName flutter-project-main` PASS
- Flutter Neural game module added and validated:
  - New dependencies resolved: `flutter_bloc`, `equatable`.
  - New module analyze PASS (`flutter analyze` on neural files).
  - Integration point: `PracticePage` now has `Neural Oyun` tab and opens `NeuralGamePage`.
  - Automated tests added and passing:
    - `flutter_vocabmaster/test/unit/neural_game_bloc_test.dart`
    - `flutter_vocabmaster/test/neural_game_page_smoke_test.dart`
    - `flutter_vocabmaster/test/neural_game_results_screen_test.dart`
    - `flutter test test/unit/neural_game_bloc_test.dart test/neural_game_page_smoke_test.dart`
    - `flutter test test/neural_game_results_screen_test.dart test/unit/neural_game_bloc_test.dart test/neural_game_page_smoke_test.dart`
    - `flutter analyze test/unit/neural_game_bloc_test.dart test/neural_game_page_smoke_test.dart`
    - `flutter analyze test/neural_game_results_screen_test.dart`
- Runtime/prod checks re-run after latest secret/config updates:
  - `verify-rollout.ps1 -Mode prod-preflight -ProjectName flutter-project-main` PASS
- Google Play live dry-run assets added:
  - `scripts/smoke-google-play-live-verify.ps1`
  - `docs/GOOGLE_PLAY_LIVE_DRY_RUN.md`
- Regression checks re-run:
  - `flutter test test/api_service_contract_test.dart` PASS
  - `mvn -q "-Dtest=AiEntitlementServiceTest,ChatbotControllerTest,SubscriptionControllerGoogleLiveModeTest" test` PASS
- Release gates re-run after neural + Google dry-run tooling updates:
  - `verify-rollout.ps1 -Mode nonprod-smoke -ProjectName flutter-project-main` PASS
  - `verify-rollout.ps1 -Mode prod-preflight -ProjectName flutter-project-main` PASS
  - `security-cors-headers-smoke` step skipped in nonprod mode when `SecuritySmokeAllowedOrigin` is not provided.
- Google Play live verification is now validated end-to-end with a real tester purchase token in local prod-like runtime:
  - first attempts failed with Android Publisher `401 permissionDenied` until Play Console API permissions were corrected for the configured service account.
  - latest verify succeeded (`planName=PREMIUM`, `SUBSCRIPTION_STATE_ACTIVE`) and wrote `GOOGLE_IAP` success transaction.
- Live verify recheck on 2026-02-23 with the latest locally stored token now returns:
  - `HTTP 400`, `code=INVALID_PURCHASE`, `error=Subscription is not active` (token is stale/inactive).
  - quota endpoint still reports active premium entitlement for the user (`planCode=PREMIUM`, `tokenLimit=50000`), so fresh-token dry-run remains required before prod cut.
- `scripts/smoke-google-play-live-verify.ps1` hardened for PowerShell 7 HTTP error handling:
  - now uses `-SkipHttpErrorCheck` and prints HTTP status/body consistently for non-2xx responses.
- Google Play package-name case handling fixed in verifier:
  - backend no longer lowercases package name before Publisher API call (required for package `com.VocabMaster`).
- Base-plan mapping hardening:
  - `monthly` base-plan key is now explicitly mapped via `APP_SUBSCRIPTION_GOOGLE_PLAY_PRODUCT_PLAN_MONTHLY` (default `PREMIUM`).
- Post-reconciliation hardening (2026-02-23):
  - fixed Spring bean constructor wiring for `GooglePlaySubscriptionReconciliationService` (`@Autowired` on primary constructor).
  - targeted Dockerized backend regression set PASS:
    - `mvn -q "-Dtest=GooglePlaySubscriptionReconciliationServiceTest,SubscriptionControllerGoogleLiveModeTest,AiEntitlementServiceTest,ChatbotControllerTest" test`
- Subscription abuse hardening (2026-02-24):
  - `SubscriptionController` now enforces fixed 30-day effective duration for AI tiers (`PREMIUM`, `PREMIUM_PLUS`) regardless of legacy plan duration drift.
  - mock/demo activation flows now return idempotent success when subscription is already active and do not extend end-date on repeated activation attempts.
  - token quota reset behavior remains daily key-based in UTC (`ai:tokens:day:{yyyy-mm-dd}:{userId}`), so repeated activation does not refresh same-day consumed tokens.
- Sentence generation parse resilience hardening in `ChatbotController`:
  - strict JSON parse now has lenient recovery path for malformed/truncated LLM outputs.
  - new regression test added: `generateSentencesRecoversFromTruncatedJsonWithAtLeastOneValidObject`.
- Sentence generation reliability hardening (additional):
  - fallback chain now includes free-text sentence extraction and deterministic fallback sentences when LLM output is empty/unparseable.
  - `generate-sentences` no longer returns `500` for empty/malformed LLM payloads; returns degrade-safe `200`.
- Global JSON-mode resilience hardening (all AI JSON scopes):
  - `GroqService` now auto-fallbacks to response_format-disabled call on `json_validate_failed/response_format` client errors.
  - `AiProxyService` now emits structured degrade-safe fallback JSON for empty/unparseable AI outputs (dictionary/reading/writing/exam scopes) instead of throwing 500.
  - Added tests:
    - `backend/src/test/java/com/ingilizce/calismaapp/service/AiProxyServiceTest.java`
    - `mvn -q "-Dtest=GroqServiceTest,AiProxyServiceTest,ChatbotServiceTest,GrammarCheckServiceTest,ChatbotControllerTest" test` PASS
- Live mini-smoke recheck after rebuild (2026-02-20 UTC):
  - Endpoints `check-translation`, `check-grammar`, `dictionary-lookup-detailed`, `reading-generate`, `writing-generate-topic`, `exam-generate` all returned HTTP 200.
  - `dictionary-lookup-detailed` and `reading-generate` returned `fallback=true` payloads (degrade-safe path active, no hard fail).
- Live mini-smoke recheck after rescue-model hardening deploy (2026-02-20 21:54 UTC):
  - backend rebuilt with latest `AiProxyService` rescue flow (`docker compose up -d --build backend`).
  - `dictionary-lookup-detailed` and `reading-generate` returned HTTP 200 with real content (no `fallback=true` key).
  - logs confirm `json_validate_failed` on `openai/gpt-oss-20b` is recovered via rescue call on `llama-3.3-70b-versatile` (`AI proxy rescue succeeded`).
  - no `AI proxy fallback payload used` log observed in this smoke run.
- Daily content architecture expanded for reading/writing (2026-02-20 UTC):
  - new backend services:
    - `backend/src/main/java/com/ingilizce/calismaapp/service/DailyReadingService.java`
    - `backend/src/main/java/com/ingilizce/calismaapp/service/DailyWritingTopicService.java`
    - `backend/src/main/java/com/ingilizce/calismaapp/service/DailyLevelSupport.java`
  - new API endpoints:
    - `GET /api/content/daily-reading?level=A1..C2`
    - `GET /api/content/daily-writing-topic?level=A1..C2`
  - both endpoints are DB-backed (`daily_content`) and return one daily content per level (same day+level => same payload).
  - scheduler prewarm now covers all CEFR levels for reading + writing in addition to daily words/exam pack.
  - paywall consistency: post-trial FREE users receive `403` with `reason=ai-access-disabled`, `upgradeRequired=true` on new daily endpoints.
  - live smoke verified:
    - same level repeated calls return same daily content (`same=True`),
    - daily writing response now normalizes `level` to requested CEFR level.
- Backend rebuilt/restarted after sentence-generation hotfix (`docker compose up -d --build backend`) and container startup is healthy (2026-02-20).
- Flutter API auth resilience hardening:
  - protected AI calls now auto-refresh JWT access token once on `401` via `/api/auth/refresh`, then retry request.
  - this mitigates user-facing `AI ... basarisiz: 401` after access token expiry (default TTL 900s).
- Secret hygiene hardening:
  - repository `.gitignore` now excludes `secrets/` to reduce accidental credential commits.
  - quick workspace scan shows no hardcoded `gsk_` key and no private-key markers in Flutter source paths.
- Post-checkpoint delivery updates (2026-02-21):
  - `generate-sentences` now supports `fresh=true` request flag:
    - bypasses sentence cache and injects variation seed for non-repeating outputs.
    - Flutter translation practice now calls this fresh mode by default.
  - Global dictionary cache added in `ChatbotController` (Redis):
    - endpoints covered: `dictionary/lookup`, `dictionary/lookup-detailed`, `dictionary/explain`, `dictionary/generate-specific-sentence`.
    - cache key space prefix: `dictionary:*` with TTL `cache.dictionary.ttl` (default 86400s).
  - Reading generation level strictness upgraded:
    - `AiProxyService.generateReadingPassage(...)` now uses CEFR profile keys (`A1..C2`) with distinct C1/C2 constraints.
    - daily reading generation now requests CEFR level directly (not coarse band alias).
  - Flutter daily practice UX hardening:
    - reading/writing daily completion tracking added (user+day+level local keying).
    - reading supports same-day answer review restore (correct/incorrect revisit).
    - practice reading level chips and writing level chips now show completion checkmarks.
  - Neural game V2 implemented:
    - mode selection added (`related words` / `Turkish translation`).
    - alias/synonym acceptance expanded (e.g. `improvement` accepted under `INNOVATION` set).
    - translation mode renders Turkish subtitle on discovered nodes.
  - Neural input acceptance hardening (2026-02-21):
    - token normalization now handles TR chars (`çğışöü` -> ascii) and punctuation trimming.
    - near-match tolerance added (small typo/inflection drift via levenshtein + prefix delta).
    - invalid answer feedback now returns mode-appropriate hints.
  - Reading CEFR differentiation hotfix (2026-02-21):
    - `DailyReadingService` content-type prefix bumped to `daily_reading_v2_` to invalidate same-day stale v1 cache rows.
    - `AiProxyService.generateReadingPassage` prompt now includes strict cross-level differentiation rule (C2 denser than C1).
  - Market gating foundation for global rollout (2026-02-21):
    - new Flutter config service: `flutter_vocabmaster/lib/services/app_market_config.dart`.
    - new build flags:
      - `APP_MARKET=auto|tr|global` (default `auto`, derives from locale when not forced),
      - `APP_ENABLE_EXAMS_GLOBAL=false|true` (default `false`).
    - `PracticePage` now derives visible practice tabs from locale+flags:
      - TR market: `Sınavlar` tab visible (default behavior),
      - global market: `Sınavlar` tab hidden by default.
    - speaking tab exam card (`IELTS & TOEFL`) is now gated by the same market rule.
  - Auth refresh-race hardening (2026-02-21):
    - `flutter_vocabmaster/lib/services/api_service.dart` now serializes refresh-token rotation via static in-flight lock (`_refreshInFlight`).
    - this prevents parallel 401 retries from issuing multiple `/api/auth/refresh` calls with the same refresh token.
    - backend root-cause confirmed in runtime logs: `Refresh token reuse detected` for tester user (id=4).
  - Profile subscription access UX update (2026-02-21):
    - `flutter_vocabmaster/lib/screens/profile_page.dart` now shows `Aboneligi Yonet` button for active PRO users.
    - subscription screen is now reachable from profile for both free and PRO accounts.
  - Premium theme system rollout (2026-02-21):
    - new theme core files:
      - `flutter_vocabmaster/lib/theme/app_theme.dart`
      - `flutter_vocabmaster/lib/theme/theme_catalog.dart`
      - `flutter_vocabmaster/lib/theme/theme_provider.dart`
    - 5 themes implemented with XP unlock tiers:
      - `Ice Blue` (free),
      - `Neural Glow` (500 XP),
      - `Midnight Focus` (1000 XP),
      - `Emerald Calm` (1500 XP),
      - `Solar Energy` (2000 XP).
    - `main.dart` now wires global `ThemeProvider` via `MultiProvider`; theme XP unlock state tracks `AppStateProvider` XP updates.
    - `AnimatedBackground` is now theme-aware and renders per-theme gradient + particle style (`rain`, `neural`, `float`, `pulse`, `energy`).
    - `ProfilePage` theme section moved from placeholder options to real unlock/select flow with lock/progress/active-state UI.
    - `ModernBackground` + `ModernCard` are now theme-aware:
      - card gradient/border/glow colors follow selected theme,
      - pattern painters (`dot/line/grid`) are parameterized for per-theme color mapping.
  - Theme unlock policy tweak (2026-02-22):
    - temporary test-mode switch enabled: all themes selectable regardless of XP/subscription (`ThemeProvider._unlockAllThemesForNow=true`).
  - Neural game interaction tuning (2026-02-22):
    - acceptance widened with tokenized phrase matching + stem/fuzzy tolerance expansion.
    - invalid answers now reduce combo by 1 (instead of hard reset to 0) to keep flow less punishing.
    - adaptive hint feedback added from remaining words.
    - debug diagnostics added for submit decisions:
      - `[NeuralGame][ISO_TIME][ACCEPT|REJECT|DUPLICATE] ...`.
    - acceptance scope broadened:
      - related-mode now includes center-word soft-association pools (e.g. travel -> `plane`, `abroad`, `tourist`),
      - fallback loose association path (`soft:*`) for natural-word inputs,
      - node placement `total` is now dynamic to reduce overlap when many loose words are accepted.
  - Theme propagation expansion (2026-02-22):
    - `NavigationMenuPanel` moved to theme-aware color mapping (drawer gradient/effects/header/footer/menu states).
    - `RepeatPage` hardcoded blue accents removed; page visuals now derive from selected app theme colors.
  - Theme propagation expansion v2 (2026-02-22):
    - `HomePage` hardcoded blue sections aligned to selected theme:
      - top hero card, stats cards, daily goal, weekly activity, quick-action buttons.
    - `WordsPage` blue hardcodes removed on key UX points:
      - calendar selected day, empty-state card, speaker chips, form focus/dropdowns.
    - `SentencesPage` blue hardcodes removed:
      - FAB/search/stat chips + sentence highlight/border/toggle accents.
    - Word/sentence modals (`WordSentencesModal`, `AddSentenceModal`) are now theme-aware for gradients/borders/accent texts.
    - `NeonButton` is now globally theme-aware (`Cümleler` / `Cümle Ekle` action buttons inherit selected theme).
  - Animated background enhancement (2026-02-22):
    - added center burst layer in `AnimatedBackground` (`_buildCoreBurst`) so non-solar themes also get center "explosion" feel on load/loop.
  - Theme propagation expansion v3 (2026-02-22):
    - `ProfilePage` first card stat tiles (`Toplam Kelime / Gun Serisi / Seviye`) now derive colors from selected theme.
    - `ProfilePage` theme selector section (`Tema Secimi`, `Aktif tema`) accent texts/icons now follow selected theme.
    - `ProfilePage` account settings icons + logout accent text now theme-aware.
    - `BottomNav` is now globally theme-aware (background, selected gradients/glow, center FAB, labels/icons).
  - Flutter auth resilience expansion (2026-02-22):
    - `ApiService` protected retry (`_withProtectedRetry`) coverage extended to non-AI core endpoints:
      - `words/*`
      - `sentences/*`
      - `content/daily-words`
      - `sentences/stats`
    - expected outcome: token-expiry 401 now refresh+retry behaves consistently across both AI and core content flows.
  - Neural game UX/theme update (2026-02-22):
    - neural widgets switched to selected-theme color system (particle, center node, lines, nodes, glass cards, score/combo/input).
    - play screen now includes quick suggestion chips (tap-to-submit) to reduce dead-end loops.
    - loose-association matching now token-scans phrases and expanded `INNOVATION` soft links (`improvement/progress/upgrade/development`).
  - Google Play lifecycle sync foundation (2026-02-23):
    - new scheduled reconciler: `GooglePlaySubscriptionReconciliationService`.
    - reads latest Google IAP transaction per user, pulls live subscription snapshot from Android Publisher, and syncs local entitlement state.
    - supports cancellation/revocation/expiry drift handling and plan remap refresh from `product-plan-map`.
    - new config namespace: `app.subscription.google-play.reconciliation.*`.
- Local verification constraint:
  - `mvn test` could not run in this sandbox due inaccessible default `.m2` path.
  - `flutter test/analyze` commands timed out in this sandbox.
  - direct `dart analyze` could not start analysis server due OS access denial in sandbox (`CreateFile failed 5`).
  - `dart format` runs on host SDK path and formats files, but exits non-zero because telemetry session file under `%APPDATA%` is not writable in sandbox.
    - final validation requires host-side build/test run.

Critical issues (must track in TODO):
1. Secret exposure risk:
- Groq key appeared in user-shared env; user confirmed rotation. Final release check still must verify old key revocation in provider console and secret manager parity.
- JWT signing secret (`APP_SECURITY_JWT_SECRET`) was shared during session (2026-02-18); VPS runtime secret was rotated on 2026-04-01 and existing JWT sessions were invalidated.
- Flutter artifact leak risk (revalidated 2026-03-04):
  - mitigated on 2026-04-01 by removing `.env` from Flutter assets and disabling embedded env-key use in release builds.
  - still verify that no previous release artifact was built with the old asset setup; rotate provider key if any such artifact exists.
2. Production env completeness:
- Keep full production payment/alert env validation in release process (not only free-launch skip mode).
- Required non-empty vars for full preflight include:
  - `ALERTMANAGER_DEFAULT_WEBHOOK_URL`, `ALERTMANAGER_CRITICAL_WEBHOOK_URL`, `ALERTMANAGER_WARNING_WEBHOOK_URL`
  - `APP_SECURITY_AUTH_GOOGLE_CLIENT_IDS`
  - `APP_SUBSCRIPTION_GOOGLE_PLAY_PACKAGE_NAME`
  - `APP_SUBSCRIPTION_GOOGLE_PLAY_SERVICE_ACCOUNT_HOST_PATH` (must point to an existing JSON file)
3. Billing pipeline not complete:
- Base server-side verification, real-token local dry-run, and scheduled lifecycle reconciliation are complete.
- Remaining gap is RTDN push-event ingestion (near-real-time cancel/refund handling) and staging/prod permission parity checks.
4. AI provider output stability:
- Upstream model may still emit empty/invalid JSON in some scopes; backend now degrades safely with fallback payloads, but quality monitoring/tuning should continue (prompt+model side).
5. Migration rollout:
- Ensure `V017` is applied on staging/prod DBs before prod deploy.
6. Frontend payment safety:
- Demo subscription bypass is now behind build flag (`SUBSCRIPTION_DEMO_MODE`) with default `false`.
- Release pipeline must not pass `--dart-define=SUBSCRIPTION_DEMO_MODE=true`.
7. Frontend localization completeness:
- New i18n foundation is active (`en/de/tr/ar/zh` + language picker + persistent locale).
- Remaining hardcoded strings in legacy screens must be migrated before global-store release quality bar.
8. Runtime header hardening parity (resolved local recheck 2026-03-04):
- docker runtime now emits required security headers and `smoke-security-cors-headers.ps1` passes end-to-end.
- keep `verify-rollout.ps1 -Mode nonprod-smoke -SecuritySmokeAllowedOrigin ...` in release gates to prevent regressions.
9. Google login release parity (new blocker 2026-03-17):
- `flutter_vocabmaster/android/app/google-services.json` Android OAuth fingerprint does not match the current repo upload keystore.
- Before next tester/prod rollout:
  - add current upload-key SHA-1/SHA-256 to Firebase + Google Cloud OAuth,
  - add Google Play App Signing SHA-1/SHA-256 for distributed builds,
  - regenerate/download `google-services.json`,
  - re-test Google login on Play-distributed build (not only local/dev).

## 7) Session startup checklist

1. Repo status:
```powershell
git status --short
```

2. Effective AI policy config:
```powershell
rg -n "ai-token-quota|ai.model-routing|jwt.enforce-auth|mock-verification" backend/src/main/resources/application.properties backend/src/main/resources/application-docker.properties backend/src/main/resources/application-prod.properties
```

3. Docker/runtime sanity:
```powershell
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
docker network inspect flutter-project-main_app-network
```

4. DB/Flyway sanity:
```powershell
docker exec flutter-project-main-postgres-1 psql -U postgres -d EnglishApp -c "SELECT installed_rank, version, description, success FROM flyway_schema_history ORDER BY installed_rank;"
```

5. Rollout gates:
```powershell
pwsh -File scripts/verify-rollout.ps1 -Mode nonprod-smoke
pwsh -File scripts/verify-rollout.ps1 -Mode prod-preflight -SkipPaymentChecks -SkipAlertmanagerChecks
```

## 8) Immediate engineering priorities

- Verify `V016` in staging/prod environments (local is already verified).
- Validate Google Play verification with real service account + package on staging/prod-like env.
- Harden lifecycle sync: keep scheduled reconciliation enabled and add RTDN push-event ingestion for near-real-time updates.
- Add/verify server-side paywall behavior for post-trial FREE users.
- Add observability panels for token usage by plan and model scope.
- Keep secrets out of Flutter artifacts and rotate leaked keys before store release.

## 9) Neural Game module

Source of truth:
- `flutter_vocabmaster/lib/screens/neural_game_page.dart`
- `flutter_vocabmaster/lib/screens/neural_game_menu_screen.dart`
- `flutter_vocabmaster/lib/screens/neural_game_play_screen.dart`
- `flutter_vocabmaster/lib/screens/neural_game_results_screen.dart`
- `flutter_vocabmaster/lib/bloc/neural_game_bloc.dart`

Implemented behavior:
- New practice tab: `Neural Oyun` in `PracticePage`.
- Flow: `menu (mode select) -> play (60s timer) -> results`.
- Scoring: `base 100` + combo multiplier (`+20%` per combo step).
- Visuals: particle background, center node circular timer, animated line connections, discovered word nodes, glass cards.
- Persistence: best score is stored via `SharedPreferences` key `neural_game_best_score`.
- Modes:
  - `Iliskili Kelime`: center worda semantik bagli Ingilizce kelime girilir.
  - `Turkce Karsilik`: related words'un Turkce karsiligi girilir; node subtitle'da translation gosterilir.

Open follow-ups:
- Expand neural game test coverage for responsive-node layout cases.
- Optional backend/AI extension: dynamic word-set generation and server telemetry for game usage.

