param(
    [string]$ProjectName = "klioai-migration-preflight",
    [int]$BackendPort = 38082,
    [int]$BackendSocketPort = 39092,
    [int]$PostgresPort = 35432,
    [int]$RedisPort = 36379,
    [switch]$SkipContainerizedReadiness,
    [switch]$KeepContainers
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$composeBase = Join-Path $repoRoot "docker-compose.yml"
$composeSmoke = Join-Path $repoRoot "docker-compose.smoke.yml"
$dbReadinessScript = Join-Path $PSScriptRoot "run-db-readiness.ps1"
$cleanDbSmokeScript = Join-Path $PSScriptRoot "smoke-clean-db.ps1"
$dbParityScript = Join-Path $PSScriptRoot "check-db-parity.ps1"

function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    Write-Host "[migration-preflight] START: $Name"
    & $Action
    if ($LASTEXITCODE -ne 0) {
        throw "[migration-preflight] FAILED: $Name (exit=$LASTEXITCODE)"
    }
    Write-Host "[migration-preflight] PASS: $Name"
}

function Invoke-Cleanup {
    if ($KeepContainers) {
        Write-Host "[migration-preflight] Keeping containers running (ProjectName=$ProjectName)."
        return
    }

    Write-Host "[migration-preflight] Cleanup: docker compose down --volumes"
    try {
        & docker compose -p $ProjectName -f $composeBase -f $composeSmoke down --volumes --remove-orphans
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "[migration-preflight] Cleanup failed with exit=$LASTEXITCODE"
        }
    } catch {
        Write-Warning "[migration-preflight] Cleanup threw: $($_.Exception.Message)"
    }
}

foreach ($scriptPath in @($cleanDbSmokeScript, $dbParityScript)) {
    if (-not (Test-Path $scriptPath)) {
        throw "Required script not found: $scriptPath"
    }
}

try {
    if (-not $SkipContainerizedReadiness) {
        if (-not (Test-Path $dbReadinessScript)) {
            throw "Required script not found: $dbReadinessScript"
        }

        Invoke-Step -Name "Testcontainers Flyway readiness" -Action {
            pwsh -NoProfile -File $dbReadinessScript -FailOnSkip -SkipSmokeFallback
        }
    } else {
        Write-Warning "[migration-preflight] Skipping Testcontainers readiness by flag."
    }

    Invoke-Step -Name "Clean Docker Compose DB smoke" -Action {
        pwsh -NoProfile -File $cleanDbSmokeScript `
            -ProjectName $ProjectName `
            -BackendPort $BackendPort `
            -BackendSocketPort $BackendSocketPort `
            -PostgresPort $PostgresPort `
            -RedisPort $RedisPort `
            -KeepContainers
    }

    Invoke-Step -Name "Explicit DB parity check" -Action {
        pwsh -NoProfile -File $dbParityScript -ProjectName $ProjectName
    }

    Write-Host "[migration-preflight] SUCCESS: migration preflight passed."
} finally {
    Invoke-Cleanup
}
