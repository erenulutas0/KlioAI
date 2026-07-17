# GitHub Release Automation Runbook

Last update: 2026-07-05

This runbook covers the high-risk automation layer for KlioAI releases:

- required branch checks on `main`
- Android signing secrets for GitHub-built AAB artifacts
- clean database migration preflight before release/deploy
- production backend deploy behind GitHub environment approval
- manual workflow dispatch for AAB and backend deploy

The local Codex environment currently has no `GITHUB_TOKEN`, `GH_TOKEN`, or
`gh` CLI, so remote GitHub changes must be applied from a shell that has a
repo-admin token.

## Required GitHub Token Scope

Use a fine-grained token for `erenulutas0/KlioAI` with enough permission for:

- Actions secrets: read/write
- Environments: read/write
- Administration or branch protection: read/write
- Actions workflow dispatch: write
- Metadata: read

Set it only for the current shell session:

```powershell
$env:GITHUB_TOKEN = "<repo-admin-token>"
```

Do not commit or paste this token into docs, `.env`, scripts, screenshots, or
chat logs.

## 1. Apply Branch Protection

Default required checks:

- `db-readiness`
- `flutter-quality`
- `trivy-fs`

Dry-run:

```powershell
pwsh -File scripts/configure-github-branch-protection.ps1
```

Apply:

```powershell
pwsh -File scripts/configure-github-branch-protection.ps1 -Execute
```

Expected behavior:

- PR required before merge
- 1 approval required
- stale approvals dismissed
- conversation resolution required
- force pushes disabled
- branch deletions disabled

## 2. Configure Android Signing Secrets

Dry-run validates local `key.properties` and keystore without printing secret
values:

```powershell
pwsh -File scripts/configure-github-android-signing-secrets.ps1
```

Apply:

```powershell
pwsh -File scripts/configure-github-android-signing-secrets.ps1 -Execute
```

Secrets uploaded:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_KEY_ALIAS`

## 3. Protect Backend Deploy Environment

The backend deploy workflow uses the GitHub environment named
`production-backend`.

Dry-run:

```powershell
pwsh -File scripts/configure-github-environment-protection.ps1
```

Apply with a reviewer:

```powershell
pwsh -File scripts/configure-github-environment-protection.ps1 `
  -ReviewerUsernames erenulutas0 `
  -Execute
```

This creates/updates the environment. In the GitHub UI, verify that
`production-backend` requires approval before deployment.

## 4. Configure VPS Deploy Environment Secrets

Prefer a deploy-only SSH key on the VPS. The public key should be authorized
for the deploy user. The private key becomes a GitHub environment secret.

Dry-run:

```powershell
pwsh -File scripts/configure-github-vps-deploy-secrets.ps1 `
  -PrivateKeyPath C:\path\to\deploy_key
```

Apply:

```powershell
pwsh -File scripts/configure-github-vps-deploy-secrets.ps1 `
  -PrivateKeyPath C:\path\to\deploy_key `
  -Execute
```

Environment secrets uploaded to `production-backend`:

- `VPS_SSH_HOST`
- `VPS_SSH_USER`
- `VPS_SSH_PORT`
- `VPS_SSH_PRIVATE_KEY`

## 5. Run Release Preflight

The release preflight workflow is the broad manual gate before publishing a Play
build or approving a backend deploy.

Workflow:

- `.github/workflows/release-preflight.yml`

Default checks:

- repo secret scan
- backend Maven tests
- migration preflight
- Flutter quality gate

The migration preflight runs:

- `scripts/run-db-readiness.ps1 -FailOnSkip -SkipSmokeFallback`
- `scripts/smoke-clean-db.ps1` against a clean Docker Compose database
- `scripts/check-db-parity.ps1` against that stack

Local command:

```powershell
pwsh -File scripts/run-migration-preflight.ps1
```

GitHub dispatch dry-run:

```powershell
pwsh -File scripts/dispatch-github-release-preflight-workflow.ps1
```

GitHub dispatch:

```powershell
pwsh -File scripts/dispatch-github-release-preflight-workflow.ps1 -Execute
```

GitHub UI:

1. Open Actions.
2. Run `Release Preflight`.
3. Keep `run_migration_preflight=true` unless the release contains no backend,
   database, Docker, or migration-sensitive changes.

Expected result:

- Testcontainers Flyway readiness passes without being skipped.
- Clean Docker Compose backend reaches health `UP`.
- DB parity confirms latest Flyway version, core tables, required indexes, and
  uniqueness constraints.

## 6. Build AAB Artifact In GitHub Actions

Dry-run:

```powershell
pwsh -File scripts/dispatch-github-aab-artifact-workflow.ps1
```

Dispatch:

```powershell
pwsh -File scripts/dispatch-github-aab-artifact-workflow.ps1 -Execute
```

Workflow:

- `.github/workflows/android-aab-artifact.yml`

Expected artifacts:

- `klioai-release-aab`
- `klioai-release-checklist`

## 7. Deploy Backend Through Protected Environment

Dry-run:

```powershell
pwsh -File scripts/dispatch-github-backend-vps-deploy-workflow.ps1
```

Dispatch:

```powershell
pwsh -File scripts/dispatch-github-backend-vps-deploy-workflow.ps1 `
  -Label <short-change-label> `
  -NoCache false `
  -Execute
```

Workflow:

- `.github/workflows/backend-vps-deploy.yml`

Expected behavior:

1. Workflow starts.
2. Job waits for `production-backend` approval.
3. Approved job connects to the VPS with environment secrets.
4. `scripts/deploy-backend-vps.ps1 -Execute` packages, uploads, backs up,
   rebuilds, recreates backend, waits for health, and runs public smoke.

## Failure Policy

- If branch protection application fails, do not weaken required checks without
  recording the reason in `TODO.md`.
- If Android signing secret upload fails, do not build a release AAB in GitHub.
- If backend deploy fails after approval, inspect the workflow logs and VPS
  backend container logs before retrying.
- Keep Play upload manual until at least two GitHub-built AAB artifacts pass
  internal-track device smoke.
