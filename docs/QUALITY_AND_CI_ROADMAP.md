# KlioAI Quality and CI/CD Roadmap

Last update: 2026-07-06

This note explains why the current project maturity is strong overall but still
only medium for test coverage and weak-to-medium for CI/CD.

## Current Assessment

| Area | Current level | Why |
| --- | --- | --- |
| Backend tests | Good | Many controller, service, security, billing, quota, prompt, RTDN, notification, and migration-adjacent tests exist. |
| Flutter tests | Medium-Good | Core services and several high-risk screens are covered, including Practice discovery, navigation menu, theme catalog/provider, and language profile smoke tests; Play Billing/Google Sign-In/FCM still need real-device smoke. |
| Coverage gates | Medium-Good | Backend has a JaCoCo core coverage script. Flutter now has a 32.5% line-coverage gate; golden/device gates are still missing. |
| CI | Medium-Good | Backend DB readiness, security scan, landing, Flutter quality, and release preflight workflows exist; Flutter analyzer is now clean at error/warning/info level. |
| CD | Medium-Good | A reproducible Android AAB artifact workflow, release checklist artifact, migration preflight gate, and protected backend deploy workflow exist. Play Console upload remains manual, and the protected backend deploy path still needs one approved real deploy before it can be called routine. |

## Why Claude Called Test Coverage "Medium"

The backend has a serious test base, so this is not a "no tests" project.
The weaker part is risk coverage:

- Flutter UI flows are large and user-facing, but many are not protected by
  widget/integration tests.
- Play Billing, Google Sign-In, FCM, Firebase Analytics, and real device
  behavior still rely mostly on manual smoke tests.
- Offline sync and XP behavior have tests now, but they should become required
  release gates because regressions here are easy to miss.
- AI prompt quality is partially tested through contract/regression tests, but
  natural-language quality still needs scenario fixtures and snapshots.

## Why CI/CD Was Called "Weak"

CI/CD is not just "some GitHub Actions exist". For production maturity, the
pipeline should reliably answer four questions:

1. Is the code safe to merge?
2. Is the release artifact reproducible?
3. Is the backend deploy repeatable and rollbackable?
4. Did production become healthy after deploy?

Current state before this update:

- Backend/security workflows existed.
- Flutter had no dedicated quality workflow.
- Release preflight was mostly local/manual.
- Backend deploy to VPS was manual.
- Play Console upload and device smoke were manual.

That is acceptable for an early solo production app, but it is not yet "very
good" CI/CD.

## Improvement Plan

### Phase 1 - CI Quality Gates

- [x] Add Flutter quality workflow:
  - `flutter pub get`
  - `flutter analyze --no-fatal-warnings --no-fatal-infos`
  - `flutter test -r compact`
- [x] Add manual release preflight workflow:
  - repo secret scan
  - backend Maven tests
  - Flutter quality gate
- [x] Make branch protection require the merge-critical checks.
  - Script used: `scripts/configure-github-branch-protection.ps1`
  - Default API contexts:
    - `db-readiness` (`Backend DB Readiness`)
    - `flutter-quality` (`Flutter Quality`)
    - `trivy-fs` (`Security Scan`)
  - Applied to `main` on GitHub with pull request review, stale approval
    dismissal, conversation resolution, force-push disable, and deletion
    disable settings.
- [x] Keep analyzer `WARNING` and `ERROR` counts at zero.
- [x] Burn down legacy analyzer `INFO` debt screen by screen.
  - report generator: `scripts/new-flutter-analyzer-burndown-report.ps1`
  - current analyzer burn-down report observed on 2026-07-05:
    `Errors=0`, `Warnings=0`, `Infos=0`
  - completed debt:
    - deprecated `Color.withOpacity(...)` calls across `flutter_vocabmaster/lib`
    - `prefer_const_constructors`
    - stale `DropdownButtonFormField.value`
    - deprecated `Matrix4.translate`
    - single-line `if` brace info findings
    - async context mounted checks in subscription/paywall paths
  - cleaned so far:
    - `ThemeSideTab`
    - `LanguageSelectionPage`
    - `ThemeCatalog`
    - remaining Flutter `lib` screens/widgets through the global opacity pass

### Phase 2 - Coverage Gates

- [x] Backend: raise the CI core coverage gate from 70 to 85.0 for current
      core backend classes.
  - local gate: `scripts/verify-rollout.ps1 -Mode local-gate`
  - DB readiness workflow gate:
    `.github/workflows/backend-db-readiness.yml`
  - release preflight backend gate:
    `.github/workflows/release-preflight.yml`
  - current observed core coverage from the local JaCoCo report:
    `85.11%` across 178 filtered core classes
  - next target after focused backend tests: stable 87; do not jump to 90
    until low-coverage provider/daily-content/support paths are either tested
    or intentionally excluded.
- [x] Flutter: generate coverage with `flutter test --coverage`.
- [x] Flutter: add a small script that fails if coverage drops below the current
      measured baseline.
  - current full-suite coverage observed on 2026-07-05: 32.56% line coverage
  - current gate: 32.5% to prevent regression without blocking normal work
