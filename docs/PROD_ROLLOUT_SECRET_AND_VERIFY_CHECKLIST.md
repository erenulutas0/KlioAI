# Prod Rollout Secret and Verify Checklist

Date: 2026-02-13

## 1) Environment Secret Checklist

Minimum required secrets for prod/stage compose rendering and runtime:

- `POSTGRES_PASSWORD`
- `SPRING_DATA_REDIS_PASSWORD`
- `APP_CORS_ALLOWED_ORIGINS`
- `IYZICO_API_KEY`
- `IYZICO_API_SECRET`
- `IYZICO_API_BASE_URL`
- `GROQ_API_KEY`
- `APP_SECURITY_AUTH_GOOGLE_CLIENT_IDS`
- `ALERTMANAGER_DEFAULT_WEBHOOK_URL`
- `ALERTMANAGER_CRITICAL_WEBHOOK_URL`
- `ALERTMANAGER_WARNING_WEBHOOK_URL`

Rules:

- Do not leave any of the values empty.
- `ALERTMANAGER_*_WEBHOOK_URL` values must point to real environment-specific destinations.
- Production and stage must use different paging endpoints.

## 1.1) Non-Secret Runtime Vars (TTS)

- `PIPER_MODEL_HOST_PATH`:
  - Host path that contains Piper `.onnx` model files.
  - Default in compose is `C:/piper`; set explicitly on non-Windows hosts.
- `PIPER_TTS_DEFAULT_MODEL`:
  - Optional override for default voice model file name.
  - Default: `en_US-amy-medium.onnx`.
- `APP_SECURITY_AUTH_RATE_LIMIT_REDIS_FALLBACK_MODE`:
  - Optional auth policy override: `memory` (default) or `deny`.
- `APP_SECURITY_AUTH_RATE_LIMIT_REDIS_FAILURE_BLOCK_SECONDS`:
  - Optional retry window for fail-closed mode.
  - Default: `60`.
- `APP_SECURITY_AUTH_GOOGLE_ID_TOKEN_REQUIRED`:
  - Prod: `true` olmalı (server-side Google ID token validation zorunlu).
  - Default non-prod: `false`.
- `APP_SECURITY_AUTH_GOOGLE_CLIENT_IDS`:
  - Prod: zorunlu. Google OAuth client ID listesi (comma-separated).
  - ID token `aud` değeri bu listede olmalı.

## 1.2) Edge / DDoS Preconditions (Prod)

Before go-live, complete these edge controls:

- Cloudflare (or equivalent CDN/WAF/DDoS shield) must be in front of origin.
- Origin backend must not be directly reachable from public internet.
- Firewall/Security Group should allow only reverse-proxy/LB ingress to backend.
- WAF/bot rules should be active for auth endpoints:
  - `/api/auth/login`
  - `/api/auth/register`
  - `/api/auth/google-login`
  - `/api/auth/refresh`

Detailed checklist: `docs/PROD_DDOS_EDGE_CHECKLIST.md`.

## 2) One-Command Verification Blocks

Run from repository root (`C:\flutter-project-main`).

### A) Prod Preflight (Secret Contract + Compose Render)

```powershell
pwsh -File .\scripts\verify-rollout.ps1 -Mode prod-preflight
```

Notes:

- Requires the 11 env vars above to be already exported/injected.
- Fails fast if any required secret is missing.

### B) Non-Prod Rollout Smoke (Reconcile + Load)

```powershell
pwsh -File .\scripts\verify-rollout.ps1 -Mode nonprod-smoke -ProjectName flutter-project-main -BackendBaseUrl http://localhost:8082
```

If you want strict staging browser-surface checks in the same run:

```powershell
pwsh -File .\scripts\verify-rollout.ps1 -Mode nonprod-smoke -ProjectName flutter-project-main -BackendBaseUrl http://localhost:8082 -SecuritySmokeAllowedOrigin https://staging.example.com
```

What it runs:

- `scripts/reconcile-all-nonprod.ps1`
- `scripts/run-http-load-smoke.ps1` on `/actuator/health`
- `scripts/run-http-load-smoke.ps1` on `/api/progress/stats` (`X-User-Id: 1`)
- Optional: `scripts/smoke-security-cors-headers.ps1` (when `-SecuritySmokeAllowedOrigin` is provided)

Optional TTS runtime check (recommended where TTS is enabled):

```powershell
Invoke-RestMethod -Uri http://localhost:8082/api/tts/status
```

Expected:
- `available=true` and at least one `voices[]` entry.

### C) Local Release Gate

```powershell
pwsh -File .\scripts\verify-rollout.ps1 -Mode local-gate -ProjectName flutter-project-main
```

What it runs:

- `mvn -q test`
- `scripts/check-core-coverage.ps1 -Threshold 90`
- `scripts/check-db-parity.ps1`

### D) Full Batch (All Three)

```powershell
pwsh -File .\scripts\verify-rollout.ps1 -Mode full -ProjectName flutter-project-main -BackendBaseUrl http://localhost:8082
```

### E) Optional Local CVE Gate (Trivy HIGH/CRITICAL)

```powershell
docker run --rm -v C:/flutter-project-main:/workspace aquasec/trivy:0.58.1 fs --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --no-progress --exit-code 1 /workspace
```

## 3) Rollout Done Criteria

- Prod preflight passes with real secret values.
- Non-prod smoke passes with `100%` success on both endpoints.
- Local release gate passes (`test`, `coverage`, `db parity`).
- Edge/DDoS preconditions are completed and verified.
