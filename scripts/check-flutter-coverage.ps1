param(
    [double]$Threshold = 32.5,
    [string]$LcovPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($Threshold -lt 0 -or $Threshold -gt 100) {
    throw "Threshold must be between 0 and 100."
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

if ([string]::IsNullOrWhiteSpace($LcovPath)) {
    $LcovPath = Join-Path $repoRoot "flutter_vocabmaster\coverage\lcov.info"
} elseif (-not [System.IO.Path]::IsPathRooted($LcovPath)) {
    $LcovPath = Join-Path $repoRoot $LcovPath
}

if (-not (Test-Path $LcovPath)) {
    throw "LCOV file not found: $LcovPath"
}

$linesFound = 0
$linesHit = 0

Get-Content $LcovPath | ForEach-Object {
    if ($_.StartsWith("LF:")) {
        $linesFound += [int]$_.Substring(3)
    } elseif ($_.StartsWith("LH:")) {
        $linesHit += [int]$_.Substring(3)
    }
}

if ($linesFound -le 0) {
    throw "No measurable lines found in LCOV file: $LcovPath"
}

$coverage = [math]::Round((100.0 * $linesHit / $linesFound), 2)
$coverageText = $coverage.ToString("F2", [System.Globalization.CultureInfo]::InvariantCulture)
$thresholdText = $Threshold.ToString("F2", [System.Globalization.CultureInfo]::InvariantCulture)

Write-Host "[flutter-coverage] Line coverage: $coverageText% (covered=$linesHit, total=$linesFound)"
Write-Host "[flutter-coverage] Threshold: $thresholdText%"

if ($coverage -lt $Threshold) {
    throw "Flutter coverage gate failed: $coverageText% < $thresholdText%"
}

Write-Host "[flutter-coverage] SUCCESS: coverage gate passed."