- [x] Add focused tests for the highest-risk Flutter/product flows:
  - onboarding / learning profile
    - [x] source-language normalization and AI profile payload unit coverage
    - [x] onboarding learning-profile step persistence widget coverage
    - [x] complete first-run onboarding-to-login navigation coverage
  - translation direction/source-language behavior
    - [x] Spanish source profile API payload and neutral direction coverage
    - [x] Translation Practice source-language direction label widget coverage
          (`EN -> ES`, `ES -> EN`)
    - [x] generated/check translation widget flow with mocked backend responses
  - [x] XP update after online/offline word and sentence changes
    - [x] mixed numeric-string stats and string practice-sentence ids no longer
          break local XP refresh/reconciliation
  - [x] pronunciation report scoring and word-chip playback
  - [x] Practice mode discovery and horizontal selector widget smoke
  - [x] Navigation menu routing/widget smoke
  - [x] Theme picker/provider smoke and persistence coverage
  - [x] Theme catalog uniqueness/fallback/config-shape coverage
  - [x] AppColors opacity alias and shared-gradient coverage
  - [x] app language provider and language-selection screen coverage
  - [x] localized AI quota/upgrade/error formatter coverage
  - notification preference toggles and FCM token sync
    - [x] push-opened notification empty-state widget coverage
    - [x] notification preference API contract coverage
    - [x] FCM token registration refresh/dedup unit coverage
    - [x] profile notification preference toggle widget coverage
    - [x] full Profile notification preference save flow with mocked services
  - billing/paywall restore and Play purchase error handling
    - [x] subscription error mapping coverage for PG-GEMF-02,
          BillingResponse.error, already-owned restore guidance, session
          verification failure, product-plan mismatch, and provider unavailable
  - release/globalization support contracts
    - [x] exam/writing/voice model mapping coverage
    - [x] Google-only login error copy no longer suggests email login
    - [x] TR/global market config coverage for exam-module availability

### Phase 3 - Release Artifact Gates

- [x] Add workflow-dispatched Android AAB build that stores the `.aab` as a
      GitHub artifact.
  - workflow: `.github/workflows/android-aab-artifact.yml`
  - requires GitHub secrets:
    - `ANDROID_KEYSTORE_BASE64`
    - `ANDROID_KEYSTORE_PASSWORD`
    - `ANDROID_KEY_PASSWORD`
    - `ANDROID_KEY_ALIAS`
  - keeps Play upload manual for now.
- [x] Upload Android signing secrets to GitHub Actions.
  - Script used:
    `scripts/configure-github-android-signing-secrets.ps1`
  - Configured remote secrets:
    - `ANDROID_KEYSTORE_BASE64`
    - `ANDROID_KEYSTORE_PASSWORD`
    - `ANDROID_KEY_PASSWORD`
    - `ANDROID_KEY_ALIAS`
- [x] Dispatch the GitHub-hosted AAB artifact workflow after signing secrets
      are configured.
  - Script used:
    `scripts/dispatch-github-aab-artifact-workflow.ps1`
  - Verified successful run:
    `https://github.com/erenulutas0/KlioAI/actions/runs/28719711617`
- [ ] Keep Play upload manual until one or two releases pass cleanly.
- [x] Add a release checklist artifact containing:
  - version/build number
  - git commit SHA
  - backend image/deploy timestamp
  - smoke commands run
  - known manual device checks
  - template: `docs/RELEASE_CHECKLIST_TEMPLATE.md`
  - generator: `scripts/new-release-checklist.ps1`
  - Android AAB workflow uploads `klioai-release-checklist`
- [x] Add a standardized Play-installed device smoke report generator.
  - script: `scripts/new-play-device-smoke-report.ps1`
  - default output: `docs/play-smoke-reports/play-device-smoke-<timestamp>.md`
  - references canonical checklist:
    `docs/PLAY_DISTRIBUTED_AAB_SMOKE_CHECKLIST.md`

### Phase 4 - Safer CD

- [x] Replace ad-hoc tarball deploy with a versioned deploy script:
  - package backend source
  - upload artifact
  - backup current source
  - build image
  - recreate backend
  - wait for health
  - run public smoke
  - print rollback command
  - script: `scripts/deploy-backend-vps.ps1`
- [x] Add a read-only VPS deploy target checker before first real scripted
      deploy.
  - script: `scripts/check-backend-vps-deploy-target.ps1`
  - verifies compose service, build context, source shape, container name, and
    health without changing remote files.
- [x] Confirm the exact remote source path on the VPS with the read-only target
      checker.
  - confirmed build context: `/opt/vocabmaster/backend-src/backend`
- [x] Run the new backend deploy helper for one real low-risk backend deploy
      and record the result.
  - label: `ci-hardening-real`
  - date: 2026-07-04
  - command:
    `pwsh -NoProfile -File scripts\deploy-backend-vps.ps1 -Label ci-hardening-real -NoCache -Execute`
  - result: backend image rebuilt, `vocabmaster-backend` recreated, container
    health passed, and public `/actuator/health` passed.
  - rollback source backup:
    `/opt/vocabmaster/backups/deploy/backend-src-pre-codex-ci-hardening-real-20260704T170433Z.tar.gz`
