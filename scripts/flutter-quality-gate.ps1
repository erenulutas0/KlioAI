param(
    [switch]$SkipPubGet,
    [double]$CoverageThreshold = 32.5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$flutterDir = Join-Path $repoRoot "flutter_vocabmaster"
$coverageScript = Join-Path $PSScriptRoot "check-flutter-coverage.ps1"

function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    Write-Host "[flutter-quality] START: $Name"
    & $Action
    if ($LASTEXITCODE -ne 0) {
        throw "[flutter-quality] FAILED: $Name (exit=$LASTEXITCODE)"
    }
    Write-Host "[flutter-quality] PASS: $Name"
}

Push-Location $flutterDir
try {
    if (-not $SkipPubGet) {
        Invoke-Step -Name "flutter pub get" -Action {
            flutter pub get
        }
    }

    Invoke-Step -Name "flutter analyze" -Action {
        flutter analyze --no-fatal-warnings --no-fatal-infos
    }

    Invoke-Step -Name "flutter test --coverage" -Action {
        flutter test --coverage -r compact
    }

    Invoke-Step -Name "check flutter coverage" -Action {
        & $coverageScript -Threshold $CoverageThreshold
    }
} finally {
    Pop-Location
}

Write-Host "[flutter-quality] SUCCESS"
