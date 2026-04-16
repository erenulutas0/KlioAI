# TODO.md

Last update: 2026-04-16  
Owner: Codex + Team  
Phase: Prod prep + auth hardening

## Session (2026-04-16): Auth surface simplification + trial abuse hardening

### Done in this session

- `flutter_vocabmaster/lib/screens/login_page.dart`: Facebook login button removed from the login surface.
- `flutter_vocabmaster/lib/services/auth_service.dart`: stable install-level `deviceId` generation added; login/register/google-login now send `deviceId` in body and `X-Device-Id` header.
- `flutter_vocabmaster/lib/services/api_service.dart`: refresh flow now also sends the same stable `deviceId`.
- `backend/src/main/resources/db/migration/V017__add_trial_eligible_to_users.sql`: new persistent `users.trial_eligible` column.
- Backend fresh-account trial gating hardened with device/IP heuristics via:
  - `backend/src/main/java/com/ingilizce/calismaapp/config/TrialAbuseProtectionProperties.java`
  - `backend/src/main/java/com/ingilizce/calismaapp/service/TrialAbuseProtectionService.java`
  - `backend/src/main/java/com/ingilizce/calismaapp/controller/AuthController.java`
  - `backend/src/main/java/com/ingilizce/calismaapp/entity/User.java`
  - `backend/src/main/java/com/ingilizce/calismaapp/service/AiEntitlementService.java`
  - `backend/src/main/java/com/ingilizce/calismaapp/controller/UserController.java`
- Flutter fresh-account AI fallback now respects backend `trialEligible=false`:
  - `flutter_vocabmaster/lib/services/ai_access_policy.dart`
- Regression coverage added/updated:
  - `backend/src/test/java/com/ingilizce/calismaapp/controller/AuthControllerUnitTest.java`
  - `backend/src/test/java/com/ingilizce/calismaapp/service/AiEntitlementServiceTest.java`
  - `backend/src/test/java/com/ingilizce/calismaapp/service/TrialAbuseProtectionServiceTest.java`
  - `flutter_vocabmaster/test/services/ai_access_policy_test.dart`

### Verification

1. Backend PASS:
  - `mvn -q "-Dmaven.repo.local=C:\flutter-project-main\backend\.m2-repo" "-Dtest=AuthControllerUnitTest,AiEntitlementServiceTest,TrialAbuseProtectionServiceTest" test`
2. Flutter PASS:
  - `flutter test test/services/ai_access_policy_test.dart`

### Remaining

1. Tune trial-abuse thresholds after observing real traffic (`device=2`, `ip=3`, `window=24h`).
2. Add stronger identity signals before scale: disposable-email filtering, device attestation / Play Integrity, optional payment/phone heuristics.
3. Google login release parity remains a separate blocker before store rollout (Play signing SHA fingerprints + regenerated `google-services.json`).

## Session (2026-04-15): Daily exam pack fallback hardening

### Done in this session

- `DailyExamPackService` fallback path hardened to stop weak repetitive exam packs when Groq returns empty/malformed JSON.
- Daily exam pack payload is now normalized before use/save:
  - canonical topic order is enforced: `Grammar`, `Vocabulary`, `Cloze Test`, `Sentence Completion`, `Reading`
  - each topic is guaranteed to contain exactly 5 valid multiple-choice items
  - partial/invalid AI payloads are topped up with deterministic fallback questions instead of leaking broken structure
- Fallback packs are now persisted into `daily_content` just like the other daily generators:
  - this avoids repeated same-day Groq retries after scheduler/runtime failures
  - scheduler/runtime should now stay on one stable cached pack for the date instead of regenerating weak repeated placeholders
- Deterministic fallback content upgraded from one duplicated question to a richer curated 25-question pack.
- Regression coverage added:
  - `backend/src/test/java/com/ingilizce/calismaapp/service/DailyExamPackServiceTest.java`

### Remaining

1. Host-side targeted backend verification:
  - run `mvn -q "-Dmaven.repo.local=C:\flutter-project-main\backend\.m2-repo" "-Dtest=DailyExamPackServiceTest,DailyContentControllerTest" test`
2. Nonprod/prod-like smoke after deploy:
  - force one fresh `GET /api/content/daily-exam-pack?exam=yds`
  - confirm returned payload has 5 topics x 5 questions and cached same-day response stays stable
3. If scheduler logs still show exam-pack failures:
  - capture the exact raw Groq payload/body once and decide whether to tighten prompt or add a narrower salvage parser

## Session (2026-04-04): Practice gating aligned with AI entitlement

### Done in this session

- Root cause confirmed for practice paywall mismatch:
  - `PracticePage` was still gating on `subscriptionEndDate` only
  - free-trial / free-tier users with active AI entitlement could still see a full-screen PRO lock and card-level upgrade overlays
- Flutter entitlement handling hardened:
  - added shared AI access policy helper:
    - `flutter_vocabmaster/lib/services/ai_access_policy.dart`
  - `AppStateProvider` now fetches `/chatbot/quota/status` during user-data refresh and merges:
    - `aiAccessEnabled`
    - `planCode`
    - `trialActive`
    - token quota snapshot fields
    into cached `userInfo`
  - `PracticePage` now unlocks from AI entitlement (`aiAccessEnabled` / trial / token quota snapshot), not only paid subscription end-date
  - practice screen now waits for the first entitlement snapshot instead of rendering an immediate false paywall on freshly logged-in users
  - additional fallback added for fresh accounts:
    - if quota snapshot is not merged yet, practice access can still be inferred from `trialDaysRemaining`, `isSubscriptionActive`, and `createdAt < 7 days`
  - `PracticePage` now triggers a one-shot entitlement refresh on entry when no snapshot is cached yet
  - subscription/account-switch UX hardened:
    - subscription page now silently attempts store restore/sync on open for non-active accounts
    - `itemAlreadyOwned` now routes to account-sync messaging instead of a raw already-owned error
  - final practice unlock simplification:
    - UI-level full-screen paywall and card overlays were removed from `PracticePage`
    - practice mode visibility no longer depends on subscription/trial sync timing
    - AI access enforcement is left to the actual backend-powered practice flows/endpoints
- Regression coverage added:
  - `flutter_vocabmaster/test/services/ai_access_policy_test.dart`

### Remaining

1. Host-side Flutter verification:
  - run `flutter test test/services/ai_access_policy_test.dart`
2. Build + distribute fresh release:
  - old closed-test builds will still contain the removed practice lock / raw already-owned flow
3. Device smoke:
  - free-trial/free-tier account with AI tokens should open `Practice`
  - post-trial FREE user with `aiAccessEnabled=false` should still see the paywall

## Session (2026-04-05): Subscription account-switch restore hardening

### Done in this session

- Backend lazy-proxy error root cause confirmed in Google restore flow:
  - repeated verify on an already-known purchase token was loading `PaymentTransaction` without eager `plan`
  - `tx.getPlan().getName()` could throw `could not initialize proxy ... SubscriptionPlan#... - no Session`
- Backend fixes applied:
  - `SubscriptionController.verifyGooglePurchase(...)` now uses `findByTransactionIdWithUserAndPlan(...)`
  - already-verified Google purchases can now be rebound to the currently signed-in app user during restore/account-switch flow
  - `UserController.getUserProfile(...)` no longer returns raw JPA `User`; it returns a flat response map to avoid future lazy-serialization failures
- Flutter fix applied:
  - `SubscriptionService.getUserSubscriptionStatus()` now calls the dedicated lightweight endpoint:
    - `/users/{id}/subscription/status`
- Release version bumped:
  - `flutter_vocabmaster/pubspec.yaml` -> `1.1.3+170`

### Remaining

1. Build and upload a fresh closed-test AAB.
2. Verify account-switch flow:
  - Account A owns the Play subscription
  - switch to Account B in the app
  - open subscription page
  - expect restore/sync instead of lazy-proxy error
3. Verify purchase UX:
  - after sync, avoid raw `alreadyOwned`
  - subscription should attach to the current app account

## Session (2026-04-04): Production data reset for clean restart

### Done in this session

- Full production PostgreSQL backup taken on VPS before destructive cleanup:
  - `/opt/vocabmaster/backups/pre-nuke/EnglishApp_pre_nuke_20260404T180918Z.dump`
- Production user/state data wiped for a clean restart:
  - truncated and identity-reset user/content/payment/session/social tables
  - flushed both Redis instances (`redis`, `redis-security`)
  - kept reference/schema tables intact:
    - `flyway_schema_history`
    - `subscription_plans`
    - `badges`
- Post-reset verification:
  - `users = 0`
  - `words = 0`
  - `sentences = 0`
  - `payment_transactions = 0`
  - `refresh_token_sessions = 0`
  - `daily_content = 0`
  - `subscription_plans = 5`
  - `badges = 14`
- Host runtime smoke re-run PASS after cleanup.

### Remaining

1. Start from a fresh mobile session:
  - uninstall/reinstall or clear app data on the device
  - register/login with a clean account
2. Re-test the subscription flow from zero:
  - purchase or restore
  - verify backend entitlement is written
  - confirm practice screen unlock follows refreshed profile state

## Session (2026-04-04): VPS runtime recheck + secret permission hardening

### Done in this session

- Production VPS runtime rechecked directly over SSH:
  - `vocabmaster-caddy`, `vocabmaster-backend`, `vocabmaster-redis`, `vocabmaster-redis-security`, `vocabmaster-postgres` were all `Up` and `healthy`
  - backend public health still returns `200` on `https://api.klioai.app/actuator/health`
  - protected AI probe without auth still returns expected `401 Unauthorized`
  - PostgreSQL accepts connections and current verification counts remain:
    - `flyway_schema_history = 17`
    - `users = 1`
  - host runtime smoke script `/opt/vocabmaster/deploy/runtime-smoke.sh` re-run PASS
- Redis runtime auth revalidated against the actual container env values:
  - `vocabmaster-redis` -> `PONG`
  - `vocabmaster-redis-security` -> `PONG`
- Secret and runtime directory permissions tightened on VPS:
  - `/opt/vocabmaster/secrets` -> `700`
  - `/opt/vocabmaster/caddy` -> `700`
  - `/opt/vocabmaster/backups` -> `700`
  - `/opt/vocabmaster/backups/backup-postgres.sh` -> `700`
- Root cause direction narrowed:
  - current production symptom is not DB/Redis/backend reachability
  - recent backend logs show repeated Groq JSON-generation failures in scheduled daily exam pack generation (`DailyExamPackService`)
  - user-facing AI problems may also still appear as expected `401` on stale mobile sessions because JWT runtime secret was rotated on 2026-04-01

