# Clean DB Smoke Test

## Recommended Entry Point

Use the readiness wrapper first. It tries the Testcontainers integration test and
automatically falls back to this smoke flow when Testcontainers is skipped:

```powershell
pwsh -File .\scripts\run-db-readiness.ps1
```

## CI

GitHub Actions workflow:

`/.github/workflows/backend-db-readiness.yml`

The workflow runs `scripts/run-db-readiness.ps1` on `push`/`pull_request` for backend and compose changes.
CI mode uses `-FailOnSkip`, so a skipped Testcontainers run fails the job.
After readiness passes, CI runs full backend tests and enforces a core coverage gate:

`pwsh -File .\scripts\check-core-coverage.ps1 -Threshold 85.0`

This smoke test boots the backend stack with a clean PostgreSQL volume and verifies:

- App startup (`GET /api`)
- Seeded plans (`GET /api/subscription/plans`)
- Auth flow (`POST /api/auth/register`, `POST /api/auth/login`)
- Critical write/read (`POST /api/words`, `GET /api/words`)

## Run

```powershell
pwsh -File .\scripts\smoke-clean-db.ps1
```

## Optional

- Keep containers after test:

```powershell
pwsh -File .\scripts\smoke-clean-db.ps1 -KeepContainers
```

- Custom project/port:

```powershell
pwsh -File .\scripts\smoke-clean-db.ps1 -ProjectName my-smoke -BackendPort 18082
```

- Run core coverage gate locally (after `mvn clean test`):

```powershell
pwsh -File .\scripts\check-core-coverage.ps1 -Threshold 85.0
```

The smoke run uses `docker-compose.yml` + `docker-compose.smoke.yml`.
