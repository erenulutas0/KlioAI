# Managed Postgres Migration Plan

KlioAI can stay on the current single VPS while traffic is low and restore tests pass. Managed Postgres becomes the right move when database reliability or operational load starts competing with product work.

## Move When Any Trigger Happens

- Daily active users exceed 500 for 7 consecutive days.
- Paying users exceed 100.
- PostgreSQL CPU or memory pressure contributes to API latency.
- Hikari pending connections are non-zero for more than 2 minutes during normal traffic.
- VPS disk usage repeatedly exceeds 80% because of DB growth, WAL, backups, or Docker churn.
- A restore test takes longer than the recovery target.
- Manual DB maintenance becomes a recurring weekly task.

## Suggested First Target

Use a managed PostgreSQL provider with:

- PostgreSQL 15 or newer
- Automated daily backups
- Point-in-time recovery
- Private networking or strict IP allowlist
- At least 2 vCPU / 4 GB RAM equivalent for the first paid tier
- Connection limit high enough for current Hikari pool plus admin/maintenance connections

## Pre-Migration Checklist

- Run `scripts/smoke-prod-readiness.ps1`.
- Create and verify a fresh backup restore into an isolated database.
- Confirm Flyway migrations are clean and current.
- Record current DB size:
  - database size
  - largest tables
  - largest indexes
- Freeze risky backend deploys during the migration window.
- Lower backend connection pool if the managed tier has a small connection limit.

## Migration Steps

1. Create managed PostgreSQL instance.
2. Create database and user with least required privileges.
3. Restrict network access to the VPS IP or private network.
4. Restore the latest verified dump into managed Postgres.
5. Run schema parity checks against the restored DB.
6. Put the app in a short maintenance window if data writes are active.
7. Take a final dump from VPS Postgres.
8. Restore final dump into managed Postgres.
9. Update backend DB env vars on the VPS.
10. Restart backend only.
11. Run production smoke.
12. Monitor Hikari, API latency, error rate, and subscription verification for at least 30 minutes.

## Rollback

Keep the old VPS Postgres container and volume intact until the managed DB has run cleanly for 48 hours.

Rollback path:

1. Stop backend.
2. Restore old DB env vars.
3. Start backend.
4. Run production smoke.
5. Compare newest writes and decide whether manual reconciliation is needed.

## Success Criteria

- Production smoke passes.
- No increase in 5xx errors.
- Hikari pending connections stay at 0 under normal traffic.
- Daily backup is visible in the managed provider.
- A managed-provider restore test is scheduled within the first week.
