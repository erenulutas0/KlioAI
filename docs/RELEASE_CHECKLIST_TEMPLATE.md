# KlioAI Release Checklist

Release ID: `{{RELEASE_ID}}`  
Generated at: `{{GENERATED_AT_UTC}}`  
Prepared by: `{{PREPARED_BY}}`

## Release Identity

| Field | Value |
| --- | --- |
| Flutter version/build | `{{FLUTTER_VERSION_BUILD}}` |
| Git commit SHA | `{{GIT_COMMIT_SHA}}` |
| Git branch | `{{GIT_BRANCH}}` |
| Backend URL | `{{BACKEND_URL}}` |
| Backend deploy timestamp | `{{BACKEND_DEPLOY_TIMESTAMP}}` |
| Backend image/source label | `{{BACKEND_IMAGE_OR_LABEL}}` |
| Android artifact | `{{ANDROID_ARTIFACT}}` |

## Automated Gates

- [ ] Repo secret scan passed: `pwsh -File scripts/scan-repo-secrets.ps1`
- [ ] Flutter quality gate passed: `pwsh -File scripts/flutter-quality-gate.ps1`
- [ ] Flutter coverage gate passed at or above the current 30% threshold.
- [ ] Flutter analyzer burn-down report generated when cleanup work changed analyzer debt:
      `pwsh -File scripts/new-flutter-analyzer-burndown-report.ps1`
- [ ] Backend targeted tests passed when backend code changed.
- [ ] Release AAB was built from the commit SHA above.
- [ ] No unexpected secrets, local `.env` values, or service-account JSON files are included in the artifact.

## Backend / API State

- [ ] Public API health returns `UP`: `https://api.klioai.app/actuator/health`
- [ ] Subscription plans endpoint returns current `FREE`, `PREMIUM`, and `PREMIUM_PLUS` metadata.
- [ ] Groq smoke passed after any AI provider/key/config change.
- [ ] Google Play live dry-run was considered for billing-impacting changes.
- [ ] Backend deploy result recorded if the backend was deployed for this release.

## Play Console / Policy

- [ ] Data Safety form still matches app behavior.
- [ ] Privacy policy and account deletion URLs are reachable.
- [ ] Version code is higher than the previous uploaded AAB.
- [ ] Play test track processing completed before device smoke.
- [ ] Known Play policy-sensitive surfaces checked: Google Sign-In, Google Play Billing, account deletion, data collection disclosures.

## Device Smoke

- [ ] Play-installed device smoke report generated:
      `pwsh -File scripts/new-play-device-smoke-report.ps1 -Tester <name> -Device <device> -AndroidVersion <version> -PlayVersionCode <code>`
- [ ] App version/build shown in Profile matches uploaded AAB.
- [ ] Google Sign-In works on a fresh install.
- [ ] Home loads without stale XP/weekly XP values.
- [ ] Add word and add sentence update XP immediately.
- [ ] Daily Words add/add-with-sentence saves correctly and does not show stale add buttons.
- [ ] Translation Practice works for the current Learning Profile source language.
- [ ] Speaking transcription works and does not show generic connection errors for provider failures.
- [ ] Pronunciation Practice records, evaluates, and plays problem-word audio.
- [ ] Notification permission/preference flow works.
- [ ] Push notification tap opens the expected app surface.
- [ ] Subscription restore/purchase smoke completed if billing changed.

## Release Decision

- [ ] Ship to internal test track.
- [ ] Hold release and fix blockers.
- [ ] Promote from internal test to wider track after smoke passes.

Notes:

-
