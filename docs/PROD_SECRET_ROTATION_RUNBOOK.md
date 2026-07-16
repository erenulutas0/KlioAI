# Production Secret Rotation Runbook

Last update: 2026-07-05

Use this after any suspected runtime secret exposure, before scaling traffic, or
before granting broader repo/session access.

Do not paste secret values into chat, docs, tickets, screenshots, or commits.

## Scope

Rotate the production runtime values that can grant backend, cache, database, or
provider access:

- `GROQ_API_KEY`
- `APP_SECURITY_JWT_SECRET`
- `SPRING_DATA_REDIS_PASSWORD`
- `REDIS_PASSWORD`
- `SPRING_DATA_REDIS_SECURITY_PASSWORD`
- `REDIS_SECURITY_PASSWORD`
- `POSTGRES_PASSWORD` / `SPRING_DATASOURCE_PASSWORD` if DB credentials were exposed
- `APP_SUBSCRIPTION_GOOGLE_PLAY_RTDN_SHARED_SECRET` if RTDN is enabled

Google OAuth client IDs are identifiers, not secrets. Service-account JSON files
are secrets and should be rotated in Google Cloud/Firebase if their private keys
were exposed.

## Impact

- JWT secret rotation logs users out after current tokens fail validation.
- Redis password rotation requires recreating Redis and backend services.
- PostgreSQL password rotation requires changing the database role password and
  updating backend runtime env consistently.
- Groq key rotation requires creating a new provider key, updating backend env,
  and revoking the old provider key.
- Service-account JSON rotation requires replacing the file and recreating the
  backend service.

Plan a quiet window if there are active users.

## Generate Local Runtime Secrets

Generate values locally without printing them to terminal:

```powershell
$out = Join-Path $env:TEMP "klioai-prod-runtime-secrets.env"
pwsh -File scripts/new-prod-runtime-secret-set.ps1 -OutputPath $out -IncludeRtdnSecret
```

If rotating PostgreSQL too:

```powershell
$out = Join-Path $env:TEMP "klioai-prod-runtime-secrets-with-postgres.env"
pwsh -File scripts/new-prod-runtime-secret-set.ps1 -OutputPath $out -IncludePostgresPassword -IncludeRtdnSecret
```

Delete the generated file after copying values into the VPS secret files.

## Pre-Rotation Snapshot

On the VPS:

```bash
sudo install -d -m 700 /opt/vocabmaster/backups/deploy
sudo cp /opt/vocabmaster/secrets/backend.env /opt/vocabmaster/backups/deploy/backend-env-pre-secret-rotation-$(date -u +%Y%m%dT%H%M%SZ).env
sudo cp /opt/vocabmaster/secrets/redis.env /opt/vocabmaster/backups/deploy/redis-env-pre-secret-rotation-$(date -u +%Y%m%dT%H%M%SZ).env
sudo cp /opt/vocabmaster/secrets/redis-security.env /opt/vocabmaster/backups/deploy/redis-security-env-pre-secret-rotation-$(date -u +%Y%m%dT%H%M%SZ).env
sudo chmod 600 /opt/vocabmaster/backups/deploy/*secret-rotation*.env
```

## Provider Rotation

### Groq

1. Create a new Groq API key in the Groq console.
2. Update `GROQ_API_KEY` in `/opt/vocabmaster/secrets/backend.env`.
3. Recreate backend after all env edits are complete.
4. Revoke the old Groq API key after smoke tests pass.

### Google / Firebase Service Accounts

Only needed if private service-account JSON was exposed.

1. Create a new service-account key in Google Cloud/Firebase.
2. Replace the file under `/opt/vocabmaster/secrets/`.
3. Keep owner/permission tight, for example `root:root` and `600`.
4. Recreate backend and run subscription/push smoke checks.
5. Delete the old service-account key in Google Cloud/Firebase.

## Redis Rotation

Update these pairs consistently:

- `/opt/vocabmaster/secrets/redis.env`
  - `REDIS_PASSWORD`
