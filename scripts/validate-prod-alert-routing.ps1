param(
    [switch]$SkipComposeConfig,
    [switch]$SkipPaymentChecks,
    [switch]$SkipAlertmanagerChecks
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$dotenvPath = Join-Path $repoRoot ".env"

function Read-DotEnv {
    param([string]$Path)

    $map = @{}
    if (-not (Test-Path $Path)) {
        return $map
    }

    foreach ($line in Get-Content $Path) {
        if ($line -match "^\s*#") {
            continue
        }
        if ($line -match "^\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)$") {
            $key = $matches[1]
            $value = $matches[2].Trim()
            $map[$key] = $value
        }
    }

    return $map
}

function Resolve-EnvValue {
    param(
        [string]$Name,
        [hashtable]$DotEnv
    )

    $value = [Environment]::GetEnvironmentVariable($Name)
    if (-not [string]::IsNullOrWhiteSpace($value)) {
        return $value
    }

    if ($DotEnv.ContainsKey($Name)) {
        return [string]$DotEnv[$Name]
    }

    return ""
}

$dotenv = Read-DotEnv -Path $dotenvPath

$requiredVars = New-Object System.Collections.Generic.List[string]
@(
    "POSTGRES_PASSWORD",
    "SPRING_DATA_REDIS_PASSWORD",
    "APP_CORS_ALLOWED_ORIGINS",
    "GROQ_API_KEY",
    "APP_SUBSCRIPTION_GOOGLE_PLAY_PACKAGE_NAME",
    "APP_SUBSCRIPTION_GOOGLE_PLAY_SERVICE_ACCOUNT_HOST_PATH"
) | ForEach-Object { [void]$requiredVars.Add($_) }

if (-not $SkipPaymentChecks) {
    Write-Host "[prod-alert-routing] INFO: Payment env checks are skipped by design (Google Play Billing only)."
}

if (-not $SkipAlertmanagerChecks) {
    @(
        "ALERTMANAGER_DEFAULT_WEBHOOK_URL",
        "ALERTMANAGER_CRITICAL_WEBHOOK_URL",
        "ALERTMANAGER_WARNING_WEBHOOK_URL"
    ) | ForEach-Object { [void]$requiredVars.Add($_) }
}

$missing = New-Object System.Collections.Generic.List[string]
foreach ($name in $requiredVars) {
    $value = Resolve-EnvValue -Name $name -DotEnv $dotenv
    if ([string]::IsNullOrWhiteSpace($value)) {
        $missing.Add($name)
    }
}

$googleServiceAccountHostPath = Resolve-EnvValue -Name "APP_SUBSCRIPTION_GOOGLE_PLAY_SERVICE_ACCOUNT_HOST_PATH" -DotEnv $dotenv
if (-not [string]::IsNullOrWhiteSpace($googleServiceAccountHostPath)) {
    if (-not (Test-Path -Path $googleServiceAccountHostPath -PathType Leaf)) {
        $missing.Add("APP_SUBSCRIPTION_GOOGLE_PLAY_SERVICE_ACCOUNT_HOST_PATH(file-not-found)")
    }
}

if ($missing.Count -gt 0) {
    throw "[prod-alert-routing] Missing required env vars: $($missing -join ', ')"
}

Write-Host "[prod-alert-routing] Required env vars are present."

if ($SkipComposeConfig) {
    Write-Host "[prod-alert-routing] Skipping compose config validation by request."
    Write-Host "[prod-alert-routing] SUCCESS"
    return
}

$composeBase = Join-Path $repoRoot "docker-compose.yml"
$composeMonitoring = Join-Path $repoRoot "docker-compose.monitoring.yml"
$composeProd = Join-Path $repoRoot "docker-compose.prod.yml"

# If alert checks are skipped, production overlays may still enforce missing webhook vars
# with `${VAR:?}`. In that case validate only the base compose file for syntax/sanity.
if ($SkipAlertmanagerChecks) {
    & docker compose -f $composeBase config | Out-Null
} else {
    & docker compose -f $composeBase -f $composeMonitoring -f $composeProd config | Out-Null
}
if ($LASTEXITCODE -ne 0) {
    throw "[prod-alert-routing] docker compose config failed."
}

Write-Host "[prod-alert-routing] docker compose config passed."
Write-Host "[prod-alert-routing] SUCCESS"
