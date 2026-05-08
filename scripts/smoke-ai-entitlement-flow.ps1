param(
    [string]$BackendBaseUrl = "http://localhost:8082",
    [string]$ProjectName = "flutter-project-main",
    [string]$PostgresService = "postgres",
    [string]$PostgresDatabase = "EnglishApp",
    [string]$PostgresUser = "postgres",
    [int]$ExpectedTrialDays = 7,
    [long]$ExpectedTrialDailyTokenLimit = 5000,
    [long]$ExpectedPremiumDailyTokenLimit = 30000,
    [long]$ExpectedPremiumPlusDailyTokenLimit = 60000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$composeBase = Join-Path $repoRoot "docker-compose.yml"

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

function Invoke-Compose {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    & docker compose -p $ProjectName -f $composeBase @Args
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose failed: $($Args -join ' ')"
    }
}

function Invoke-PostgresNonQuery {
    param([string]$Sql)
    $null = Invoke-Compose @(
        "exec", "-T", $PostgresService,
        "psql", "-U", $PostgresUser, "-d", $PostgresDatabase,
        "-v", "ON_ERROR_STOP=1",
        "-c", $Sql
    )
}

function Invoke-Api {
    param(
        [ValidateSet("GET", "POST", "PUT", "DELETE")]
        [string]$Method,
        [string]$Uri,
        [hashtable]$Headers = @{},
        [object]$Body = $null
    )

    $params = @{
        Method             = $Method
        Uri                = $Uri
        Headers            = $Headers
        TimeoutSec         = 30
        SkipHttpErrorCheck = $true
    }
    if ($null -ne $Body) {
        $params.ContentType = "application/json"
        $params.Body = ($Body | ConvertTo-Json -Depth 20)
    }

    $resp = Invoke-WebRequest @params
    $json = $null
    if (-not [string]::IsNullOrWhiteSpace($resp.Content)) {
        try {
            $json = $resp.Content | ConvertFrom-Json -AsHashtable
        } catch {
            $json = $null
        }
    }

    return [PSCustomObject]@{
        StatusCode = [int]$resp.StatusCode
        Json       = $json
        Raw        = $resp.Content
    }
}

function Assert-QuotaState {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Response,
        [string]$ExpectedPlanCode,
        [bool]$ExpectedAiAccessEnabled,
        [bool]$ExpectedTrialActive,
        [long]$ExpectedTokenLimit
    )

    Assert-True ($Response.StatusCode -eq 200) "Expected quota status HTTP 200, got $($Response.StatusCode)."
    Assert-True ($null -ne $Response.Json) "Quota status response is not valid JSON."

    $payload = $Response.Json
    $success = if ($payload.ContainsKey("success")) { [bool]$payload["success"] } else { $false }
    $planCode = if ($payload.ContainsKey("planCode")) { [string]$payload["planCode"] } else { "" }
    $aiAccessEnabled = if ($payload.ContainsKey("aiAccessEnabled")) { [bool]$payload["aiAccessEnabled"] } else { $false }
    $trialActive = if ($payload.ContainsKey("trialActive")) { [bool]$payload["trialActive"] } else { $false }
    $tokenLimit = if ($payload.ContainsKey("tokenLimit")) { [long]$payload["tokenLimit"] } else { -1L }

    Assert-True $success "quota/status success=false"
    Assert-True ($planCode -eq $ExpectedPlanCode) "Unexpected planCode: $planCode"
    Assert-True ($aiAccessEnabled -eq $ExpectedAiAccessEnabled) "Unexpected aiAccessEnabled for plan $ExpectedPlanCode"
    Assert-True ($trialActive -eq $ExpectedTrialActive) "Unexpected trialActive for plan $ExpectedPlanCode"
    Assert-True ($tokenLimit -eq $ExpectedTokenLimit) "Unexpected tokenLimit for plan ${ExpectedPlanCode}: $tokenLimit"
}

Write-Host "[ai-entitlement-smoke] Starting trial/paywall flow verification..."

$email = "ai_flow_$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())@local.test"
$password = "SmokePass123!"

$registerResponse = Invoke-Api -Method POST -Uri "$BackendBaseUrl/api/auth/register" -Body @{
    email = $email
    password = $password
    displayName = "AI Smoke User"
}

Assert-True ($registerResponse.StatusCode -eq 200) "Registration failed with status $($registerResponse.StatusCode)."
Assert-True ($null -ne $registerResponse.Json) "Registration response is not valid JSON."
Assert-True ([bool]$registerResponse.Json.success) "Registration success=false."

$userId = [long]$registerResponse.Json.userId
$accessToken = [string]$registerResponse.Json.accessToken
Assert-True ($userId -gt 0) "Registration did not return a valid userId."
Assert-True (-not [string]::IsNullOrWhiteSpace($accessToken)) "Registration did not return an accessToken."