- `/opt/vocabmaster/secrets/redis-security.env`
  - `REDIS_SECURITY_PASSWORD`
- `/opt/vocabmaster/secrets/backend.env`
  - `SPRING_DATA_REDIS_PASSWORD`
  - `SPRING_DATA_REDIS_SECURITY_PASSWORD`

Then recreate Redis and backend:

```bash
cd /opt/vocabmaster/deploy
docker compose -f docker-compose.app.yml up -d --force-recreate redis redis-security
docker compose -f docker-compose.app.yml up -d --no-deps --force-recreate backend
```

Verify:

```bash
docker inspect -f '{{.State.Health.Status}}' vocabmaster-redis
docker inspect -f '{{.State.Health.Status}}' vocabmaster-redis-security
docker inspect -f '{{.State.Health.Status}}' vocabmaster-backend
docker exec vocabmaster-backend sh -lc 'curl -fsS http://localhost:8082/actuator/health'
```

## JWT Rotation

Update in `/opt/vocabmaster/secrets/backend.env`:

```text
APP_SECURITY_JWT_SECRET=<new value>
```

Then recreate backend:

```bash
cd /opt/vocabmaster/deploy
docker compose -f docker-compose.app.yml up -d --no-deps --force-recreate backend
```

Expected result: existing mobile sessions may need re-login.

## PostgreSQL Rotation

Only do this if DB credentials were exposed or as part of a planned maintenance
window.

1. Generate a new DB password.
2. On the VPS, alter the database role used by the backend:

```bash
docker exec -it vocabmaster-postgres psql -U postgres -d EnglishApp
```

Inside `psql`:

```sql
ALTER USER englishapp WITH PASSWORD '<new password>';
```

3. Update backend runtime env:

```text
SPRING_DATASOURCE_PASSWORD=<new password>
POSTGRES_PASSWORD=<new password, only if compose still uses this var for backend binding>
```

4. Recreate backend only:

```bash
cd /opt/vocabmaster/deploy
docker compose -f docker-compose.app.yml up -d --no-deps --force-recreate backend
```

5. Verify backend health and a simple authenticated flow.

## Post-Rotation Verification

From local repo:

```powershell
pwsh -File scripts/check-prod-secret-parity-vps.ps1 -Execute
pwsh -File scripts/check-backend-vps-deploy-target.ps1 -Execute
pwsh -File scripts/smoke-prod-readiness.ps1
pwsh -File scripts/scan-repo-secrets.ps1
```

If Groq was rotated and you have the new key locally:

```powershell
pwsh -File scripts/smoke-groq-provider.ps1 -ApiKey <new-key>
pwsh -File scripts/smoke-groq-provider.ps1 -ApiKey <new-key> -JsonMode
```

Do not store the Groq key in repo files.

## Latest Rotation Record

2026-07-05:

- Rotated with `scripts/rotate-prod-runtime-secrets-vps.ps1 -Execute`:
  - `APP_SECURITY_JWT_SECRET`
  - `SPRING_DATA_REDIS_PASSWORD` / `REDIS_PASSWORD`
  - `SPRING_DATA_REDIS_SECURITY_PASSWORD` / `REDIS_SECURITY_PASSWORD`
- Redis, Redis security, and backend containers were recreated and health
  checks passed.
- Follow-up verification passed:
  - `scripts/check-prod-secret-parity-vps.ps1 -Execute`
  - `scripts/check-backend-vps-deploy-target.ps1 -Execute`
  - `scripts/smoke-prod-readiness.ps1`
  - `scripts/scan-repo-secrets.ps1`
- Still requires manual/provider action if exposure is suspected:
  - `GROQ_API_KEY`
  - `SPRING_DATASOURCE_PASSWORD` / PostgreSQL role password
  - Google/Firebase service-account JSON private keys

## Cleanup

- Delete local generated secret files from `%TEMP%`.
- Delete any copied plaintext secret snippets from shell history where possible.
- Revoke old provider keys after smoke checks pass.
- Record only the rotation date and affected variable names in `TODO.md`; never
  record secret values.
