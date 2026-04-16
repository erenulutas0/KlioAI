# Google Play Live Verification Dry-Run

Last update: 2026-02-18

## Purpose

Validate real Google Play purchase-token verification path before production rollout.

Endpoint:
- `POST /api/subscription/verify/google`

Script:
- `scripts/smoke-google-play-live-verify.ps1`

## Preconditions

1. Backend is running with live verification mode:
- `APP_SUBSCRIPTION_MOCK_VERIFICATION_ENABLED=false`
- `APP_SUBSCRIPTION_GOOGLE_PLAY_ENABLED=true`

2. Google Play envs are set:
- `APP_SUBSCRIPTION_GOOGLE_PLAY_PACKAGE_NAME`
- `APP_SUBSCRIPTION_GOOGLE_PLAY_SERVICE_ACCOUNT_HOST_PATH` (existing JSON path)
- product-plan map envs (`APP_SUBSCRIPTION_GOOGLE_PLAY_PRODUCT_PLAN_*`)

3. Service account has Android Publisher access for the same package.
4. You have a real test purchase token from Play Billing test flow.
5. You have a valid app user id (`X-User-Id`) and optional JWT.

## Non-Token Checks (run first)

```powershell
pwsh -File scripts/verify-rollout.ps1 -Mode prod-preflight -ProjectName flutter-project-main
```

Expected:
- `runtime-prod-flags-check` PASS
- `validate-prod-alert-routing` PASS

## Live Token Dry-Run Command

```powershell
pwsh -NoProfile -File scripts/smoke-google-play-live-verify.ps1 `
  -BackendBaseUrl "http://localhost:8082" `
  -UserId 123 `
  -PurchaseToken "<REAL_PLAY_PURCHASE_TOKEN>" `
  -ProductId "pro_monthly_subscription" `
  -PackageName "com.VocabMaster" `
  -AccessToken "<JWT_OPTIONAL>"
```

## Expected Success Response (shape)

- HTTP `200`
- payload includes:
  - `message` (`Google IAP verified` or `Google IAP already verified`)
  - `planName`
  - `subscriptionEndDate`
  - `subscriptionState`
  - `productKeys`
  - `latestOrderId`

## Failure Mapping (important)

- `400`: invalid purchase / product-plan mapping issue
- `500`: server misconfiguration (missing/invalid service account, package mismatch)
- `503`: provider unavailable (Google API unavailable/timeouts)

## Post-Run Validation

1. Confirm user entitlement:
- `GET /api/chatbot/quota/status`
- check `planCode`, `aiAccessEnabled`, daily quota limit

2. Confirm DB persistence:
- `users.ai_plan_code` updated
- `payment_transactions.provider=GOOGLE_IAP` and success row exists

3. Idempotency check:
- run same token again, expect `Google IAP already verified` and no duplicate success transaction.
