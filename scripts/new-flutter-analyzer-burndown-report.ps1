param(
    [string]$OutputPath = "",
    [int]$TopFiles = 20
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$flutterDir = Join-Path $repoRoot "flutter_vocabmaster"

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $reportDir = Join-Path $repoRoot "docs\quality-reports"
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
    $OutputPath = Join-Path $reportDir "flutter-analyzer-burndown-$stamp.md"
} elseif (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $repoRoot $OutputPath
}

$machineOutput = Join-Path $env:TEMP "klioai-flutter-analyze-machine-$([Guid]::NewGuid().ToString('N')).txt"

Push-Location $flutterDir
try {
    dart analyze --format=machine > $machineOutput
    $analyzeExit = $LASTEXITCODE
} finally {
    Pop-Location
}

$items = Get-Content -LiteralPath $machineOutput |
    Where-Object { $_ -match "^(INFO|WARNING|ERROR)\|" } |
    ForEach-Object {
        $parts = $_ -split "\|"
        [pscustomobject]@{
            Severity = $parts[0]
            Type     = $parts[1]
            Code     = $parts[2]
            File     = $parts[3].Replace($repoRoot + "\", "")
            Line     = [int]$parts[4]
            Message  = $parts[7]
        }
    }

Remove-Item -LiteralPath $machineOutput -Force -ErrorAction SilentlyContinue

$generatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$total = @($items).Count
$warnings = @($items | Where-Object Severity -eq "WARNING").Count
$errors = @($items | Where-Object Severity -eq "ERROR").Count
$infos = @($items | Where-Object Severity -eq "INFO").Count

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Flutter Analyzer Burn-down Report") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("Generated at UTC: $generatedAt") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("## Summary") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Metric | Count |") | Out-Null
$lines.Add("| --- | ---: |") | Out-Null
$lines.Add("| Errors | $errors |") | Out-Null
$lines.Add("| Warnings | $warnings |") | Out-Null
$lines.Add("| Infos | $infos |") | Out-Null
$lines.Add("| Total | $total |") | Out-Null
$lines.Add("| Analyzer exit code | $analyzeExit |") | Out-Null
$lines.Add("") | Out-Null

$lines.Add("## Issues By Code") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Code | Count |") | Out-Null
$lines.Add("| --- | ---: |") | Out-Null
foreach ($group in ($items | Group-Object Code | Sort-Object Count -Descending)) {
    $lines.Add("| ``$($group.Name)`` | $($group.Count) |") | Out-Null
}
$lines.Add("") | Out-Null

$lines.Add("## Top Files") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| File | Count |") | Out-Null
$lines.Add("| --- | ---: |") | Out-Null
foreach ($group in ($items | Group-Object File | Sort-Object Count -Descending | Select-Object -First $TopFiles)) {
    $lines.Add("| ``$($group.Name)`` | $($group.Count) |") | Out-Null
}
$lines.Add("") | Out-Null

$lines.Add("## Recommended Burn-down Order") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("1. Keep `WARNING` and `ERROR` counts at zero first.") | Out-Null
$lines.Add("2. Convert `withOpacity` to `withValues(alpha: ...)` screen by screen.") | Out-Null
$lines.Add("3. Apply `prefer_const_constructors` only in files already touched by behavior or test work.") | Out-Null
$lines.Add("4. Re-run this report after each focused cleanup batch.") | Out-Null

$outputDir = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}
Set-Content -LiteralPath $OutputPath -Value $lines -Encoding UTF8

Write-Host "[analyzer-burndown] Wrote $OutputPath"
Write-Host "[analyzer-burndown] Errors=$errors Warnings=$warnings Infos=$infos Total=$total"
