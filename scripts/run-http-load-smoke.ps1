param(
    [Parameter(Mandatory = $true)]
    [string]$Uri,

    [int]$TotalRequests = 1000,
    [int]$Concurrency = 30,
    [int]$TimeoutSec = 10,
    [string]$HeadersJson = "{}"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($TotalRequests -le 0) {
    throw "TotalRequests must be > 0"
}
if ($Concurrency -le 0) {
    throw "Concurrency must be > 0"
}

function Get-Percentile {
    param(
        [double[]]$Values,
        [double]$Percentile
    )

    if ($null -eq $Values -or $Values.Count -eq 0) {
        return 0
    }

    $sorted = $Values | Sort-Object
    $index = [Math]::Ceiling(($Percentile / 100.0) * $sorted.Count) - 1
    if ($index -lt 0) {
        $index = 0
    }
    if ($index -ge $sorted.Count) {
        $index = $sorted.Count - 1
    }
    return [Math]::Round([double]$sorted[$index], 2)
}

$headers = ConvertFrom-Json $HeadersJson -AsHashtable

$all = [System.Diagnostics.Stopwatch]::StartNew()
$results = 1..$TotalRequests | ForEach-Object -Parallel {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $code = -1
    $ok = $false

    try {
        $resp = Invoke-WebRequest -UseBasicParsing -Uri $using:Uri -Headers $using:headers -TimeoutSec $using:TimeoutSec
        $code = [int]$resp.StatusCode
        $ok = ($code -ge 200 -and $code -lt 400)
    } catch {
        if ($_.Exception.Response) {
            $code = [int]$_.Exception.Response.StatusCode.value__
        }
    }

    $sw.Stop()
    [PSCustomObject]@{
        code = $code
        ok = $ok
        ms = [Math]::Round($sw.Elapsed.TotalMilliseconds, 2)
    }
} -ThrottleLimit $Concurrency
$all.Stop()

$resultList = @($results)
$okCount = @($resultList | Where-Object { $_.ok }).Count
$errorCount = $resultList.Count - $okCount
$latencies = [double[]](@($resultList | Select-Object -ExpandProperty ms))
if ($latencies.Count -gt 0) {
    $avg = [Math]::Round((($latencies | Measure-Object -Average).Average), 2)
    $min = [Math]::Round((($latencies | Measure-Object -Minimum).Minimum), 2)
    $max = [Math]::Round((($latencies | Measure-Object -Maximum).Maximum), 2)
} else {
    $avg = 0
    $min = 0
    $max = 0
}
$p95 = Get-Percentile -Values $latencies -Percentile 95
$p99 = Get-Percentile -Values $latencies -Percentile 99
$durationSec = [Math]::Round($all.Elapsed.TotalSeconds, 2)
$rps = [Math]::Round($TotalRequests / $all.Elapsed.TotalSeconds, 2)
$successRate = [Math]::Round((100.0 * $okCount / $TotalRequests), 2)

Write-Host "[load-smoke] target=$Uri total=$TotalRequests concurrency=$Concurrency timeout_sec=$TimeoutSec"
Write-Host "[load-smoke] ok=$okCount err=$errorCount success_rate=$successRate% duration_s=$durationSec rps=$rps"
Write-Host "[load-smoke] latency_ms min=$min avg=$avg p95=$p95 p99=$p99 max=$max"

$resultList |
    Group-Object code |
    Sort-Object Name |
    ForEach-Object {
        Write-Host "[load-smoke] status_code[$($_.Name)]=$($_.Count)"
    }
