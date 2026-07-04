# KlioAI Quality and CI/CD Roadmap

Last update: 2026-07-04

This note explains why the current project maturity is strong overall but still
only medium for test coverage and weak-to-medium for CI/CD.

## Current Assessment

| Area | Current level | Why |
| --- | --- | --- |
| Backend tests | Good | Many controller, service, security, billing, quota, prompt, RTDN, notification, and migration-adjacent tests exist. |
| Flutter tests | Medium-Good | Core services and several high-risk screens are covered, including Practice discovery and navigation menu smoke tests; Play Billing/Google Sign-In/FCM still need real-device smoke. |
| Coverage gates | Medium-Good | Backend has a JaCoCo core coverage script. Flutter now has a 30% line-coverage gate; golden/device gates are still missing. |
| CI | Medium | Backend DB readiness, security scan, landing, Flutter quality, and release preflight workflows exist. |
| CD | Weak-Medium | A reproducible Android AAB artifact workflow now exists, but backend deploy and Play Console release are still operator-controlled. |

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
- [ ] Make branch protection require the merge-critical checks.
  - Script prepared: `scripts/configure-github-branch-protection.ps1`
  - Default API contexts:
    - `db-readiness` (`Backend DB Readiness`)
    - `flutter-quality` (`Flutter Quality`)
    - `trivy-fs` (`Security Scan`)
  - Still needs a GitHub token or manual GitHub UI confirmation before it is
    considered applied on the remote repository.
- [x] Keep analyzer `WARNING` and `ERROR` counts at zero.
- [ ] Burn down legacy analyzer `INFO` debt screen by screen.
  - report generator: `scripts/new-flutter-analyzer-burndown-report.ps1`
  - current dominant debt is deprecated `withOpacity` usage and const cleanup.

### Phase 2 - Coverage Gates

- [ ] Backend: keep core coverage threshold and raise it gradually from 70 to
      80, then 90 only after noisy legacy areas are excluded intentionally.
- [x] Flutter: generate coverage with `flutter test --coverage`.
- [x] Flutter: add a small script that fails if coverage drops below the current
      measured baseline.
  - current full-suite coverage observed on 2026-07-04: 30.73% line coverage
  - current gate: 30% to prevent regression without blocking normal work
- [ ] Add focused tests for:
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
  - [x] pronunciation report scoring and word-chip playback
  - [x] Practice mode discovery and horizontal selector widget smoke
  - [x] Navigation menu routing/widget smoke
  - notification preference toggles and FCM token sync
    - [x] push-opened notification empty-state widget coverage
    - [x] notification preference API contract coverage
    - [x] FCM token registration refresh/dedup unit coverage
    - [x] profile notification preference toggle widget coverage
    - [x] full Profile notification preference save flow with mocked services

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
- [ ] Upload Android signing secrets to GitHub Actions.
  - Script prepared:
    `scripts/configure-github-android-signing-secrets.ps1`
  - Required remote secrets:
    - `ANDROID_KEYSTORE_BASE64`
    - `ANDROID_KEYSTORE_PASSWORD`
    - `ANDROID_KEY_PASSWORD`
    - `ANDROID_KEY_ALIAS`
  - Still needs a repo-admin GitHub token before the script can apply the
    secrets and before the real GitHub-hosted AAB workflow can run.
- [ ] Dispatch the GitHub-hosted AAB artifact workflow after signing secrets
      are configured.
  - Script prepared:
    `scripts/dispatch-github-aab-artifact-workflow.ps1`
  - Default target:
    `.github/workflows/android-aab-artifact.yml` on `main` with
    `backend_url=https://api.klioai.app` and quality gate enabled.
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
- [ ] Apply the `production-backend` environment protection on GitHub with a
      repo-admin token and at least one required reviewer.
- [ ] Upload VPS deploy environment secrets after creating a deploy-only SSH
      key.
- [ ] Keep database migrations automatic through Flyway, but require preflight
      migration checks before production deploy.

## Practical Target

The next realistic maturity target is:

- Test coverage: `Good`
- CI/CD: `Medium-Good`

Very good CI/CD should wait until Play release, backend deploy, rollback, and
post-deploy smoke are all standardized. It is better to be manually safe than
automatically dangerous.