### Remaining

1. App-side smoke after forced re-auth:
  - fully log out / log back in on the device
  - re-test dictionary, translation, reading, writing, and exam flows
2. Backend fix follow-up:
  - harden `DailyExamPackService` so malformed/empty Groq JSON produces a richer deterministic fallback instead of weak repetitive content
3. If user still sees AI failure after re-login:
  - capture exact endpoint/screen and status code/body from the device or backend logs

### Additional auth diagnostic progress

- Login issue reported on device at `2026-04-04 14:13` is now strongly attributed to a stale build targeting an old `ngrok` backend:
  - observed runtime error body referenced `sanda-sheathiest-uncredulously.ngrok-free.dev`
  - current repo/runtime config no longer contains that host and production default is `https://api.klioai.app`
  - no persistent backend-URL override was found in app storage code; likely source is an older APK/AAB built with `--dart-define BACKEND_URL=...ngrok...`
- Flutter auth diagnostics hardened:
  - `flutter_vocabmaster/lib/services/auth_service.dart`
    - login/register/google-login now detect non-JSON backend responses and include clearer context
  - `flutter_vocabmaster/lib/services/google_login_error_message_formatter.dart`
    - stale-offline `ngrok` responses now map to an explicit “old build / install fresh api.klioai.app build” message
  - regression test added:
    - `flutter_vocabmaster/test/google_login_error_message_formatter_test.dart`
- Host-side Flutter test execution still needs local verification:
  - sandbox timeout hit while running `flutter test test/google_login_error_message_formatter_test.dart`
- Release config crash root cause identified after ngrok was removed:
  - new device error `NotInitializedError` came from direct `dotenv.env` access in release when `.env` is not bundled
  - fix applied:
    - new helper `flutter_vocabmaster/lib/config/dotenv_safe.dart`
    - `app_config.dart`, `backend_config.dart`, `auth_service.dart`, `groq_api_client.dart` now read dotenv values through safe fallback access
  - expected runtime effect:
    - release builds without bundled `.env` should now fall back to `https://api.klioai.app` cleanly instead of failing before URL resolution
- Google Play verify runtime fix applied on VPS:
  - subscription verify error `Unable to read Google service account file` was traced to file permissions on the bind-mounted service-account JSON
  - backend container runs as non-root user `spring` (`uid=999`)
  - mounted file `/run/secrets/google-play-service-account.json` was `root:root 600`, so backend could not read it
  - host file permission changed to `644`:
    - `/opt/vocabmaster/secrets/google-play-service-account.json`
  - backend restarted cleanly after the fix
  - post-fix container check confirms:
    - `/run/secrets/google-play-service-account.json` is now readable by the app process
    - `APP_SUBSCRIPTION_GOOGLE_PLAY_SERVICE_ACCOUNT_FILE=/run/secrets/google-play-service-account.json`
- Subscription sync mismatch analysis completed for `eerenulutass@gmail.com`:
  - current production user row:
    - `id=3`
    - `subscription_end_date = NULL`
    - `ai_plan_code = FREE`
  - `payment_transactions` currently has no successful row for this user, so store ownership has not yet been written into backend entitlement
  - Flutter-side follow-up fixes applied:
    - `AuthService.refreshProfile()` now fetches real backend profile from `/api/users/{id}` and persists updated user data
    - `SubscriptionPage` now refreshes profile + `AppStateProvider` after active subscription status is detected
    - `PracticePage` premium gate no longer treats any non-null `subscriptionEndDate` as active; it now checks for a valid non-expired date

## Session (2026-03-30): Pre-prod review + sentence generation hardening

### Done in this session

- Translation practice sentence quality root-cause review completed:
  - backend sentence prompt contract was internally inconsistent:
    - `PromptCatalog.generateSentences()` asked for 3 items,
    - controller asked for 5 mixed level/length items,
    - service was wrapping the controller prompt a second time (`Target word: ...` inside another `Target word: ...` string).
  - this mismatch made repetitive / overly generic sentence outputs more likely, especially when `fresh=true`.
- Backend sentence generation hardening applied:
  - `backend/src/main/java/com/ingilizce/calismaapp/service/PromptCatalog.java`
    - prompt upgraded to v2,
    - now requires a JSON object with `sentences`,
    - explicitly requests exactly 5 structurally diverse outputs and natural Turkish translations.
  - `backend/src/main/java/com/ingilizce/calismaapp/service/ChatbotService.java`
    - sentence-generation user message is now passed through directly instead of being double-wrapped.
  - `backend/src/main/java/com/ingilizce/calismaapp/controller/ChatbotController.java`
    - fresh-mode prompt now contains stronger diversity/length instructions,
    - duplicate English sentences are filtered before response/caching.
- Regression coverage added:
  - `backend/src/test/java/com/ingilizce/calismaapp/service/ChatbotServiceTest.java`
  - `backend/src/test/java/com/ingilizce/calismaapp/controller/ChatbotControllerTest.java`
  - covers direct prompt pass-through, fresh variation instructions, and duplicate sentence removal.

### Remaining

1. Host-side targeted backend verification:
  - `mvn -q "-Dmaven.repo.local=C:\\flutter-project-main\\backend\\.m2-repo" "-Dtest=ChatbotServiceTest,ChatbotControllerTest" test`
2. Manual QA on device/app flow:
  - same word with different level/length selections should now produce meaningfully different sentence sets
  - `fresh=true` consecutive taps should avoid repeating the same stock examples
3. Random translation mode review:
  - current Flutter random mode still concatenates multiple words into one backend `word` field; this should be redesigned if product goal is "one sentence per random word".

## Session (2026-03-30): VPS30 baseline provisioning

### Done in this session

- Primary production VPS baseline prepared on clean Ubuntu 24.04 host:
  - Docker installed and enabled
  - Docker Compose v2 installed
  - `fail2ban` installed and active (`sshd` jail)
  - `unattended-upgrades` enabled
  - `ufw` enabled with default deny-incoming / allow-outgoing
  - inbound allowlist currently limited to:
    - `22/tcp`
    - `80/tcp`
    - `443/tcp`
- Deployment directory skeleton created under `/opt/vocabmaster`:
  - `deploy`
  - `secrets`
  - `caddy`
  - `backend`
  - `frontend`
  - `redis`
  - `logs`
  - `backups`

### Remaining

1. Decide short-term topology on primary VPS:
  - temporary single-host mode: backend + redis + postgres
  - later split: move postgres to dedicated VPS20
2. Add deployment assets to host:
  - production compose files
  - env/secrets
  - reverse proxy config
3. Add app/redis deployment and backup coverage:
  - backend/redis compose on primary VPS
  - app/redis config backup as needed
4. Add monitoring/alert routing on the VPS runtime after first deployment.

### Additional progress

- Temporary single-host PostgreSQL runtime is now active on the primary VPS:
  - Docker Compose file: `/opt/vocabmaster/deploy/docker-compose.postgres.yml`
  - container name: `vocabmaster-postgres`
  - DB: `EnglishApp`
  - app role: `englishapp`
  - bind scope: `127.0.0.1:5432` only (not public)
  - healthcheck status verified healthy
- Secret handling improved after first bootstrap:
  - Postgres passwords rotated
  - compose now uses file-based Docker secrets from `/opt/vocabmaster/secrets/`
  - inline password bootstrap file removed
- Daily logical backup added on the VPS:
  - script: `/opt/vocabmaster/backups/backup-postgres.sh`
  - cron: `/etc/cron.d/vocabmaster-postgres-backup`
  - retention: delete dumps older than 7 days
  - first backup smoke run succeeded
- Primary app stack is now deployed on the same VPS:
  - compose: `/opt/vocabmaster/deploy/docker-compose.app.yml`
  - backend env split completed:
    - `/opt/vocabmaster/secrets/backend.env`
    - `/opt/vocabmaster/secrets/redis.env`
    - `/opt/vocabmaster/secrets/redis-security.env`
  - backend: `healthy` on `http://84.46.251.95:8082`
  - redis: `healthy`
  - redis-security: `healthy`
  - `/actuator/health` -> `200` + `{"status":"UP"}`
  - protected quota probe without JWT -> expected `401`
- Startup blockers resolved during deploy:
  - empty remote `POSTGRES_APP_PASSWORD` caused Flyway SCRAM auth failure
  - Compose variable interpolation initially blanked Redis runtime passwords until `$$...` escaping and split env files were applied
  - prod strict CORS validation rejected local loopback origins from the developer `.env`; temporary VPS origin is now `http://84.46.251.95:8082`
  - Redis host hardening applied: persistent `vm.overcommit_memory=1`
- Immediate infra follow-ups after first successful deploy:
  - replace temporary public-IP CORS origin with final HTTPS domain origin
  - rotate VPS `root` password, add SSH key auth, disable password login
  - move PostgreSQL to dedicated VPS20 when provisioned
- Reverse proxy layer is now active on the VPS:
  - compose: `/opt/vocabmaster/deploy/docker-compose.proxy.yml`
  - Caddy config: `/opt/vocabmaster/caddy/Caddyfile`
  - public backend access moved to `http://84.46.251.95`
  - Caddy -> `vocabmaster-backend:8082` reverse proxy verified
  - `/actuator/health` returns `200 UP` through both `localhost:80` and public host IP
  - public firewall exposure for `8082/tcp` removed after proxy verification

Next infra step now requires user input / DNS:
- [ ] Point final production domain/subdomain to the VPS public IP.
- [ ] Update Caddy from IP-based HTTP to domain-based HTTPS.
- [ ] After domain cutover, update backend CORS origin from `http://84.46.251.95` to the final `https://...` origin.
- SSH hardening progress:
  - provided ED25519 public key added to `/root/.ssh/authorized_keys`
  - root password login is intentionally still enabled until key-based login is tested successfully
- Domain cutover progress:
  - `api.klioai.app` is now active on Caddy with automatic Let's Encrypt TLS
  - `http://api.klioai.app/...` -> `308` redirect to `https://api.klioai.app/...`
  - `https://api.klioai.app/actuator/health` -> `200 UP`
  - backend CORS origin updated to domain-based values:
    - `https://klioai.app`
    - `https://api.klioai.app`
  - `klioai.app` apex now also has working Let's Encrypt TLS
  - `http://klioai.app` -> `308` to `https://klioai.app`
  - `https://klioai.app` -> `301` to `https://api.klioai.app`

Current public routing state:
- backend base URL: `https://api.klioai.app`
- apex site: `https://klioai.app` static landing page

## Session (2026-04-01): Post-domain prod hardening

### Done in this session

