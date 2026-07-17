param(
    [string]$OutputPath = "",
    [string]$Tester = "manual-tester",
    [string]$Track = "internal",
    [string]$BackendUrl = "https://api.klioai.app",
    [string]$Device = "not-recorded",
    [string]$AndroidVersion = "not-recorded",
    [string]$PlayVersionCode = "not-recorded",
    [string]$AabArtifactName = "app-release.aab",
    [string]$GitHubRunUrl = "not-recorded",
    [string]$ReleaseChecklistPath = "not-recorded",
    [string]$Notes = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$pubspecPath = Join-Path $repoRoot "flutter_vocabmaster\pubspec.yaml"
$checklistPath = Join-Path $repoRoot "docs\PLAY_DISTRIBUTED_AAB_SMOKE_CHECKLIST.md"

if (-not (Test-Path -LiteralPath $pubspecPath -PathType Leaf)) {
    throw "Flutter pubspec not found: $pubspecPath"
}
if (-not (Test-Path -LiteralPath $checklistPath -PathType Leaf)) {
    throw "Play smoke checklist not found: $checklistPath"
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $reportDir = Join-Path $repoRoot "docs\play-smoke-reports"
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
    $OutputPath = Join-Path $reportDir "play-device-smoke-$stamp.md"
} elseif (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $repoRoot $OutputPath
}

$versionLine = Get-Content -LiteralPath $pubspecPath |
    Where-Object { $_ -match "^version:\s*" } |
    Select-Object -First 1
if (-not $versionLine) {
    throw "Could not find version in $pubspecPath"
}
$flutterVersionBuild = ($versionLine -replace "^version:\s*", "").Trim()
$generatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

function Get-GitValue {
    param([string[]]$GitArgs)
    try {
        $value = & git -C $repoRoot @GitArgs 2>$null
        if ([string]::IsNullOrWhiteSpace($value)) {
            return "unknown"
        }
        return ($value | Select-Object -First 1).ToString().Trim()
    } catch {
        return "unknown"
    }
}

$gitSha = Get-GitValue -GitArgs @("rev-parse", "HEAD")
$gitBranch = Get-GitValue -GitArgs @("rev-parse", "--abbrev-ref", "HEAD")

if (-not [string]::IsNullOrWhiteSpace($ReleaseChecklistPath) -and
    $ReleaseChecklistPath -ne "not-recorded" -and
    -not [System.IO.Path]::IsPathRooted($ReleaseChecklistPath)) {
    $ReleaseChecklistPath = Join-Path $repoRoot $ReleaseChecklistPath
}

$report = @"
# KlioAI Play Device Smoke Report

Generated at UTC: $generatedAt  
Tester: $Tester  
Track: $Track  
Backend URL: $BackendUrl

## Build Identity

| Field | Value |
| --- | --- |
| Flutter version/build | $flutterVersionBuild |
| Play version code | $PlayVersionCode |
| Git commit SHA | $gitSha |
| Git branch | $gitBranch |
| AAB artifact | $AabArtifactName |
| GitHub Actions run | $GitHubRunUrl |
| Release checklist | $ReleaseChecklistPath |
| Device | $Device |
| Android version | $AndroidVersion |

## Required Result

Mark every item below during the Play-installed device smoke. Use `PASS`,
`FAIL`, or `N/A`, and add notes for every failure.

| Area | Check | Result | Notes |
| --- | --- | --- | --- |
| Build | Installed from Google Play test track, not sideloaded | TODO | |
| Build | Profile > Account Settings version/build matches uploaded AAB | TODO | |
| Auth | Fresh install opens Google-only login | TODO | |
| Auth | Google Sign-In succeeds | TODO | |
| Auth | Email/password login is not visible | TODO | |
| Auth | Profile sign out and sign in again restore the same account | TODO | |
| Subscription | Monthly product visible and purchase/restore verifies backend entitlement | TODO | |
| Subscription | Annual product visible or tracked as Play Console config issue | TODO | |
| AI | Free or paid quota status matches Profile/Practice UI | TODO | |
| AI | Translation Practice generates and checks one item | TODO | |
| AI | Speaking transcription returns useful result, not generic connection error | TODO | |
| Practice | Top mode selector scrolls without right-edge overflow blocking taps | TODO | |
| Practice | Reading, Writing, Grammar, Speaking, Pronunciation, Word Galaxy, Neural modes are discoverable | TODO | |
| XP | Add word updates XP progress and weekly XP immediately | TODO | |
| XP | Add sentence updates XP progress and weekly XP immediately | TODO | |
| Daily Words | Add word and add-with-sentence persist to Words/Sentences correctly | TODO | |
| Notifications | Permission/preference flow works | TODO | |
| Notifications | Push tap opens expected app surface | TODO | |
| Policy | Privacy policy URL reachable | TODO | |
| Policy | Account deletion URL reachable | TODO | |
| Stability | App restart keeps expected auth/session state | TODO | |

## Backend/Console Checks

- [ ] `https://api.klioai.app/actuator/health` returns `UP`.
- [ ] The GitHub Actions run above completed successfully.
- [ ] The release checklist above was reviewed before this device smoke.
- [ ] Subscription transaction row appears after purchase/restore when tested.
- [ ] No new Play policy warning is present for this version.
- [ ] Data Safety form, privacy policy URL, and account deletion URL are still accepted by Play Console.

## Decision

- [ ] PASS: promote or keep rollout moving.
- [ ] HOLD: fix blockers before wider rollout.
- [ ] RETEST: Play processing or tester/device state was inconclusive.

## Notes

$Notes

## Reference Checklist

See `docs/PLAY_DISTRIBUTED_AAB_SMOKE_CHECKLIST.md` for the canonical long-form checklist.
"@

$outputDir = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}
Set-Content -LiteralPath $OutputPath -Value $report -Encoding UTF8

Write-Host "[play-smoke] Wrote $OutputPath"
