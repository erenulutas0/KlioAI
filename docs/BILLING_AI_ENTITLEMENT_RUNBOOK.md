# Billing And AI Entitlement Runbook

Last audit: 2026-05-24 Europe/Istanbul

Use this before changing Google Play Billing, subscription state, paywall behavior, or AI token quota.

Related auth/abuse rule:

- Do not block Google login purely because an IP is shared.
- Trial-abuse protection may mark new users `trialEligible=false` after device/IP thresholds.
- Current default threshold is 2 trial grants per device and 4 trial grants per IP in 24 hours.
- Paid users should not lose entitlement because of shared IP heuristics.

## Current Incident

Reported behavior:

- A test/Play subscription became inactive after about 5 minutes.
- Re-subscribing/restoring can show: `Session verification failed. Please try again. If the issue continues, reopen the app and try once more.`
- Annual plan can show that the store product does not exist.
- The affected account cannot use even the expected daily FREE token allowance.

Treat these as separate signals until verified:

- 5-minute expiry may be Play test-subscription timing leaking into local entitlement or an old backend deploy.
- Session verification failure means backend returned 401/403 to purchase verify/status, often from stale JWT, `X-User-Id` mismatch, or auth enforcement.
- Annual product not found is usually Play Console product/base-plan/track/tester mismatch for `pro_annual_subscription`.
- Free token failure conflicts with current prod config and points to stale runtime env, stale deploy, or quota endpoint/auth state.

## Current Plan Mapping

Flutter product IDs:

- `PRO_MONTHLY` -> `pro_monthly_subscription`
- `PRO_ANNUAL` -> `pro_annual_subscription`
- `PREMIUM` -> `premium_monthly`
- `PREMIUM_PLUS` -> `premium_plus_monthly`

Visible paywall plans:

- `PRO_MONTHLY`
- `PRO_ANNUAL`

Backend product map defaults:

- `pro_monthly_subscription` -> `PREMIUM`
- `pro_annual_subscription` -> `PREMIUM_PLUS`
- `premium_monthly` -> `PREMIUM`
- `premium_plus_monthly` -> `PREMIUM_PLUS`
- `monthly` base plan -> `PREMIUM`

Plan metadata migrations currently set:

- `PRO_MONTHLY`/`PREMIUM`: 30 days, 149.99 TRY.
- `PRO_ANNUAL`: 365 days, 999.99 TRY.
- `PREMIUM_PLUS`: 30 days, 999.99 TRY.
- `FREE`: base app access with 1500 daily AI token quota (`V023__align_free_plan_ai_token_metadata.sql`).

## 2026-05-24 Production Checkpoint

- Backend was rebuilt and redeployed on the VPS from the current workspace.
- Flyway latest version on production is `023`.
- Public API health returned `200 UP`.
- Public CORS preflight for `https://klioai.app` returned `200` with the expected allow-origin.
- Public `/api/subscription/plans` returns FREE metadata as `Base app access with 1500 daily AI token quota.`
- The affected masked account is currently `FREE`, has `subscription_end_date=NULL`, and has no completed Google IAP transactions in the local DB.
- Latest local Google IAP rows for that account are refund/reset state, so backend cannot currently grant paid entitlement without a fresh restore/verify or an explicit manual override.
- Remote backend source backup before the `V023` deploy:
  - `/opt/vocabmaster/backups/deploy/backend-src-pre-codex-v023-20260524T001043Z.tar.gz`
- Later same day incident update:
  - Fresh Play test purchase produced a Google receipt, but backend logs showed `Auth required for subscription verify`, so the purchase token never reached controller verification.
  - Backend fix deployed: live `/api/subscription/verify/google` is allowed through security filters and still requires Android Publisher purchase-token verification before entitlement is written.
  - Mock verification mode still requires authenticated self/admin access.
  - Remote backend source backup before this deploy:
    - `/opt/vocabmaster/backups/deploy/backend-src-pre-codex-google-verify-permit-20260524T144409Z.tar.gz`

## AI Quota Policy

Current code/config source:

- `AiEntitlementService`
- `AiPlanTier`
- `AiTokenQuotaService`
- `application-prod.properties`

Current production defaults in repo:

- Trial duration: 7 days.
- Trial quota: 5000 tokens/day.
- Free quota: 1500 tokens/day.
- Premium quota: 30000 tokens/day.
- Premium Plus quota: 60000 tokens/day.