- Flutter production config hardened for public rollout:
  - `flutter_vocabmaster/lib/config/app_config.dart`
    - non-debug builds now default to `https://api.klioai.app` when no explicit `BACKEND_URL` is provided
  - `flutter_vocabmaster/lib/config/backend_config.dart`
    - legacy callers now also fall back to `https://api.klioai.app` outside debug mode
  - `flutter_vocabmaster/lib/main.dart`
    - `.env` loading is now best-effort so release builds do not crash when the file is not bundled
  - `flutter_vocabmaster/pubspec.yaml`
    - `.env` removed from Flutter assets; release APK/AAB should no longer bundle the local env file
  - `flutter_vocabmaster/lib/services/groq_api_client.dart`
    - embedded `.env` Groq key path is now disabled in release builds even if `ALLOW_EMBEDDED_GROQ_KEY` is present
  - Android cleartext posture improved:
    - `flutter_vocabmaster/android/app/src/main/AndroidManifest.xml` -> `usesCleartextTraffic=false`
    - `flutter_vocabmaster/android/app/src/debug/AndroidManifest.xml` keeps cleartext enabled for local debug only
- VPS runtime hardened after domain cutover:
  - backend host port publish removed from `/opt/vocabmaster/deploy/docker-compose.app.yml`
  - backend is now only reachable internally by Caddy on the Docker network
  - `docker inspect vocabmaster-backend` confirms empty host `PortBindings`
  - `APP_SECURITY_JWT_SECRET` rotated on VPS runtime env files
  - expected impact: existing access/refresh tokens are invalidated; clients should re-authenticate
  - Docker container log rotation added:
    - backend: `20m x 5`
    - caddy/postgres/redis services: `10-20m x 3-5`
  - basic runtime smoke added:
    - script: `/opt/vocabmaster/deploy/runtime-smoke.sh`
    - cron: `/etc/cron.d/vocabmaster-runtime-smoke` (every 5 minutes)
    - logrotate config: `/etc/logrotate.d/vocabmaster-runtime-smoke`
- Backup / restore validation completed:
  - fresh backup generated: `/opt/vocabmaster/backups/postgres/EnglishApp_20260331T220911Z.sql.gz`
  - restore smoke DB created and loaded successfully
  - restore verification counts:
    - `flyway_schema_history = 17`
    - `users = 1`
  - temp restore DB dropped after verification

### Validation notes

- Remote health check PASS:
  - `https://api.klioai.app/actuator/health` -> `200 UP`
- Runtime smoke PASS on-host:
  - backend/caddy/redis/postgres all healthy at check time
- Local host-side tooling constraints remain:
  - `dart format` timed out in this sandbox
  - `flutter test flutter_vocabmaster/test/config/app_config_test.dart` timed out in this sandbox
  - final Flutter build/test verification still requires host-side execution

### Remaining manual items

1. Test SSH key login from your machine:
  - `ssh root@84.46.251.95`
2. After SSH key login is confirmed, disable SSH password login on the VPS.
3. Decide whether `klioai.app` stays as redirect or gets a real landing page/frontend.

## Session (2026-04-01): klioai.app landing page rollout

### Done in this session

- New static landing page added to the repo:
  - `site/klioai-landing/index.html`
  - `site/klioai-landing/styles.css`
- Landing page visual direction:
  - dark editorial hero
  - product-focused messaging for Klio AI
  - sections for workflow, product value, and infrastructure posture
- VPS deployment completed:
  - static files uploaded to `/opt/vocabmaster/frontend/klioai-site`
  - Caddy apex routing changed from redirect mode to static file serving
  - `klioai.app` now serves the landing page over HTTPS
  - `api.klioai.app` remains the backend/API origin
- Verification completed:
  - `https://klioai.app` -> `200` with HTML landing page
  - `https://api.klioai.app/actuator/health` -> `200 UP`

### Current public routing state

- `https://klioai.app` -> static landing page
- `https://api.klioai.app` -> backend/API

## Session (2026-04-01): public legal pages

### Done in this session

- Added public legal pages to the static site:
  - `site/klioai-landing/privacy.html`
  - `site/klioai-landing/terms.html`
- Updated landing page navigation/footer links:
  - `Privacy`
  - `Terms`
  - footer legal links now visible on `klioai.app`
- Deployed updated static files to VPS:
  - `https://klioai.app/privacy.html` -> `200`
  - `https://klioai.app/terms.html` -> `200`

### Current public web surface

- `https://klioai.app` -> landing page
- `https://klioai.app/privacy.html` -> privacy policy
- `https://klioai.app/terms.html` -> terms of use
- `https://api.klioai.app` -> backend/API

## Session (2026-03-21): Cross-account local state isolation fix

### Done in this session

- Cross-account state bleed root cause confirmed in Flutter session layer:
  - `AppStateProvider` was keeping previous account words/stats/xp/streak in memory across logout/login cycles.
  - visible symptom: after switching accounts on the same device, the new account could temporarily see the previous account's local words and derived stats.
- Session isolation hardening applied:
  - `flutter_vocabmaster/lib/providers/app_state_provider.dart` now resets session-scoped in-memory state before hydrating a signed-in user.
  - login hydration path now reloads words/sentences/user stats for the current authenticated user instead of reusing stale provider state.
  - explicit `clearSessionState()` added for logout/account-switch flows.
- Logout flows now clear provider state immediately before local auth/session cleanup:
  - `flutter_vocabmaster/lib/screens/profile_page.dart`
  - `flutter_vocabmaster/lib/services/ai_paywall_handler.dart`
- Regression coverage added:
  - `flutter_vocabmaster/test/unit/app_state_provider_session_reset_test.dart`
  - verifies that prior account in-memory words/xp/streak/profile state is cleared.

### Remaining

1. Host-side verification:
  - switch Account A -> logout -> Account B -> confirm words/xp/streak are isolated
  - repeat with Account A re-login on the same device
2. Targeted Flutter test still needs host execution:
  - `flutter test test/unit/app_state_provider_session_reset_test.dart`

## Session (2026-03-19): Auth backend URL validation hotfix

### Done in this session

- Login/register `FormatException` root cause narrowed down to invalid frontend backend URL configuration:
  - Flutter was accepting malformed `BACKEND_URL` values without validation.
  - Reported failing shape included whitespace/invalid host content and accidental extra path content (example symptom included `exit_with_errorlevel.bat` in the composed URL).
- Frontend config hardening applied:
  - `flutter_vocabmaster/lib/config/app_config.dart` now normalizes and validates backend root URLs before use.
  - invalid values are now rejected early when they contain whitespace, malformed host content, unsupported scheme, or extra path/query/fragment parts.
  - accepted shape remains backend root only, for example `https://api.example.com` or `http://192.168.1.102:8082`.
- Auth error handling improved:
  - `flutter_vocabmaster/lib/services/auth_service.dart` now resolves auth URIs inside `try` blocks so invalid config errors are surfaced as readable login/register failures instead of escaping before request handling.
- Regression coverage added:
  - `flutter_vocabmaster/test/config/app_config_test.dart`
  - covers valid root URLs, whitespace rejection, and accidental path/query rejection.

### Remaining

1. Rebuild/run with a corrected backend define or `.env` value:
  - PowerShell example: `flutter run --dart-define=\"BACKEND_URL=https://your-api-host\"`
2. Host-side verification still required:
  - `flutter test test/config/app_config_test.dart`
  - login/register smoke on device or release build with the real backend URL

## Session (2026-03-18): Closed-test Google Sign-In verification guard

### Done in this session

- Closed-test Google Sign-In blocker confirmed locally by comparing repo release keystore vs Firebase Android OAuth client:
  - upload keystore SHA-1 = `DD:C9:FB:90:3C:F4:BF:D0:E7:E6:E6:88:C5:23:0F:D1:6A:37:A4:D7`
  - current `flutter_vocabmaster/android/app/google-services.json` Android OAuth SHA-1 = `5D:5F:25:F4:73:C0:3F:AB:6B:98:57:BC:A9:80:50:17:68:B6:20:82`
  - result: mismatch reproduced; closed-test Google login failure is configuration-side, not Flutter auth-flow logic.
- New local guard added:
  - `scripts/check-google-signin-android-config.ps1`
  - reads `flutter_vocabmaster/android/key.properties`, resolves the release keystore, extracts SHA fingerprints with `keytool`, and compares them to Android OAuth fingerprints in `google-services.json`.
  - `scripts/verify-rollout.ps1 -Mode local-gate` now runs this check before backend/test gates.
- Release checklist updated with explicit Google Sign-In closed-test prerequisites and repo validation command.
- Closed-test networking root cause confirmed:
  - bundled Flutter `.env` pointed auth traffic to local LAN backend `http://192.168.1.102:8082`, so tester devices outside the same network hit register/login timeouts.
  - `flutter_vocabmaster/lib/config/app_config.dart` now prefers `--dart-define` values over bundled `.env` for `BACKEND_URL`, `API_PORT`, and host fallbacks.
  - release builds can now target a public/staging backend without editing the checked-in `.env`.
- Backend auth refresh hotfix applied:
  - `AuthController.refresh` no longer issues a new access token from a detached lazy `User` proxy returned via rotated refresh session.
  - user is now reloaded from `UserRepository` before JWT issuance, preventing `LazyInitializationException` -> `500` -> client retry -> false `REUSE_DETECTED` cascades.
  - integration coverage added for successful `/api/auth/refresh` token rotation.

### Remaining

1. Console-side fix:
  - add current upload-key SHA-1/SHA-256 to Firebase Android app and Google Cloud OAuth.
  - add Google Play App Signing SHA-1/SHA-256 to Firebase Android app and Google Cloud OAuth.
  - download refreshed `flutter_vocabmaster/android/app/google-services.json`.
  - rebuild AAB and publish a new closed-test release.
2. Smoke verification:
  - install only the Play-distributed closed-test build on a tester device.
  - re-run Google Sign-In smoke there; local/debug APK success is not sufficient.

## Session (2026-03-17): TesterCommunity feedback triage

### Done in this session

- Google login external-test root cause narrowed down:
  - current Android OAuth fingerprint in `flutter_vocabmaster/android/app/google-services.json` does not match the repo upload keystore fingerprint.
  - repo upload keystore SHA-1 differs from the Firebase-configured Android client hash, so Play/internal-test builds can fail with Google Sign-In developer error (`ApiException: 10`) even if local/debug login appears healthy.
  - required release action: add both current upload key and Google Play App Signing SHA-1/SHA-256 fingerprints to Firebase + Google Cloud OAuth config, then download and ship refreshed `google-services.json`.
