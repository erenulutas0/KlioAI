# Play-Distributed AAB Smoke Checklist

Use this after uploading a new KlioAI AAB to a Play test track. Do not use a sideloaded APK/AAB for Billing or Google Sign-In validation; Play Billing catalog behavior depends on the Play-distributed install.

Before starting the phone smoke, generate a per-build report file and fill it
while testing:

```powershell
pwsh -File scripts/new-play-device-smoke-report.ps1 `
  -Tester <name> `
  -Device <device> `
  -AndroidVersion <version> `
  -PlayVersionCode <code> `
  -GitHubRunUrl <actions-run-url> `
  -ReleaseChecklistPath <checklist-path>
```

The default output path is `docs/play-smoke-reports/play-device-smoke-<timestamp>.md`.

## Build Identity

- App is installed from Google Play test track.
- Android package is `com.VocabMaster`.
- App version/build matches the uploaded AAB.
- Profile > Account Settings shows the same `version+buildNumber`.
- Backend target is `https://api.klioai.app`.
- GitHub AAB artifact workflow run URL and release checklist path are recorded
  in the generated smoke report.

## Auth

- Fresh install opens the Google-only login screen.
- Google Sign-In succeeds on the tester account.
- Email/password login is not visible.
- Profile shows the signed-in Google account.
- Profile sign out works and returns to login.
- Signing in again restores the same account data.

## Subscription

- Open Profile or subscription entry point.
- Tap `Upgrade` / subscription CTA.
- Store product list includes:
  - `pro_monthly_subscription`
  - `pro_annual_subscription`
- Monthly plan purchase/restore reaches backend verification.
- Backend result after purchase/restore:
  - `aiPlanCode=PREMIUM`
  - subscription status active
  - no stale `FREE` state after returning to Profile
- Annual plan purchase/restore maps to `PREMIUM_PLUS`.
- If annual is missing, fix Play Console product/base-plan/track/tester setup before changing app code.

## AI Entitlement

- Open Practice and run one AI-backed action.
- Open Speaking and send one short chat message; the app should return an AI answer.
- Expected for paid monthly user:
  - request succeeds
  - quota/status refresh keeps `planCode=PREMIUM`
  - remaining/used AI quota changes consistently
- Expected for free user:
  - small daily quota is available
  - quota exhaustion returns paywall/quota UX, not a generic error
- Subscription screen return path does not leave Profile or Practice in stale `FREE` state.

Optional authenticated API canary, using a fresh tester JWT from the same account:

```powershell
pwsh -File scripts/smoke-authenticated-ai-chat.ps1 -AccessToken <token>
```

## Practice UI

- Practice top selector scrolls horizontally.
- Known open issue: a thin right-edge tab sliver may still appear on some devices; keep tracking in `TODO.md` unless it blocks tapping/scrolling modes.
- These modes are visible and selectable:
  - Translation
  - Reading
  - Writing
  - Grammar
  - Speaking
  - Exams, when enabled for locale
  - Word Galaxy
  - Neural Game
- No mode shows a first-session lock icon.
- Home does not show the removed first-session 4-step task card.

## Core Regression

- Add a word.
- Add a sentence to the word.
- Open daily words.
- Open Word Galaxy and return.
- Open Neural Game, start, finish or exit, and return.
- App restart keeps auth/session state.

## Backend/Observability Checks

- `GET /api/chatbot/quota/status` matches the app-visible plan.
- `payment_transactions` has a successful `GOOGLE_IAP` row after purchase/restore.
- Prometheus receives:
  - `auth_trial_abuse_block_total` when trial grants are blocked
  - `ai_token_quota_block_total` when token quota blocks happen
- Grafana dashboard `AI Entitlement & Abuse Observability` loads after monitoring config deploy/reload.

## Pass Criteria

- Google Sign-In works from the Play-installed app.
- Monthly subscription activates backend entitlement and stays visible in Profile.
- Annual product is visible or explicitly tracked as a Play Console configuration issue.
- AI actions work according to plan/quota.
- Practice modes are discoverable without first-session locks.
- No stale subscription state remains after app restart.
