param(
    [string]$OutputPath,
    [string]$BackendUrl = "https://api.klioai.app",
    [string]$PreparedBy = "Codex",
    [string]$BackendDeployTimestamp = "not-deployed-in-this-release",
    [string]$BackendImageOrLabel = "not-recorded",
    [string]$AndroidArtifact = "app-release.aab"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$templatePath = Join-Path $repoRoot "docs\RELEASE_CHECKLIST_TEMPLATE.md"
$pubspecPath = Join-Path $repoRoot "flutter_vocabmaster\pubspec.yaml"

if (-not (Test-Path $templatePath)) {
    throw "Release checklist template not found: $templatePath"
}
if (-not (Test-Path $pubspecPath)) {
    throw "Flutter pubspec not found: $pubspecPath"
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $releaseDir = Join-Path $repoRoot "docs\release-checklists"
    New-Item -ItemType Directory -Path $releaseDir -Force | Out-Null
    $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
    $OutputPath = Join-Path $releaseDir "klioai-release-checklist-$stamp.md"
} elseif (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $repoRoot $OutputPath
}

$outputDir = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$versionLine = Get-Content $pubspecPath | Where-Object { $_ -match "^version:\s*" } | Select-Object -First 1
if (-not $versionLine) {
    throw "Could not find version in $pubspecPath"
}
$flutterVersionBuild = ($versionLine -replace "^version:\s*", "").Trim()

function Get-GitHeadSha {
    try {
        $value = (& git -C $repoRoot rev-parse HEAD 2>$null)
        if ([string]::IsNullOrWhiteSpace($value)) {
            return "unknown"
        }
        return ($value | Select-Object -First 1).ToString().Trim()
    } catch {
        return "unknown"
    }
}

function Get-GitBranch {
    try {
        $value = (& git -C $repoRoot rev-parse --abbrev-ref HEAD 2>$null)
        if ([string]::IsNullOrWhiteSpace($value)) {
            return "unknown"
        }
        return ($value | Select-Object -First 1).ToString().Trim()
    } catch {
        return "unknown"
    }
}

$gitSha = Get-GitHeadSha
$gitBranch = Get-GitBranch
$generatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$safeVersion = $flutterVersionBuild -replace "[^A-Za-z0-9._+-]", "-"
$releaseId = "klioai-$safeVersion-$($gitSha.Substring(0, [Math]::Min(12, $gitSha.Length)))"

$content = Get-Content $templatePath -Raw
$replacements = @{
    "{{RELEASE_ID}}" = $releaseId
    "{{GENERATED_AT_UTC}}" = $generatedAt
    "{{PREPARED_BY}}" = $PreparedBy
    "{{FLUTTER_VERSION_BUILD}}" = $flutterVersionBuild
    "{{GIT_COMMIT_SHA}}" = $gitSha
    "{{GIT_BRANCH}}" = $gitBranch
    "{{BACKEND_URL}}" = $BackendUrl
    "{{BACKEND_DEPLOY_TIMESTAMP}}" = $BackendDeployTimestamp
    "{{BACKEND_IMAGE_OR_LABEL}}" = $BackendImageOrLabel
    "{{ANDROID_ARTIFACT}}" = $AndroidArtifact
}

foreach ($entry in $replacements.GetEnumerator()) {
    $content = $content.Replace($entry.Key, $entry.Value)
}

Set-Content -Path $OutputPath -Value $content -Encoding UTF8
Write-Host "[release-checklist] Wrote $OutputPath"