- Google login UX hardening applied:
  - `AuthService` now maps common Google Sign-In native failures to actionable user-facing copy.
  - config/signing failures now explicitly suggest temporary fallback to email login instead of generic failure text.
  - `LoginPage` now updates `AppStateProvider` on successful Google login for parity with email login.
- New-user walkthrough path activated:
  - first unauthenticated launch now routes from `SplashScreen` to `OnboardingScreen` once via `app_tour_completed_v2`.
  - onboarding completion is persisted through new `AppTourService`.
  - `SettingsPage` now exposes replay entrypoint for the app tour.
  - onboarding content is now driven from existing localized landing feature copy instead of hardcoded Turkish-only strings.
- Language-gate device compatibility hotfix:
  - `LanguageSelectionPage` content now uses a scrollable list and the continue CTA is pinned in the bottom safe area, so smaller/older devices cannot trap the action below the fold.
  - continue action now also pushes explicitly to `SplashScreen` after persisting the language, reducing dependency on root-gate rebuild timing.

### Remaining

1. Firebase/Google Cloud console fix:
  - register the current upload key fingerprints.
  - register Google Play App Signing fingerprints for test/prod distributed builds.
  - refresh `flutter_vocabmaster/android/app/google-services.json`.
  - re-run Google login smoke on Play-distributed build, not only local APK/debug.
2. ASO/store listing work:
  - prepare stronger short/full descriptions and keyword set before next store submission.
3. Walkthrough depth:
  - current app tour covers feature intro + replay.
  - next iteration can add contextual coach-marks/tooltips inside Home / Practice / Subscription flows.

## Hotfix (2026-03-04): AI outage + uptime hardening

### Done in this session

- Root-cause identified for "Groq/API calismiyor" report:
  - issue was not Groq provider; backend failed startup due DB hostname resolution (`UnknownHostException: postgres`).
  - immediate cause: compose dependency services `postgres`, `redis`, `redis-security` were down (`Exited (255)`), backend entered restart loop.
- Runtime recovered:
  - `docker compose up -d postgres redis redis-security backend`
  - `docker compose ps` now shows backend/postgres/redis/redis-security healthy.
  - health probe `GET /actuator/health` returned `200`.
  - AI probe `POST /api/chatbot/dictionary/lookup-detailed` returned `200`.
- Uptime hardening applied:
  - `docker-compose.yml` updated with `restart: unless-stopped` for `postgres`, `redis`, `redis-security`.
- Security header/runtime hardening completed (2026-03-04):
  - `backend/src/main/resources/application-docker.properties` now enables `app.security.headers.*` defaults in docker runtime.
  - `scripts/smoke-security-cors-headers.ps1` updated for PowerShell 7 (`-SkipHttpErrorCheck`) to avoid false failures on non-2xx checks.
  - `scripts/verify-rollout.ps1` now passes a distinct disallowed origin (`http://evil.example.com`) to security smoke when `SecuritySmokeAllowedOrigin` is set.
  - verified PASS:
    - `pwsh -File scripts/smoke-security-cors-headers.ps1 -BaseUrl http://localhost:8082 -AllowedOrigin http://localhost:8080 -DisallowedOrigin http://evil.example.com`
    - `pwsh -File scripts/verify-rollout.ps1 -Mode nonprod-smoke -ProjectName flutter-project-main -SecuritySmokeAllowedOrigin http://localhost:8080`
- Flutter widget regression fixes completed (2026-03-04):
  - fixed responsive overflow in `WordOfTheDayModal` header and completion badge row.
  - updated `daily_word_card_test.dart` and `word_of_the_day_modal_test.dart` to localization-aware assertions.
  - verified PASS:
    - `flutter test test/daily_word_card_test.dart test/word_of_the_day_modal_test.dart -r compact`
    - `flutter test -r compact`
  - backend regression recheck PASS:
    - `mvn -q "-Dmaven.repo.local=C:\\flutter-project-main\\backend\\.m2-repo" test` (`578 tests, 0 failures`).
- Security attack probe recheck PASS (2026-03-04):
  - `noAuthQuota=401`, `spoofUserHeader=403`, `tamperedJwt=401`, `sqliLogin=401`, brute-force -> `...401,401,429,429`, `adminEndpointAsUser=403`.
- UI theme parity (2026-03-04):
  - `flutter_vocabmaster/lib/screens/notifications_page.dart` now uses selected `ThemeProvider` colors for notification icon palette + unread dot + loading/empty states (hardcoded red/pink removed).
  - `flutter analyze lib/screens/notifications_page.dart` -> PASS.

## New Workstream (2026-02-24): Global Localization Rollout

### Done in this session

- Flutter i18n foundation added:
  - `flutter_vocabmaster/lib/l10n/app_localizations.dart`
  - `flutter_vocabmaster/lib/providers/language_provider.dart`
  - `flutter_vocabmaster/lib/screens/language_selection_page.dart`
- `MaterialApp` wired with:
  - explicit `locale` from `LanguageProvider`
  - `flutter_localizations` delegates
  - `supportedLocales` (`en`, `de`, `tr`)
- First-run language gate implemented:
  - user must choose language before splash/auth routing
  - device locale is used as recommended default
  - persistent keys: `app_language_code`, `app_language_selected`
- In-app language switcher added in drawer menu.
- Main shell localization applied to:
  - splash
  - landing
  - login
  - bottom nav
  - drawer/menu labels
  - practice shell (mode labels + key CTA/header/lock texts)
- Post-integration test-hardening:
  - `BottomNav` now gracefully falls back to default theme when `ThemeProvider` is absent in isolated widget tests.
  - `WordOfTheDayModal` now gracefully falls back to default theme when `ThemeProvider` is absent in isolated widget tests.
  - `NeuralGameResultsScreen` + `NeuralParticleBackground` + `GlassmorphismCard` now also fall back to default theme when `ThemeProvider` is absent in isolated widget tests.
  - `DailyWordCard` + `NeuralGameMenuScreen` + `NeuralGamePlayScreen` + `NeuralScoreCard` + `NeuralWordNode` now also fall back to default theme when `ThemeProvider` is absent in isolated widget tests.
  - `NeuralGameMenuScreen` info tiles now use responsive text layout (no horizontal overflow on narrow test viewport).
  - Warning cleanup pass applied (low-risk hardening):
    - removed many `unused import/field/local` warnings across `main`, key screens, services, and integration tests.
    - fixed `override_on_non_overriding_member` in offline connectivity test doubles.
    - replaced runtime call to `XPManager.resetIdempotency()` with production-safe `XPManager.clearIdempotencyCache()`.
    - removed several unnecessary non-null assertions in sentence deletion flow (`AppStateProvider`) and daily word/home flows.
- Async `BuildContext` safety hardening pass:
  - added `mounted/context.mounted` guards after `await` points in key UI flows (`main`, `home`, `chat_detail`, `dictionary`, `quick_dictionary`, `repeat`, `subscription`, `translation_practice`, `writing_practice`).
  - fixed context-capture issues in list/dialog builders by switching to state context where appropriate (`sentences_page`, `words_page`).
- Production logging lint hardening (Flutter):
  - all remaining `print(...)` calls in `lib/` were replaced with `debugPrint(...)` to remove `avoid_print` analyzer infos.
  - added missing `package:flutter/foundation.dart` imports in affected service/test files where needed for `debugPrint`.
- Analyzer cleanup pass #2 (Flutter, low-risk):
  - `use_super_parameters` batch applied across widget constructors (`super(key: key)` -> `super.key`).
  - removed spread `toList()` usages (`...iterable.toList()` -> `...iterable`).
  - fixed all currently reported `unnecessary_string_escapes` in grammar content files.
  - removed unnecessary imports (`dart:ui`/`dart:typed_data`) and `IO` prefix naming lint (`as io`) in socket files.
  - fixed deprecated test mock handler API in `test/word_of_the_day_modal_test.dart` (defaultBinaryMessenger path).
- Analyzer cleanup pass #3 (Flutter, low-risk):
  - fixed `createState` public API return types across stateful widgets (`State<Widget>`), addressing private-type-in-public-api lint set.
  - fixed selected flow-control brace lints and `SizedBox` whitespace lints in chat/grammar/social/home/repeat/video views.
  - normalized `word_of_the_day_modal` step-builder method names to lowerCamelCase.
  - cleaned additional minor lints: conditional assignment in language selection, unnecessary casts in API/daily progress parse paths.
- Analyzer cleanup pass #4 (Flutter, low-risk):
  - removed remaining reported `unused_element` helpers in focused screens (`friend_list`, `practice`, `profile`, `social_feed`, `video_call`, `words`, `home`).
  - cleared additional spread lint points and small `const`/declaration lints in tests/services/screens.
  - applied extra targeted cleanups for `unnecessary_const`, `prefer_final_fields`, and small constructor/style hotspots.
- HomePage analyzer recovery fix:
  - restored missing `_buildDailyWordsSection`, `_buildQuickActions`, `_buildRecentlyLearned` methods in `home_page.dart`.
  - added safe helper rendering for daily words/recent words and quick navigation cards.
  - removed stale unused `_mix` helper and reintroduced `Word` model import required by recovered section.
- Language UX reliability fix:
  - `LanguageProvider` now persists and checks `app_language_prompt_seen`; old installs without this flag will see language selection once on next launch.
  - Home quick actions now include direct `Dil / Language` shortcut (`route: language`) so users can change language without opening drawer.
- Localization hardening pass (2026-02-27):
  - new in-app `SettingsPage` language selector is now wired from drawer (`Ayarlar / Settings`) and profile account settings card.
  - `supportedLocales` expanded to include `ar` and `zh` (fallback-to-English for missing keys).
  - `PracticePage` mode/submode logic moved from Turkish labels to language-agnostic IDs (`translate/reading/...`, `select/manual/random`) to prevent locale-dependent behavior bugs.
  - `LevelAndLengthSection` localized and length values normalized to `short/medium/long`.
  - `HomePage` + `DailyWordCard` key user-facing hardcoded strings moved to localization keys (XP progress, weekly activity, add-sentence CTA, keep-going labels).
  - localization key integrity check now reports `MISSING_COUNT=0` for all `context.tr(...)` usages in `lib/`.
- Home "Günün Kelimeleri" UX restore:
  - daily words section reconnected to `DailyWordCard` horizontal card flow (tap -> `WordOfTheDayModal`).
  - `+` quick action now reopens two-path add flow (`Kelimeyi Ekle`, `Kelimeyi Cümlesiyle Ekle`) via bottom sheet.
  - daily-word payload normalization added in `home_page.dart` so modal/card work even if backend key shapes differ.
  - `WordOfTheDayModal` final action label aligned to flow (`Devam Et`) and summary add CTA label normalized (`Kelimeyi Ekle`).