- [x] Rotate internally generated production runtime secrets after the compose
      config exposure.
  - script: `scripts/rotate-prod-runtime-secrets-vps.ps1`
  - rotated: JWT secret, Redis app password pair, Redis security password pair
  - result: Redis, Redis security, and backend containers recreated; internal
    and public health checks passed
  - not rotated by script: Groq provider key, Google/Firebase service-account
    files, PostgreSQL credentials
  - latest repeat rotation on 2026-07-05 after VPS layout diagnostics: PASS;
    Redis, Redis security, and backend were recreated and health checks passed.
- [x] Add read-only prod secret parity check before scale/release approval.
  - script: `scripts/check-prod-secret-parity-vps.ps1`
  - verifies VPS secret-file presence/permissions, Redis password parity,
    required backend runtime keys, production auth/billing flags in the running
    backend container, service-account mount readability, Docker Compose render,
    and backend health without printing secret values.
  - latest read-only prod check on 2026-07-05: PASS
- [x] Add a GitHub Actions backend deploy workflow behind a protected
      environment/manual approval.
  - workflow: `.github/workflows/backend-vps-deploy.yml`
  - environment: `production-backend`
  - deploy script: `scripts/deploy-backend-vps.ps1`
  - dispatch helper:
    `scripts/dispatch-github-backend-vps-deploy-workflow.ps1`
  - environment protection helper:
    `scripts/configure-github-environment-protection.ps1`
  - VPS environment-secret helper:
    `scripts/configure-github-vps-deploy-secrets.ps1`
  - runbook: `docs/GITHUB_RELEASE_AUTOMATION_RUNBOOK.md`
- [x] Apply the `production-backend` environment protection on GitHub with a
      repo-admin token and at least one required reviewer.
- [x] Upload VPS deploy environment secrets after creating a deploy-only SSH
      key.
- [x] Smoke the protected backend deploy workflow path.
  - result: workflow reached protected-environment waiting state, then the test
    run was cancelled without touching production.
- [x] Keep database migrations automatic through Flyway, but require preflight
      migration checks before production deploy.
  - script: `scripts/run-migration-preflight.ps1`
  - release workflow: `.github/workflows/release-preflight.yml`
  - checks:
    - Testcontainers clean Postgres Flyway readiness with `-FailOnSkip`
    - Docker Compose clean DB smoke
    - explicit DB parity check for latest Flyway version, core tables,
      required indexes, and key uniqueness constraints

### Phase 5 - Crash Observability

- [x] Extract a testable `CrashlyticsService` wrapper
      (`flutter_vocabmaster/lib/services/crashlytics_service.dart`) around the
      Firebase Crashlytics handlers that were already wired in `main.dart`
      (`FlutterError.onError`, `PlatformDispatcher.instance.onError`).
  - enable-gated and try/catch-safe, mirroring `AnalyticsService`'s pattern:
    a no-op until Firebase telemetry initializes, and a recorder failure never
    throws back into the crash-reporting path itself.
  - injectable `CrashlyticsRecorder` seam lets
    `test/services/crashlytics_service_test.dart` verify the enable-gating and
    failure-swallowing logic without needing Firebase platform channels.
  - `main.dart` now also calls `CrashlyticsService.setUserId(...)` alongside
    the existing `AnalyticsService.setUserId(...)` call so crash reports can be
    correlated with a user for support/entitlement debugging.
- [x] Added a release-checklist gate: confirm the Crashlytics dashboard shows
      no new fatal crash spike for the previous release before promoting the
      next one (`docs/RELEASE_CHECKLIST_TEMPLATE.md`).
- [ ] Not done yet (follow-up, out of scope for this pass): apply the native
      `com.google.firebase.crashlytics` Gradle plugin and wire
      `flutter build ... --obfuscate --split-debug-info=...` symbol upload so
      release-mode Dart stack traces de-obfuscate in the Crashlytics console.
      Current wiring already reports Dart-level fatal/non-fatal errors without
      this; the follow-up only affects readability of obfuscated release
      stack traces.

## Practical Target

The next realistic maturity target is:

- Test coverage: `Good`
- CI/CD: `Medium-Good`

Remaining work before calling CI/CD "very good":

- Run one approved production backend deploy through the protected GitHub
  environment, then record the deploy ID, rollback backup, and smoke result.
- Keep Play upload manual until one or two GitHub-built AAB artifacts pass Play
  Console processing and device smoke without fixes.
- Raise backend core coverage to a stable 87 using focused tests for
  low-coverage service/provider paths.
- Keep Flutter coverage at or above the 32.5 baseline while adding device/golden
  coverage for Play Billing, Google Sign-In, FCM, and first-run flows.

Very good CI/CD should wait until Play release, backend deploy, rollback, and
post-deploy smoke are all standardized. It is better to be manually safe than
automatically dangerous.
