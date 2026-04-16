param(
    [ValidateSet("prod-preflight", "nonprod-smoke", "local-gate", "full")]
    [string]$Mode = "full",
    [string]$ProjectName = "flutter-project-main",
    [string]$BackendBaseUrl = "http://localhost:8082",
    [string]$SecuritySmokeAllowedOrigin = "",
    [string]$SecuritySmokeDisallowedOrigin = "http://evil.example.com",
    [switch]$SkipPaymentChecks,
    [switch]$SkipAlertmanagerChecks
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$validateProdScript = Join-Path $PSScriptRoot "validate-prod-alert-routing.ps1"
$reconcileAllScript = Join-Path $PSScriptRoot "reconcile-all-nonprod.ps1"
$loadSmokeScript = Join-Path $PSScriptRoot "run-http-load-smoke.ps1"
$securitySmokeScript = Join-Path $PSScriptRoot "smoke-security-cors-headers.ps1"
$runtimeIsolationScript = Join-Path $PSScriptRoot "check-runtime-isolation.ps1"
$runtimeProdFlagsScript = Join-Path $PSScriptRoot "check-runtime-prod-flags.ps1"
$googleSigninConfigScript = Join-Path $PSScriptRoot "check-google-signin-android-config.ps1"
$coverageScript = Join-Path $PSScriptRoot "check-core-coverage.ps1"
$parityScript = Join-Path $PSScriptRoot "check-db-parity.ps1"
$aiEntitlementSmokeScript = Join-Path $PSScriptRoot "smoke-ai-entitlement-flow.ps1"
$backendDir = Join-Path $repoRoot "backend"

function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    Write-Host "[verify-rollout] START: $Name"
    & $Action
    if ($LASTEXITCODE -ne 0) {
        throw "[verify-rollout] FAILED: $Name (exit=$LASTEXITCODE)"
    }
    Write-Host "[verify-rollout] PASS: $Name"
}

function Run-ProdPreflight {
    Invoke-Step -Name "runtime-prod-flags-check" -Action {
        & $runtimeProdFlagsScript -ProjectName $ProjectName
    }

    Invoke-Step -Name "validate-prod-alert-routing" -Action {
        & $validateProdScript -SkipPaymentChecks:$SkipPaymentChecks -SkipAlertmanagerChecks:$SkipAlertmanagerChecks
    }
}

function Run-NonProdSmoke {
    Invoke-Step -Name "runtime-isolation-check" -Action {
        & $runtimeIsolationScript -ProjectName $ProjectName
    }

    Invoke-Step -Name "reconcile-all-nonprod" -Action {
        & $reconcileAllScript -ProjectNames $ProjectName
    }

    Invoke-Step -Name "load-smoke health" -Action {
        & $loadSmokeScript -Uri "$BackendBaseUrl/actuator/health" -TotalRequests 2000 -Concurrency 50
    }

    Invoke-Step -Name "load-smoke subscription-plans" -Action {
        & $loadSmokeScript -Uri "$BackendBaseUrl/api/subscription/plans" -TotalRequests 1000 -Concurrency 30
    }

    Invoke-Step -Name "ai-entitlement-smoke" -Action {
        & $aiEntitlementSmokeScript -BackendBaseUrl $BackendBaseUrl -ProjectName $ProjectName
    }

    if (-not [string]::IsNullOrWhiteSpace($SecuritySmokeAllowedOrigin)) {
        Invoke-Step -Name "security-cors-headers-smoke" -Action {
            & $securitySmokeScript -BaseUrl $BackendBaseUrl -AllowedOrigin $SecuritySmokeAllowedOrigin -DisallowedOrigin $SecuritySmokeDisallowedOrigin
        }
    } else {
        Write-Host "[verify-rollout] SKIP: security-cors-headers-smoke (SecuritySmokeAllowedOrigin not provided)"
    }
}

function Run-LocalGate {
    Invoke-Step -Name "check-google-signin-android-config" -Action {
        & $googleSigninConfigScript
    }

    Invoke-Step -Name "mvn -q test" -Action {
        Push-Location $backendDir
        try {
            & mvn -q test
        } finally {
            Pop-Location
        }
    }

    Invoke-Step -Name "check-core-coverage" -Action {
        & $coverageScript -Threshold 90
    }

    Invoke-Step -Name "check-db-parity" -Action {
        & $parityScript -ProjectName $ProjectName
    }
}

switch ($Mode) {
    "prod-preflight" {
        Run-ProdPreflight
    }
    "nonprod-smoke" {
        Run-NonProdSmoke
    }
    "local-gate" {
        Run-LocalGate
    }
    "full" {
        Run-ProdPreflight
        Run-NonProdSmoke
        Run-LocalGate
    }
    default {
        throw "Unknown mode: $Mode"
    }
}

Write-Host "[verify-rollout] SUCCESS: mode '$Mode' completed."