- Subscription/quota abuse hardening (backend):
  - `SubscriptionController` now treats AI subscription duration as fixed 30 days for `PREMIUM` / `PREMIUM_PLUS` tiers.
  - mock/demo activation paths now return idempotent success when a subscription is already active (no extra extension), preventing repeat-activation abuse by test users.
  - daily token quota behavior remains day-key based (`ai:tokens:day:{yyyy-mm-dd}:{userId}`), so quota usage is not reset by re-activation and naturally resets every UTC day.

### Remaining (high priority)

1. Migrate remaining legacy hardcoded strings across all Flutter screens (`home`, `profile`, `dictionary`, `words`, `sentences`, etc.) to `AppLocalizations`.
2. Host-side validation required:
  - `flutter pub get`
  - targeted `flutter analyze`
  - smoke test on device for language switch + persistence + RTL-safe layouts (future-proofing)
3. Add i18n regression tests for language persistence and startup flow.

## Session Handoff (2026-02-18)

### Ne Yaptik

- AI entitlement + paywall + model routing mimarisini prod'a yakin seviyeye getirdik.
- Neural game modulu app'e entegre edildi ve otomasyon testleri eklendi.
- Google Play live verify icin smoke script ve runbook eklendi.
- Release gate'ler tekrar kosuldu (`nonprod-smoke` + `prod-preflight`) ve PASS alindi.
- Secret hygiene guclendirildi (`secrets/` gitignore, hizli leak taramalari temiz).

### Ne Yapiyoruz

- Prod cut oncesi son mile dogrulamalar:
- gercek purchase token ile Google Play live verify dry-run
- gercek kullanici akisinda quota/paywall UX dogrulama
- neural game fiziksel cihaz UX/fps ve responsive layout kontrolu

### Nerede Kaldik

- Kod ve testler green, rollout gate'ler green.
- Kritik eksik: gercek Google Play token ile canli verify adimi henuz kosulmadi.
- Kritk eksik: staging/prod `V016` migration dogrulamasi ve RTDN/cancel/refund sync yok.

### Ne Yapacagiz (yarin ilk sirada)

1. `scripts/smoke-google-play-live-verify.ps1` ile gercek token dry-run.
2. `GET /api/chatbot/quota/status` ile plan/quota sonucunu verify et.
3. Gercek cihazda AI call -> profile quota dususu + paywall redirect UX smoke.
4. Opsiyonel: `SecuritySmokeAllowedOrigin` verip CORS security smoke adimini zorunlu PASS'e cek.

## Active Goal

Ship production-safe AI entitlement model:
- 7-day free trial
- trial: 25k token/day
- post-trial free: AI disabled
- premium: 50k/day
- premium+: 100k/day
- speech flows on 70B, utility flows on cheaper model

## Done Today

