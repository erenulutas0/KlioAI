param(
    [double]$Threshold = 85.0,
    [string]$JacocoCsvPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($Threshold -lt 0 -or $Threshold -gt 100) {
    throw "Threshold must be between 0 and 100."
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$backendDir = Join-Path $repoRoot "backend"

if ([string]::IsNullOrWhiteSpace($JacocoCsvPath)) {
    $JacocoCsvPath = Join-Path $backendDir "target\site\jacoco\jacoco.csv"
} elseif (-not [System.IO.Path]::IsPathRooted($JacocoCsvPath)) {
    $JacocoCsvPath = Join-Path $repoRoot $JacocoCsvPath
}

if (-not (Test-Path $JacocoCsvPath)) {
    throw "JaCoCo CSV not found: $JacocoCsvPath"
}

$rows = Import-Csv $JacocoCsvPath
if ($null -eq $rows -or $rows.Count -eq 0) {
    throw "JaCoCo CSV is empty: $JacocoCsvPath"
}

function Test-IsCoreClass {
    param(
        [string]$PackageName,
        [string]$ClassName
    )

    if ([string]::IsNullOrWhiteSpace($ClassName)) {
        return $false
    }

    # Skip synthetic anonymous classes emitted by JaCoCo.
    if ($ClassName -match "\.new\s") {
        return $false
    }

    $communityPattern = "(friendship|social|feed|notification|matchmaking)"
    if ($PackageName -match $communityPattern -or $ClassName -match $communityPattern) {
        return $false
    }

    # Chatbot is core; generic chat module classes remain excluded.
    if ($ClassName -match "^Chat(?!bot)") {
        return $false
    }

    # Community-related DTO/entity/config classes still present in the same package tree.
    if ($ClassName -in @(
        "MessageDto",
        "PostDto",
        "Message",
        "Post",
        "PostLike",
        "Comment",
        "SocketIOConfig",
        "SSLUtils"
    )) {
        return $false
    }

    return $true
}

$coreRows = @()
foreach ($row in $rows) {
    if (Test-IsCoreClass -PackageName $row.PACKAGE -ClassName $row.CLASS) {
        $lineMissed = [int]$row.LINE_MISSED
        $lineCovered = [int]$row.LINE_COVERED
        if (($lineMissed + $lineCovered) -gt 0) {
            $coreRows += $row
        }
    }
}

if ($coreRows.Count -eq 0) {
    throw "No core classes found in JaCoCo CSV after filtering."
}

$totalMissed = ($coreRows | Measure-Object -Property LINE_MISSED -Sum).Sum
$totalCovered = ($coreRows | Measure-Object -Property LINE_COVERED -Sum).Sum
$totalLines = $totalMissed + $totalCovered

if ($totalLines -le 0) {
    throw "No measurable core lines found for coverage gate."
}

$coverage = [math]::Round((100.0 * $totalCovered / $totalLines), 2)
$coverageInvariant = $coverage.ToString("F2", [System.Globalization.CultureInfo]::InvariantCulture)
$thresholdInvariant = $Threshold.ToString("F2", [System.Globalization.CultureInfo]::InvariantCulture)

Write-Host "[coverage-gate] Core line coverage: $coverageInvariant% (covered=$totalCovered, total=$totalLines, classes=$($coreRows.Count))"
Write-Host "[coverage-gate] Threshold: $thresholdInvariant%"

if ($coverage -lt $Threshold) {
    Write-Warning "[coverage-gate] Coverage is below threshold. Lowest core classes:"

    $coreRows |
        ForEach-Object {
            $miss = [int]$_.LINE_MISSED
            $cov = [int]$_.LINE_COVERED
            $total = $miss + $cov
            [pscustomobject]@{
                CLASS = $_.CLASS
                COVERAGE = [math]::Round((100.0 * $cov / $total), 2)
                MISSED = $miss
                COVERED = $cov
            }
        } |
        Sort-Object COVERAGE, MISSED -Descending:$false |
        Select-Object -First 20 |
        Format-Table -AutoSize |
        Out-String |
        Write-Host

    throw "Core coverage gate failed: $coverageInvariant% < $thresholdInvariant%"
}

Write-Host "[coverage-gate] SUCCESS: coverage gate passed."