$headers = @{
    "Authorization" = "Bearer $accessToken"
    "X-User-Id" = "$userId"
}

$trialQuota = Invoke-Api -Method GET -Uri "$BackendBaseUrl/api/chatbot/quota/status" -Headers $headers
Assert-QuotaState -Response $trialQuota `
    -ExpectedPlanCode "FREE_TRIAL_7D" `
    -ExpectedAiAccessEnabled $true `
    -ExpectedTrialActive $true `
    -ExpectedTokenLimit $ExpectedTrialDailyTokenLimit

$trialDaysRemaining = if ($trialQuota.Json.ContainsKey("trialDaysRemaining")) { [int]$trialQuota.Json["trialDaysRemaining"] } else { -1 }
Assert-True ($trialDaysRemaining -ge 1) "trialDaysRemaining should be >= 1, got $trialDaysRemaining"
Assert-True ($trialDaysRemaining -le $ExpectedTrialDays) "trialDaysRemaining should be <= $ExpectedTrialDays, got $trialDaysRemaining"

Invoke-PostgresNonQuery -Sql "UPDATE users SET created_at = NOW() - INTERVAL '8 days', subscription_end_date = NOW() - INTERVAL '1 day', ai_plan_code = 'FREE' WHERE id = $userId;"

$freeQuota = Invoke-Api -Method GET -Uri "$BackendBaseUrl/api/chatbot/quota/status" -Headers $headers
Assert-QuotaState -Response $freeQuota `
    -ExpectedPlanCode "FREE" `
    -ExpectedAiAccessEnabled $false `
    -ExpectedTrialActive $false `
    -ExpectedTokenLimit 0
$freeTrialDaysRemaining = if ($freeQuota.Json.ContainsKey("trialDaysRemaining")) { [int]$freeQuota.Json["trialDaysRemaining"] } else { -1 }
Assert-True ($freeTrialDaysRemaining -eq 0) "Expected trialDaysRemaining=0 after forced expiry."

$paywallResponse = Invoke-Api -Method POST -Uri "$BackendBaseUrl/api/chatbot/dictionary/lookup" -Headers $headers -Body @{
    word = "apple"
}
Assert-True ($paywallResponse.StatusCode -eq 403) "Expected paywall HTTP 403, got $($paywallResponse.StatusCode)."
Assert-True ($null -ne $paywallResponse.Json) "Paywall response is not valid JSON."
$paywallReason = if ($paywallResponse.Json.ContainsKey("reason")) { [string]$paywallResponse.Json["reason"] } else { "" }
$upgradeRequired = if ($paywallResponse.Json.ContainsKey("upgradeRequired")) { [bool]$paywallResponse.Json["upgradeRequired"] } else { $false }
Assert-True ($paywallReason -eq "ai-access-disabled") "Unexpected paywall reason: '$paywallReason' raw=$($paywallResponse.Raw)"
Assert-True $upgradeRequired "Expected upgradeRequired=true on paywall response. raw=$($paywallResponse.Raw)"

Invoke-PostgresNonQuery -Sql "UPDATE users SET subscription_end_date = NOW() + INTERVAL '30 days', ai_plan_code = 'PREMIUM' WHERE id = $userId;"

$premiumQuota = Invoke-Api -Method GET -Uri "$BackendBaseUrl/api/chatbot/quota/status" -Headers $headers
Assert-QuotaState -Response $premiumQuota `
    -ExpectedPlanCode "PREMIUM" `
    -ExpectedAiAccessEnabled $true `
    -ExpectedTrialActive $false `
    -ExpectedTokenLimit $ExpectedPremiumDailyTokenLimit

Invoke-PostgresNonQuery -Sql "UPDATE users SET subscription_end_date = NOW() + INTERVAL '30 days', ai_plan_code = 'PREMIUM_PLUS' WHERE id = $userId;"

$premiumPlusQuota = Invoke-Api -Method GET -Uri "$BackendBaseUrl/api/chatbot/quota/status" -Headers $headers
Assert-QuotaState -Response $premiumPlusQuota `
    -ExpectedPlanCode "PREMIUM_PLUS" `
    -ExpectedAiAccessEnabled $true `
    -ExpectedTrialActive $false `
    -ExpectedTokenLimit $ExpectedPremiumPlusDailyTokenLimit

$finalFreePlanCode = if ($freeQuota.Json.ContainsKey("planCode")) { [string]$freeQuota.Json["planCode"] } else { "UNKNOWN" }
Write-Host "[ai-entitlement-smoke] PASS: userId=$userId trial->$finalFreePlanCode->premium->premium_plus flow validated."