- [x] Plan-aware AI entitlement foundation implemented.
- [x] `users.ai_plan_code` added in migration `V016`.
- [x] Subscription activation paths updated to persist plan code.
- [x] Quota service integrated with entitlement limits and access control.
- [x] `GET /api/chatbot/quota/status` extended with entitlement metadata.
- [x] Model routing service added (`speech` vs `utility` model split).
- [x] Routing wired into Chatbot/AI proxy/daily content/grammar services.
- [x] Config keys added to app properties and `.env.example`.
- [x] New entitlement and model-routing tests added.
- [x] Broken tests fixed for Groq method signature changes.
- [x] Backend full test suite PASS (`mvn -q test`).
- [x] Backend container rebuilt with latest code (`docker compose up -d --build backend`).
- [x] Flyway runtime verification PASS: `V016` applied on live DB.
- [x] Rollout regression PASS: `verify-rollout.ps1 -Mode nonprod-smoke`.
- [x] Free-launch preflight PASS: `verify-rollout.ps1 -Mode prod-preflight -SkipPaymentChecks -SkipAlertmanagerChecks`.
- [x] Google Play server-side subscription verification service added (`GooglePlaySubscriptionVerificationService`).
- [x] `/api/subscription/verify/google` now supports live mode when mock verification is disabled.
- [x] Product/base-plan to internal plan mapping added (env/property based).
- [x] Google live-mode controller tests added and passing.
- [x] Post-trial/free AI access response hardened: `ai-access-disabled` now returns `403` (+ `upgradeRequired=true`) instead of generic `429`.
- [x] Full backend test suite rerun PASS after Google + paywall changes (`mvn -q test`).
- [x] Rollout gates rerun PASS after Google + paywall changes (`nonprod-smoke` + `prod-preflight --skip payment/alert`).
- [x] Flutter API layer now maps `403 + upgradeRequired` to `ApiUpgradeRequiredException`.
- [x] Flutter paywall redirect wired in core AI flows (chat/exam/dictionary/quick-dictionary/translation/reading/writing).
- [x] Flutter API contract test added for `403 + upgradeRequired` mapping.
- [x] Subscription ekraninda hardcoded `DEMO_MODE=true` kaldirildi; demo bypass artik `--dart-define=SUBSCRIPTION_DEMO_MODE=true` ile aciliyor (default: false).
- [x] Mobile IAP toggle build-flag ile kontrol ediliyor (`ENABLE_MOBILE_IAP`, default: true).
- [x] `scripts/check-runtime-prod-flags.ps1` guclendirildi:
- [x] Flutter subscription demo default guard (`SUBSCRIPTION_DEMO_MODE=false`) eklendi.
- [x] Workflow/script taramasinda `SUBSCRIPTION_DEMO_MODE=true` release ihlali kontrolu eklendi.
- [x] Container yokken/null trim hatasi duzeltildi.
- [x] `check-runtime-prod-flags.ps1` Docker erisimiyle tekrar kosuldu -> PASS.
- [x] Rollout gate'ler tekrar kosuldu -> PASS:
- [x] `verify-rollout.ps1 -Mode nonprod-smoke -ProjectName flutter-project-main`
- [x] `verify-rollout.ps1 -Mode prod-preflight -ProjectName flutter-project-main -SkipPaymentChecks -SkipAlertmanagerChecks`
- [x] Flutter contract regression test tekrar kosuldu -> PASS:
- [x] `flutter test test/api_service_contract_test.dart`
- [x] `verify-rollout.ps1 -Mode prod-preflight -ProjectName flutter-project-main` (skip olmadan) dogrulandi:
- [x] Once env eksik listesi bulundu (`ALERTMANAGER_*`, `APP_SECURITY_AUTH_GOOGLE_CLIENT_IDS`).
- [x] Eksikler gecici env ile tamamlaninca full preflight PASS alindi.
- [x] Entitlement/paywall backend test seti PASS:
- [x] `mvn -q "-Dtest=AiEntitlementServiceTest,ChatbotControllerTest,SubscriptionControllerGoogleLiveModeTest" test`
- [x] `.env.example` prod-preflight tam set ile hizalandi (`SPRING_DATA_REDIS_SECURITY_PASSWORD`, `APP_SECURITY_AUTH_GOOGLE_CLIENT_IDS` eklendi).
- [x] Iyzico production zorunlulugu kaldirildi:
- [x] `docker-compose.prod.yml` icinden `IYZICO_*` zorunlu envleri cikarildi.
- [x] `validate-prod-alert-routing.ps1` odeme env kontrolunu Google Play Billing only moduna aldi.
- [x] `validate-prod-alert-routing.ps1` compose validationi yalnizca `SkipAlertmanagerChecks` ile gevsetecek sekilde duzeltildi.
- [x] `application-prod.properties` icinden iyzico satirlari cikarildi (prod profile artik iyzico degiskeni zorlamiyor).
- [x] Flutter subscription akisindan iyzico fallback/webview kaldirildi; mobilde sadece IAP kullaniliyor.
- [x] Full `prod-preflight` sadece alert webhook envleri ile PASS (Iyzico env olmadan).
- [x] Full `prod-preflight` tekrar kosuldu: varsayilan ortamda artik sadece `ALERTMANAGER_*` eksikleri blokluyor.
- [x] AI access gating `ChatbotController` icinde tek noktaya alindi (`enforceAiAccess`):
- [x] post-trial FREE user tum AI endpointlerde tutarli `403 + reason=ai-access-disabled + upgradeRequired=true` aliyor.
- [x] `generate-sentences` cache-hit path'i ve `check-grammar` endpointi de ayni paywall davranisina alindi.
- [x] Controller regression testleri eklendi:
- [x] `generateSentencesReturnsUpgradeRequiredWhenAiAccessDisabledEvenIfCacheHit`
- [x] `checkGrammarReturnsUpgradeRequiredWhenAiAccessDisabled`
- [x] New E2E smoke script eklendi: `scripts/smoke-ai-entitlement-flow.ps1`.
- [x] `verify-rollout.ps1 -Mode nonprod-smoke` icine `ai-entitlement-smoke` adimi eklendi.
- [x] Backend rebuild sonrasi smoke/preflight tekrar PASS:
- [x] `pwsh -File scripts/smoke-ai-entitlement-flow.ps1 -BackendBaseUrl http://localhost:8082 -ProjectName flutter-project-main`
- [x] `pwsh -File scripts/verify-rollout.ps1 -Mode nonprod-smoke -ProjectName flutter-project-main`
- [x] `pwsh -File scripts/verify-rollout.ps1 -Mode prod-preflight -ProjectName flutter-project-main`
- [x] Flutter Neural Word Network game module added:
- [x] New files: game screens (`menu/play/results/wrapper`), BLoC (`event/state/bloc`), models/data/utils, neural widgets.
- [x] Practice tab integration done: new `Neural Oyun` entry opens `NeuralGamePage`.
- [x] Added dependencies: `flutter_bloc`, `equatable` (`flutter pub get` complete).
- [x] Flutter quality checks:
- [x] `flutter analyze` on neural game module -> PASS (no issues).
- [x] `flutter analyze lib/screens/practice_page.dart` -> only 1 low-priority info (`prefer_const_constructors`).
- [x] Regression tests re-run:
- [x] `flutter test test/api_service_contract_test.dart` -> PASS
- [x] `mvn -q "-Dtest=AiEntitlementServiceTest,ChatbotControllerTest,SubscriptionControllerGoogleLiveModeTest" test` -> PASS
- [x] Prod gate re-check:
- [x] `pwsh -File scripts/verify-rollout.ps1 -Mode prod-preflight -ProjectName flutter-project-main` -> PASS
- [x] Neural game automated test set added:
- [x] `test/unit/neural_game_bloc_test.dart` (start, score/combo, duplicate-word, invalid-word, timer-finish)
- [x] `test/neural_game_page_smoke_test.dart` (menu -> play -> menu)
- [x] `test/neural_game_results_screen_test.dart` (best-score persistence / new-best state)
- [x] `flutter test test/unit/neural_game_bloc_test.dart test/neural_game_page_smoke_test.dart` -> PASS
- [x] `flutter analyze test/unit/neural_game_bloc_test.dart test/neural_game_page_smoke_test.dart` -> PASS
- [x] `flutter test test/neural_game_results_screen_test.dart test/unit/neural_game_bloc_test.dart test/neural_game_page_smoke_test.dart` -> PASS
- [x] `flutter analyze test/neural_game_results_screen_test.dart` -> PASS
- [x] Repo secret hygiene guclendirildi: `.gitignore` icine `secrets/` eklendi.
- [x] Secret scan (workspace) tekrarlandi:
- [x] hardcoded `gsk_` key izi bulunmadi.
- [x] Flutter source icinde service-account/private key izi bulunmadi.
- [x] Google Play live dry-run tooling eklendi:
- [x] `scripts/smoke-google-play-live-verify.ps1` (real purchase token ile `/api/subscription/verify/google` smoke)
- [x] `docs/GOOGLE_PLAY_LIVE_DRY_RUN.md` (preconditions + komut + expected outcomes)
- [x] Flutter IAP plan mapping hotfix: `PREMIUM`/`PREMIUM_PLUS` planlari da productId map'e eklendi, store query ID set'i 4 urune genisletildi (`pro_*` + `premium_*`).
- [x] Subscription UI hotfix: `SubscriptionPage` tek kart gosterecek sekilde sinirlandi (oncelik `PRO_MONTHLY`), kart fiyat etiketi gecici olarak `20 TRY` gosteriyor.
- [x] `verify-rollout.ps1 -Mode prod-preflight -ProjectName flutter-project-main` tekrar PASS
- [x] Release gate sirasi tekrar PASS:
- [x] `verify-rollout.ps1 -Mode nonprod-smoke -ProjectName flutter-project-main` -> PASS
- [x] `verify-rollout.ps1 -Mode prod-preflight -ProjectName flutter-project-main` -> PASS
- [x] Not: `security-cors-headers-smoke` step'i `SecuritySmokeAllowedOrigin` verilmedigi icin SKIP.
- [x] `generate-sentences` parse resilience hotfix:
- [x] malformed/truncated LLM JSON ciktilarinda strict parse fallback + lenient object/field recovery eklendi (`ChatbotController`).
- [x] regression testi eklendi: `generateSentencesRecoversFromTruncatedJsonWithAtLeastOneValidObject`.
- [x] backend container hotfix ile yeniden build/start edildi (`docker compose up -d --build backend`).
- [x] Flutter auth resilience hotfix:
- [x] `ApiService` icinde protected endpointlerde `401` alindiginda `/api/auth/refresh` ile tek-seferlik token yenileme + retry eklendi.
- [x] AI endpointlerinin tamami (`chatbot/*`) bu retry mekanizmasina alindi.
- [x] contract test eklendi: `chatbotGenerateSentences refreshes token once and retries on 401`.
- [x] Backend sentence-generation reliability hotfix:
- [x] `ChatbotController` parse fallback'i genisletildi: strict JSON -> lenient JSON -> free-text extraction -> deterministic sentence fallback.
- [x] Model bos/gecersiz cikti verdiginde `generate-sentences` artik `500` yerine `200` donuyor (degrade-safe response).
- [x] canli smoke dogrulama: `word=focus` istegi parser-fallback ile `200` dondu (count=5).
- [x] Global Groq JSON-mode reliability hotfix:
- [x] `GroqService` artik `json_validate_failed/response_format` 400 durumunda otomatik olarak response_format'siz tek-sefer fallback deniyor (merkezi tum JSON endpointler icin).
- [x] `AiProxyService` parse-guvenli fallback payload uretiyor (dictionary/reading/writing/exam scope'lari icin), bos/bozuk AI cevabinda 500 yerine kontrollu JSON donuyor.
- [x] Yeni testler eklendi ve PASS:
- [x] `AiProxyServiceTest`
- [x] `mvn -q "-Dtest=GroqServiceTest,AiProxyServiceTest,ChatbotServiceTest,GrammarCheckServiceTest,ChatbotControllerTest" test`
- [x] Canli backend mini smoke tekrarlandi (register + 6 endpoint):
- [x] `check-translation`, `check-grammar`, `dictionary-lookup-detailed`, `reading-generate`, `writing-generate-topic`, `exam-generate` hepsi HTTP `200`.
- [x] Not: `dictionary-lookup-detailed` ve `reading-generate` bu turda `fallback=true` payload ile dondu (hard-fail yok, degrade-safe).
- [x] Rescue-model (`llama-3.3-70b-versatile`) fallback devreye alinip backend yeniden build edildi (`docker compose up -d --build backend`).
- [x] Canli smoke recheck (2026-02-20 21:54 UTC):
- [x] `dictionary-lookup-detailed` ve `reading-generate` yine HTTP `200` dondu ve gercek icerik uretti (`fallback` alani yok).
- [x] Backend loglari dogrulandi: utility model `json_validate_failed` aldiginda rescue model basariyla devreye girdi; `fallback payload used` logu gorulmedi.
- [x] Quota smoke: ayni akista `tokensUsed=7426` goruldu (profilde token dusumu backend tarafinda calisiyor).
- [x] `eerenulutass@gmail.com` (userId=4) icin reset islemi tamamlandi:
- [x] `user_progress` -> `total_xp=0`, `level=1`, `current_streak=0`
- [x] `words`, `sentences`, `sentence_practices` -> temizlendi (0 kayit)
- [x] Daily reading/writing cache mimarisi eklendi (seviye bazli, gunluk tek icerik):
- [x] backend service'ler: `DailyReadingService`, `DailyWritingTopicService`, `DailyLevelSupport`
- [x] yeni endpoint'ler:
- [x] `GET /api/content/daily-reading?level=A1..C2`
- [x] `GET /api/content/daily-writing-topic?level=A1..C2`
- [x] scheduler prewarm genisletildi: gunluk tum seviyeler icin reading + writing cache uretimi
- [x] daily endpointlerde AI access paywall korumasi eklendi (`403 + upgradeRequired=true`)
- [x] Flutter reading/writing daily mode'a alindi:
- [x] Reading: artik daily endpointten geliyor, sonuc ekrani `Ayni Testi Tekrar Coz` davranisinda (yeni pasaj uretmiyor)
- [x] Writing: word-count secimi kaldirildi, sadece seviye secimi var, `Gunun Konusunu Getir` akisi eklendi
- [x] Writing: ayni seviyede gunluk konu sabit, `Ayni Konuyu Tekrar Coz` akisi eklendi
- [x] Canli smoke:
- [x] ayni seviyede art arda cagri -> ayni reading/writing icerigi (same=True)
- [x] post-trial FREE kullanici daily writing endpointinde dogru paywall aliyor (`403 ai-access-disabled`)
- [x] Cevirmede tekrar eden cumle problemi icin `fresh` mod eklendi:
- [x] backend `/api/chatbot/generate-sentences` artik `fresh=true` isteginde sentence cache'i bypass ediyor ve varyasyon seed'i ile yeni set uretiyor.
- [x] Flutter `TranslationPracticePage` artik sentence uretiminde `fresh=true` gonderiyor.
- [x] AI Sozluk global cache eklendi (cross-user hizlandirma):
- [x] backend dictionary endpointleri (`lookup`, `lookup-detailed`, `explain`, `generate-specific-sentence`) Redis cache ile cevap veriyor.
- [x] Reading/Writing gunluk tamamlama UX iyilestirmeleri:
- [x] Reading: bugun tamamlanan seviye tik'i + bugunku cevaplari geri acma (dogru/yanlis inceleme) + sonuc ekraninda `Baska Seviye Sec`.
- [x] Reading: yeni pasaj algisi yaratan refresh davranisi kaldirildi; gunluk ayni test tekrar coz akisi korundu.
- [x] Writing: seviye kartlarinda gunluk tik eklendi, metin uzunlugu odagi UI'dan kaldirildi (yalnizca seviye odakli akış).
- [x] Reading seviye farklilastirma guclendirildi:
- [x] backend reading generation CEFR bazli (A1..C2) profile'a alindi, C1/C2 ayrimi sertlestirildi.
- [x] Neural oyun V2:
- [x] iki mod eklendi (`Iliskili Kelime`, `Turkce Karsilik`),
- [x] semantik kabul genisletildi (alias/synonym; `innovation -> improvement` dahil),
- [x] TR mode'da node'larda Turkce karsilik gosterimi eklendi.
- [x] Neural kabul motoru sertlestirildi:
- [x] normalization (TR karakter normalize), typo/fuzzy toleransi (levenshtein), mode-bazli ipucu metni eklendi.
- [x] Reading C1/C2 ayni icerik riski azaltildi:
- [x] daily reading cache key version'i `v2`ye alindi (`daily_reading_v2_*`) -> ayni gun yeni CEFR icerigi regenerate olur.
- [x] reading promptunda CEFR farklandirma kurali sertlestirildi (C2 > C1 soyut yogunluk).
- [x] Global/TR feature-flag temeli eklendi (Flutter):
- [x] yeni config: `flutter_vocabmaster/lib/services/app_market_config.dart`
- [x] dart-define flags: `APP_MARKET=auto|tr|global`, `APP_ENABLE_EXAMS_GLOBAL=false|true`
- [x] `PracticePage` tablari locale+flag bazli hale getirildi; globalde `Sınavlar` default gizli, TR'de acik.
- [x] Konusma sekmesindeki `IELTS & TOEFL` sinav karti da ayni flag ile kosullandirildi.
- [x] OAuth/401 akisi hardening:
- [x] `ApiService` token refresh cagrilari singleton lock ile serialize edildi (`_refreshInFlight`) -> paralel 401 dalgalarinda refresh-token reuse riski azaltildi.
- [x] Root-cause dogrulandi: backend logu `Refresh token reuse detected` (userId=4) kayitlari verdi.
- [x] Profil UX iyilestirmesi:
- [x] PRO kullanici icin de `Aboneligi Yonet` butonu eklendi (`profile_page.dart`) ve `SubscriptionPage`e dogrudan gecis saglandi.
- [x] Premium tema sistemi (5 tema) eklendi:
- [x] yeni dosyalar: `lib/theme/app_theme.dart`, `lib/theme/theme_catalog.dart`, `lib/theme/theme_provider.dart`
- [x] tema profilleri: `Ice Blue (free)`, `Neural Glow (500 XP)`, `Midnight Focus (1000 XP)`, `Emerald Calm (1500 XP)`, `Solar Energy (2000 XP)`
- [x] `AnimatedBackground` tema-bazli gradient + 5 particle style (rain/neural/float/pulse/energy) destekleyecek sekilde guncellendi.
- [x] `main.dart` icinde global `ThemeProvider` baglandi (MultiProvider), XP degisimi ile tema kilitleri dinamik guncelleniyor.
- [x] `ProfilePage` tema secimi gercek unlock mantigina alindi (kilit/progress/aktif tema secimi + persistence).
- [x] `ModernBackground` + `ModernCard` tema-aware hale getirildi; kart gradient/border/glow renkleri secili temadan dinamik okunuyor.
- [x] dot/line/grid pattern painter'lari tema rengi alacak sekilde parametrize edildi.
- [x] Build blocker hotfix: `profile_page.dart` tema karti icindeki spread-list kapanis syntax hatasi (`...[]`) duzeltildi.
- [x] Tema unlock politikasi guncellendi:
- [x] aktif PRO abonelik varsa premium temalar XP'den bagimsiz unlock oluyor.
- [x] `ThemeProvider` icine `hasPremiumAccess` eklendi, `main.dart` + `ProfilePage` uzerinden abonelik durumu senkronize edildi.
- [x] `ProfilePage._loadSubscriptionInfo` sonrasinda `_syncThemeXp()` cagrisi eklendi (abonelik response geldikten sonra tema kilidi aninda guncelleniyor).
- [x] Tema XP gereksinimi gecici olarak kapatildi (test/dogfooding): tum temalar secilebilir (`ThemeProvider._unlockAllThemesForNow=true`).
- [x] Neural oyun kabul motoru yumusatildi:
- [x] phrase/token kabul (cumle icinde gecen dogru kelimeyi yakalar),
- [x] stem + fuzzy tolerans araligi genisletildi,
- [x] yanlis cevapta combo sifirlama yerine 1 kademe dusurme (daha interaktif akiş),
- [x] uyarlanabilir ipucu mesaji (kalan kelimelerden dinamik preview),
- [x] debug log satirlari eklendi (`[NeuralGame][ISO_TIME][ACCEPT|REJECT|DUPLICATE] ...`).
- [x] Tema yayilimi genisletildi:
- [x] `NavigationMenuPanel` tema-aware hale getirildi (drawer gradient, orb/rain/sparkle, header/footer, aktif item renkleri secili temaya baglandi).
- [x] `RepeatPage` icindeki hardcoded mavi tonlar kaldirildi; orb/header/card/CTA ve metin vurgu renkleri secili temaya baglandi.
- [x] Neural oyun accepted input havuzu genisletildi:
- [x] center-word soft association listeleri eklendi (travel dahil `plane`, `abroad`, `tourist` vb.),
- [x] related mode'da dogal kelime fallback (`soft:*`) kabul yolu eklendi,
- [x] node yerlesiminde `total` dinamiklestirildi (daha cok accepted kelimede overlay riski azaldi).
- [x] Tema yayilimi ikinci dalga tamamlandi (UI hardcoded blue cleanup):
- [x] `HomePage` ust kart, istatistik kartlari, gunluk hedef, haftalik aktivite ve hizli erisim butonlari secili tema renklerine baglandi.
- [x] `WordsPage` secili gun kutusu, bos durum paneli, seslendirme chip'leri, form focus/dropdown renkleri tema-aware hale getirildi.
- [x] `SentencesPage` ust FAB/search/stat/filter ve sentence highlight/border renkleri tema-aware hale getirildi.
- [x] kelime detay/modaller: `WordSentencesModal` + `AddSentenceModal` icindeki gradient/border/accent renkleri secili tema ile senkronlandi.
- [x] `NeonButton` globalde tema aware yapildi (`Cümleler` / `Cümle Ekle` aksiyonlarinda mavi sabit kaldirildi).
- [x] Tum temalara "merkez patlama" hissi eklendi:
- [x] `AnimatedBackground` icine tema renkleriyle calisan merkez burst katmani (`_buildCoreBurst`) eklendi; Solar'daki hissiyat diger temalara da tasindi.
- [x] Profil tema temizligi tamamlandi:
- [x] `ProfilePage` ilk karttaki `Toplam Kelime / Gun Serisi / Seviye` stat kartlari secili tema renklerine baglandi.
- [x] `Tema Secimi` alanindaki ikon, alt bilgi (`Aktif tema`) ve accent metinleri secili tema ile senkronlandi.
- [x] `Hesap Ayarlari` karti + tile iconlari + ayar dialog baslik iconlari tema accent rengine cekildi; `Cikis Yap` metni sabit pembe yerine tema accent oldu.
- [x] Alt menu global tema uyumu:
- [x] `BottomNav` merkezi widget'i tema-aware hale getirildi (arka plan, secili tab gradient/glow, center FAB, text/icon renkleri).
- [x] 401 auth-resilience genisletmesi:
- [x] `ApiService` icinde daha once direct auth header kullanan core endpointler (`words`, `sentences`, `daily content`, `sentence stats`) de `_withProtectedRetry` kapsamına alindi.
- [x] Boylece token expire senaryosunda refresh+retry tum kritik API akislarinda tutarli calisiyor.
- [x] Neural oyun UX + tema v3:
- [x] neural widget'larin tamami secili tema renklerine baglandi (`particle`, `center node`, `connection`, `input`, `combo/score`, `glass`).
- [x] `NeuralGamePlayScreen` icine hizli oneriler (`ActionChip`) eklendi; kullanici cikmaza girdiginde tek tikla kabul edilebilir cevap gonderebiliyor.
- [x] `NeuralGameBloc` loose-association kabulunde token taramasi genisletildi, `innovation` seti icin `improvement/progress/upgrade` gibi beklenen cevaplar eklendi.
- [x] Tema yayilimi final pass:
- [x] `Gunun Kelimeleri` kartlari (`DailyWordCard`) secili temaya baglandi (gradient/border/glow/accent aksiyonlar).
- [x] `WordOfTheDayModal` secili tema ile uyumlu hale getirildi (dialog gradient, progress, step kartlari, quiz secim rengi, ozet aksiyonlari).
- [x] `ProfilePage` kalan fallback mavi noktalar temizlendi:
- [x] avatar secim popup, profil goruntuleme dialogu, initials/progress indikatorleri, scaffold arka plani ve tema secim karti taban rengi secili temaya baglandi.
- [x] `BottomNav` + neural play icinde default-theme fallbackleri kaldirildi; secili tema dogrudan provider'dan okunuyor.
- [x] 401 auth-resilience v2:
- [x] `ApiService` icinde protected call akisi refresh sonrasinda da `401` ise artik `ApiUnauthorizedException` firlatiyor (sessiz fail yerine net durum).
- [x] `AiPaywallHandler` unauthorized durumunu da ele aliyor: snack + logout + `LoginPage`e yonlendirme.
- [x] `AIBotChatPage` ve `ExamChatPage` hata akislarinda merkezi handler kullanimi ile 401/upgrade davranisi tek noktaya alindi.
- [x] DB parity local recheck (2026-02-23):
- [x] `pwsh -File scripts/check-db-parity.ps1 -ProjectName flutter-project-main` -> PASS
- [x] `flyway_schema_history` uzerinden latest migration `016` (`add ai plan code to users`) dogrulandi.
- [ ] Staging/prod `V016` dogrulamasi halen acik (bu workspace'te staging/prod erisimi yok).
- [x] Google Play lifecycle reconciliation foundation eklendi (2026-02-23):
- [x] yeni scheduled service: `GooglePlaySubscriptionReconciliationService` (`@Scheduled`, UTC cron, max-user batching).
- [x] state-aware sync davranisi:
- [x] `ACTIVE/GRACE` (ve policy'ye gore `ON_HOLD`) durumlarinda kullanici abonelik bitis/plani Google snapshot ile senkronlanir.
- [x] `CANCELED` + future expiry durumunda kullanici expiry sonuna kadar premium kalir.
- [x] `REVOKED/EXPIRED` ve non-eligible state durumlarinda local entitlement downgrade edilir (`FREE`).
- [x] yeni config: `app.subscription.google-play.reconciliation.*` (+ `.env.example`).
- [x] yeni unit test seti eklendi: `GooglePlaySubscriptionReconciliationServiceTest`.
- [x] Reconciliation bean wiring fixi uygulandi (`GooglePlaySubscriptionReconciliationService` constructor `@Autowired`).
- [x] Dockerized hedef backend test seti PASS:
- [x] `mvn -q "-Dtest=GooglePlaySubscriptionReconciliationServiceTest,SubscriptionControllerGoogleLiveModeTest,AiEntitlementServiceTest,ChatbotControllerTest" test`
- [x] `scripts/smoke-google-play-live-verify.ps1` PowerShell 7 uyumlulugu duzeltildi (`-SkipHttpErrorCheck`, net HTTP status/body output).
- [x] Live Google verify recheck (2026-02-23) mevcut son token ile kosuldu:
- [x] sonuc `HTTP 400` + `{"code":"INVALID_PURCHASE","error":"Subscription is not active"}` (token aktif degil/stale).
- [x] Entitlement kontrolu ayni anda dogrulandi:
- [x] `GET /api/chatbot/quota/status` -> `planCode=PREMIUM`, `tokenLimit=50000`, `aiAccessEnabled=true`.

## Now Working On

- [ ] Validate real user flow:
- [ ] AI call -> profile quota decreases
- [x] trial end user -> AI endpoints blocked consistently (automated smoke + controller tests)
- [ ] premium/premium+ users -> correct daily quota shown and enforced
- [ ] Validate Google Play live flow with real credentials and real purchase token in nonprod/prod-like env.
- [ ] `scripts/smoke-google-play-live-verify.ps1` ile gercek test purchase token dry-run (200 verified/already-verified beklenir).
- [ ] Flutter paywall UX QA:
- [ ] AI ekraninda upgrade mesaji + subscription acilisi beklenen gibi mi
- [ ] subscription ekranindan geri donuste state tutarliligi
- [ ] Neural game QA:
- [ ] menu -> play -> results akisi fiziksel cihazda UX/fps kontrolu
- [ ] farkli ekran boyutlarinda node yerlesimi overlap kontrolu
- [ ] game best-score persistence ve tekrar-oyna akisi manuel dogrulama
- [ ] Local `.env` prod alert vars su an bos:
- [x] `ALERTMANAGER_DEFAULT_WEBHOOK_URL`, `ALERTMANAGER_CRITICAL_WEBHOOK_URL`, `ALERTMANAGER_WARNING_WEBHOOK_URL` `.env` icine eklendi.
- [x] `APP_SECURITY_AUTH_GOOGLE_CLIENT_IDS` `.env` icine eklendi.
- [x] `APP_SUBSCRIPTION_GOOGLE_PLAY_PACKAGE_NAME` `.env` icine eklendi (`com.VocabMaster`).
- [x] `APP_SUBSCRIPTION_GOOGLE_PLAY_SERVICE_ACCOUNT_HOST_PATH` `.env` icine eklendi (`C:\\flutter-project-main\\secrets\\prime-poetry-425219-q8-9d5ed643a714.json`).
- [x] Google Play service account JSON dosyasi host path'te dogrulandi.

## Next Priority Queue

- [ ] Optional: global app-level interceptor ile tum AI ekranlari icin tek noktadan upgrade yonlendirmesi.
- [ ] Neural game test coverage'i genislet:
- [ ] node placement/responsive layout widget test (kucuk ekran + buyuk ekran)
- [ ] Add dashboard metrics:
- [ ] token usage by plan
- [ ] token usage by AI scope/model
- [ ] Add RTDN / cancellation / refund sync flow for Google subscriptions.
- [ ] run pre-release gates:
- [x] `SecuritySmokeAllowedOrigin` verilerek nonprod-smoke icindeki `security-cors-headers-smoke` adimi zorunlu PASS dogrulandi.

## Important Issues (Prod Blocking / High Risk)

- [x] Security: rotate exposed `GROQ_API_KEY` (user-confirmed, 2026-02-18).
- [x] Security: rotate exposed `APP_SECURITY_JWT_SECRET` (shared during session, 2026-02-18) and force-refresh sessions.
- [ ] Security: verify old Groq key revocation and secret-manager parity before release cut.
- [x] Security: ensure no provider secrets are bundled into Flutter artifacts.
- [x] Security (2026-03-04): remove `.env` asset bundling path before release; `flutter_vocabmaster/pubspec.yaml` no longer packages `.env` and release builds default to `https://api.klioai.app`.
- [x] Security (2026-03-04): docker runtime security headers (`Referrer-Policy/CSP/HSTS/Permissions-Policy`) fixlendi; `smoke-security-cors-headers.ps1` PASS.
- [ ] Config: provide real `APP_SUBSCRIPTION_GOOGLE_PLAY_PACKAGE_NAME` and service account file path on target environment.
- [ ] Config: gercek prod degerleriyle `.env`/secret manager tamamla:
- [x] `ALERTMANAGER_DEFAULT_WEBHOOK_URL`, `ALERTMANAGER_CRITICAL_WEBHOOK_URL`, `ALERTMANAGER_WARNING_WEBHOOK_URL` local `.env` set edildi.
- [ ] `APP_SECURITY_AUTH_GOOGLE_CLIENT_IDS`
- [x] `APP_SUBSCRIPTION_GOOGLE_PLAY_SERVICE_ACCOUNT_HOST_PATH` altindaki JSON dosyasi yerlestirildi (local).
- [ ] Migration: verify all environments (staging/prod) have applied `V016`.
- [~] Abuse risk: account-age-only trial gating was replaced with `trialEligible` + device/IP heuristics on 2026-04-16; stronger identity signals (disposable-email/device attestation/payment/phone) are still pending before scale.
- [ ] Observability gap: neural game icin event/usage metric yok (start, finish, avg score, avg found words).

## Session Notes

Checkpoint inherited from 2026-02-17:
- quota UI + endpoint feature was already near QA handoff.
- this session added backend entitlement architecture for monetization path.
- runtime now includes `V016` and smoke/preflight gates are green after rebuild.
- latest check: full `prod-preflight` PASS after alert webhook env values were provided.
- latest check: full `prod-preflight` PASS after Google Play package + service-account host-path configuration.
- 2026-02-18 current local check: `verify-rollout.ps1 -Mode prod-preflight -ProjectName flutter-project-main` FAILED early because Docker daemon/backend container was not running.
- 2026-02-18 registration diagnostic: `/api/auth/register` returns `400 Registration failed` when email already exists (seen for Google-login accounts); unique email registration is healthy (`200`).
- 2026-02-18 IAP diagnostic: device log shows `Products not found` for all 4 product IDs (`pro_monthly_subscription`, `pro_annual_subscription`, `premium_monthly`, `premium_plus_monthly`); installed app has `installerPackageName=null` (sideload/debug install), so Play Billing catalog is not being resolved on-device.
- 2026-02-18 Android target SDK fix: `flutter_vocabmaster/android/app/build.gradle` updated from `targetSdk = flutter.targetSdkVersion` to `targetSdk = 35` to satisfy Play API level requirement.
- 2026-02-18 OAuth tester reset: `eerenulutass@gmail.com` (`userId=4`) was manually reset from `PREMIUM` to `FREE` (`subscription_end_date=NULL`) in local DB to re-open purchase/paywall QA flow.
- 2026-02-19 device re-check: app is now Play-installed (`installerPackageName=com.android.vending`, `targetSdk=35`) but Google Billing still returns `Products not found` for all queried IDs; remaining blocker is Play Console product/base-plan activation + tester/track alignment.
- 2026-02-20 purchase-verify diagnostic: `/api/subscription/verify/google` required JWT (`APP_SECURITY_JWT_ENFORCE_AUTH=true`) and Flutter verify call was missing `Authorization` header; fixed in `subscription_service.dart`.
- 2026-02-20 local runtime fix: `docker-compose.yml` updated to mount Google service-account JSON and default `APP_SUBSCRIPTION_GOOGLE_PLAY_SERVICE_ACCOUNT_FILE` to `/run/secrets/google-play-service-account.json`.
- 2026-02-20 Google OAuth fix: service-account JWT `aud` claim switched to string format in `GooglePlaySubscriptionVerificationService`; token request error (`invalid_grant failed audience check`) resolved.
- 2026-02-20 post-fix probe: `/api/subscription/verify/google` now returns `400 INVALID_PURCHASE` for dummy token (expected), confirming provider path is operational.
- 2026-02-20 Flutter purchase UX hardening: `already owned` errors now trigger `restorePurchases()` auto-sync path in `SubscriptionService`; verify request includes auth and logs non-200 body.
- 2026-02-20 SubscriptionPage UX hardening: active subscription status is fetched and shown; `Hemen Yukselt` button is disabled/replaced with `Abonelik Aktif` when subscription is already active.
- 2026-02-20 Verify resilience hardening: purchase verification now retries user-id resolution via profile refresh and surfaces backend error categories (401/403, INVALID_PURCHASE, PROVIDER_UNAVAILABLE) as user-facing messages.
- 2026-02-20 Backend observability hardening: `SecurityConfig` logs 401/403 hits on `/api/subscription/verify/*` paths to speed up purchase verification diagnostics.
- 2026-02-20 IAP recovery hardening: `SubscriptionPage` now has explicit `Satin alimlari geri yukle` action and post-restore status refresh.
- 2026-02-20 IAP direct-exception mapping hardening: startup purchase exceptions now map `PG-GEMF-02`, `BillingResponse.error`, `itemAlreadyOwned` to actionable Turkish messages.
- 2026-02-20 Backend Google verify diagnostics expanded: `SubscriptionController` now logs masked verify metadata (`userId`, `productId`, `tokenLen`) and success/failure reason codes.
- 2026-02-20 root-cause finding: backend Google verify log showed `INVALID_PURCHASE` with non-empty token (`tokenLen=123`) for `pro_monthly_subscription`, while user remained `FREE` and `payment_transactions` had no `GOOGLE_IAP` row.
- 2026-02-20 backend fix: `GooglePlaySubscriptionVerificationService` no longer lowercases `packageName` (case-sensitive package path preserved); this likely resolves token rejection for package `com.VocabMaster`.
- 2026-02-20 diagnostics improvement: Google verify now propagates detailed 4xx/5xx HTTP error summary (auth/permission vs invalid token distinction) to controller-level logs.
- 2026-02-20 21:00+03 runtime finding: Google verify reached backend but failed with `MISCONFIGURED` -> Android Publisher `401 permissionDenied` (`The current user has insufficient permissions to perform the requested operation.`). This is Play Console/API access permission issue, not app purchase-flow logic.
- 2026-02-20 mapping hardening: Google Play `basePlanId=monthly` is now explicitly mapped (`APP_SUBSCRIPTION_GOOGLE_PLAY_PRODUCT_PLAN_MONTHLY`, default `PREMIUM`) in all app profiles to avoid product-only mapping dependency.
- 2026-02-20 live success checkpoint: tester `eerenulutass@gmail.com` (`userId=4`) Google verify finally succeeded (`planName=PREMIUM`, `SUBSCRIPTION_STATE_ACTIVE`), DB updated with `ai_plan_code=PREMIUM` and `GOOGLE_IAP` SUCCESS transaction row.
- 2026-02-20 translation/sentence generation incident: backend log showed Groq `200 OK` but LLM output JSON was truncated (`JsonEOFException`); `ChatbotController` now recovers valid sentence objects from malformed payload instead of failing whole request.
- 2026-02-20 subscription mismatch incident (tester): user had `ai_plan_code=PREMIUM` but `subscription_end_date` was in the past (UTC), causing AI access disabled while Play showed ownership; local QA unblock applied by setting user `id=4` subscription end to `now+30 days`.
- 2026-02-20 auth incident: `APP_SECURITY_JWT_ENFORCE_AUTH=true` + access token TTL (900s) nedeniyle mobilde token suresi dolunca AI endpointleri `401` donuyordu; Flutter `ApiService`e refresh-token rotate + auto-retry eklendi.
- 2026-02-20 parser incident: Groq bazen bos/JSON-disinda cevap dondugunde `Parsed sentence list is empty` ile `500` oluyordu; controller fallback zinciri genisletildi ve bu durum kullaniciya artik degrade-safe `200` olarak donuyor.
- 2026-02-21 build/verify note: mevcut sandbox ortaminda `mvn test` local repo path sorunu (`C:\\Users\\CodexSandboxOffline\\.m2\\repository`) ve `flutter test/analyze` timeout nedeniyle otomatik testlerin tamami bu turda kosulamadi; degisiklikler kod incelemesi ile dogrulandi, cihaz/build dogrulamasi kullanici tarafinda alinacak.


