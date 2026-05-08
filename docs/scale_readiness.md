# Scale Readiness

This checklist covers the operational checks that should run before and after production changes.

## Production Smoke

Run after each backend deploy:

```powershell
pwsh -File .\scripts\smoke-prod-readiness.ps1
```

The smoke verifies:

- `GET /actuator/health`
- unauthenticated API auth gates
- `GET /api/subscription/plans`
- unauthenticated daily words auth gate
- CORS preflight for the landing/app origin
- HSTS header on the public API

To validate authenticated daily words as well, pass a tester token and user id:

```powershell
pwsh -File .\scripts\smoke-prod-readiness.ps1 -AccessToken "<jwt>" -UserId "<id>"
```

## Clean DB Readiness

Run before risky backend releases:

```powershell
pwsh -File .\scripts\run-db-readiness.ps1
```

This validates migrations, seeded plans, auth, core write/read flow, and schema parity in a disposable Docker stack.

## Backup Restore Verification

Start or keep a compose stack running first:

```powershell
pwsh -File .\scripts\smoke-clean-db.ps1 -KeepContainers
```

Then verify a real `pg_dump` can restore into an isolated PostgreSQL container:

```powershell
pwsh -File .\scripts\verify-postgres-backup-restore.ps1
```

This does not restore into the source database. It creates a temporary dump, restores it into a separate container, checks core schema presence, and removes the temporary artifacts.

Last production restore verification:

- Date: 2026-05-08
- Result: restored into isolated PostgreSQL container
- Tables restored: 28
- Flyway latest version: 22

## Production VPS Notes

- Keep manual backups under `/opt/vocabmaster/backups/manual`.
- Never test restore directly against the production database.
- A backup is not proven until it has been restored into an isolated database at least once.
- If disk usage passes 80%, review Docker image/cache usage and old backup retention before deploying.