Important: `AiEntitlementService` enables AI access when daily token limit is greater than zero. Therefore a FREE user should have `aiAccessEnabled=true` if prod runtime uses the repo default `free-daily-token-quota-per-user=1500`.

## Backend Verification Flow

Endpoint:

- `POST /api/subscription/verify/google`

Expected request fields:

- `X-User-Id`
- `Authorization: Bearer ...`
- body: `purchaseToken`, `productId`, optional `packageName`

Flow:

1. `SubscriptionController` loads the user.
2. If mock verification is disabled, it calls `GooglePlaySubscriptionVerificationService.verifySubscription`.
3. Verifier calls Google Android Publisher `purchases/subscriptionsv2/tokens/{token}`.
4. Verifier extracts `subscriptionState`, max line-item `expiryTime`, `latestOrderId`, product IDs, and base-plan IDs.
5. Backend maps product/base-plan to an internal `SubscriptionPlan`.
6. Backend updates `users.subscription_end_date` and `users.ai_plan_code`.
7. Backend writes or updates `payment_transactions` with provider `GOOGLE_IAP`.

## Reconciliation Flow

Service:

- `GooglePlaySubscriptionReconciliationService`
- `GooglePlayRtdnService`
- `GooglePlayRtdnController`

Behavior:

- Scheduled reconciliation fetches the latest Google IAP transaction per user.
- RTDN push endpoint `POST /api/subscription/google-play/rtdn` accepts Google Pub/Sub push envelopes when `APP_SUBSCRIPTION_GOOGLE_PLAY_RTDN_ENABLED=true`.
- If `APP_SUBSCRIPTION_GOOGLE_PLAY_RTDN_SHARED_SECRET` is set, the endpoint requires either `X-KlioAI-RTDN-Secret` or `?secret=` to match before processing.
- RTDN payloads are treated as state-change signals only; the backend still fetches the authoritative subscription snapshot from Android Publisher API using the stored purchase token.
- Active/grace states preserve or extend local access.
- Revoked/expired/ineligible states downgrade the user to FREE.
- Current code should preserve future local entitlement when Google test expiry is already past, unless the user local end date is also expired.

If production still cuts access after about 5 minutes, check whether the latest reconciliation and controller duration hardening are deployed.

## Fast Diagnostic Checklist

For the affected user/account:

1. Backend health:
   - `GET https://api.klioai.app/actuator/health`
2. App session:
   - Force logout/re-login or clear app data if JWT secret rotated recently.
3. Quota endpoint with a fresh JWT:
   - `GET /api/chatbot/quota/status`
   - Expect FREE users to show `tokenLimit=1500` and `aiAccessEnabled=true` under current prod defaults.
4. User DB row:
   - Check `users.ai_plan_code`, `subscription_end_date`, `trial_eligible`, `created_at`.
5. Payment DB row:
   - Check latest `payment_transactions` for provider `GOOGLE_IAP`, status, plan, and transaction token prefix.
6. Google Play product catalog:
   - Ensure `pro_monthly_subscription` and `pro_annual_subscription` are active.
   - Ensure base plans are active.
   - Ensure the tester is in the correct Play track.
   - Ensure the installed app came from Play, not sideload/debug.
7. Backend logs:
   - Search for `Google verify request`, `Google verify failed`, `User identity mismatch`, and reconciliation logs.

For AI provider failures affecting multiple practice modes:

```powershell
pwsh -File scripts/smoke-groq-provider.ps1
pwsh -File scripts/smoke-groq-provider.ps1 -JsonMode
```

Expected: both configured models return PASS. `expired_api_key` means the Groq key must be regenerated, updated in the backend runtime secret/env, and the backend container restarted.

## Code Change Rules

- Do not hide 401/403 billing errors behind generic purchase errors; keep enough detail for diagnosis.
- Do not trust Flutter plan names over Google product/base-plan verification.
- Do not make Play test subscriptions define local production entitlement length unless explicitly desired.
- Do not complete a purchase before backend verification has had a chance to persist entitlement.
- Add controller/service tests for every billing entitlement rule change.

## Focused Test Set

```powershell
Set-Location backend
mvn -q "-Dmaven.repo.local=C:\flutter-project-main\backend\.m2-repo" "-Dtest=SubscriptionControllerGoogleLiveModeTest,SubscriptionControllerTest,AiEntitlementServiceTest,GooglePlaySubscriptionReconciliationServiceTest" test
```

```powershell
Set-Location flutter_vocabmaster
flutter analyze lib/services/subscription_service.dart lib/screens/subscription_page.dart
```
