param(
    [string]$BaseUrl = "https://api.klioai.app",
    [string]$AllowedOrigin = "https://klioai.app",
    [string]$AccessToken = "",
    [string]$UserId = "",
    [int]$TimeoutSec = 15,
    [int]$MaxDailyWords = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

function Invoke-JsonProbe {
    param(
        [ValidateSet("GET", "OPTIONS")]
        [string]$Method,
        [string]$Path,
        [hashtable]$Headers = @{}
    )

    $uri = "$($BaseUrl.TrimEnd('/'))$Path"
    $response = Invoke-WebRequest `
        -Method $Method `
        -Uri $uri `
        -Headers $Headers `
        -TimeoutSec $TimeoutSec `
        -UseBasicParsing `
        -SkipHttpErrorCheck

    $content = $response.Content
    if ($content -is [byte[]]) {
        $content = [System.Text.Encoding]::UTF8.GetString($content)
    } elseif ($null -ne $content) {
        $content = [string]$content
    } else {
        $content = ""
    }

    $json = $null
    if (-not [string]::IsNullOrWhiteSpace($content)) {
        try {
            $json = $content | ConvertFrom-Json
        } catch {
            $json = $null
        }
    }

    return [PSCustomObject]@{
        StatusCode = [int]$response.StatusCode
        Headers = $response.Headers
        Json = $json
        Raw = $content
        Uri = $uri
    }
}

function Get-HeaderValue {
    param(
        [object]$Headers,
        [string]$Name
    )

    if ($null -eq $Headers) {
        return $null
    }

    try {
        $value = $Headers[$Name]
        if ($null -ne $value) {
            if ($value -is [System.Array]) {
                return ($value -join ",")
            }
            return [string]$value
        }
    } catch {
        return $null
    }

    return $null
}

$normalizedBase = $BaseUrl.TrimEnd("/")
Write-Host "[prod-smoke] base_url=$normalizedBase"

$health = Invoke-JsonProbe -Method GET -Path "/actuator/health"
Assert-True ($health.StatusCode -eq 200) "[prod-smoke] health status expected 200, got $($health.StatusCode)"
Assert-True ($health.Json.status -eq "UP") "[prod-smoke] health JSON status expected UP, got '$($health.Json.status)'"
Write-Host "[prod-smoke] PASS health"

$protectedApi = Invoke-JsonProbe -Method GET -Path "/api"
Assert-True ($protectedApi.StatusCode -eq 401) "[prod-smoke] protected /api expected 401 without auth, got $($protectedApi.StatusCode)"
Write-Host "[prod-smoke] PASS protected-api-auth-gate"

$plans = Invoke-JsonProbe -Method GET -Path "/api/subscription/plans"
Assert-True ($plans.StatusCode -eq 200) "[prod-smoke] plans expected 200, got $($plans.StatusCode)"
$planCount = @($plans.Json).Count
Assert-True ($planCount -ge 1) "[prod-smoke] expected at least one subscription plan"
Write-Host "[prod-smoke] PASS subscription-plans count=$planCount"

if (-not [string]::IsNullOrWhiteSpace($AccessToken) -and -not [string]::IsNullOrWhiteSpace($UserId)) {
    $dailyWords = Invoke-JsonProbe -Method GET -Path "/api/content/daily-words" -Headers @{
        "Authorization" = "Bearer $AccessToken"
        "X-User-Id" = $UserId
    }
    Assert-True ($dailyWords.StatusCode -eq 200) "[prod-smoke] daily words expected 200, got $($dailyWords.StatusCode)"
    Assert-True ([bool]$dailyWords.Json.success) "[prod-smoke] daily words success=false"
    $wordCount = @($dailyWords.Json.words).Count
    Assert-True ($wordCount -ge 1) "[prod-smoke] expected at least one daily word"
    Assert-True ($wordCount -le $MaxDailyWords) "[prod-smoke] expected <= $MaxDailyWords daily words, got $wordCount"
    Write-Host "[prod-smoke] PASS daily-words count=$wordCount"
} else {
    $dailyWordsGate = Invoke-JsonProbe -Method GET -Path "/api/content/daily-words"
    Assert-True ($dailyWordsGate.StatusCode -eq 401) "[prod-smoke] unauthenticated daily words expected 401, got $($dailyWordsGate.StatusCode)"
    Write-Host "[prod-smoke] PASS daily-words-auth-gate"
}

$preflight = Invoke-JsonProbe -Method OPTIONS -Path "/api/auth/google-login" -Headers @{
    "Origin" = $AllowedOrigin
    "Access-Control-Request-Method" = "POST"
}
Assert-True ($preflight.StatusCode -ge 200 -and $preflight.StatusCode -lt 300) "[prod-smoke] CORS preflight expected 2xx, got $($preflight.StatusCode)"
$acao = Get-HeaderValue -Headers $preflight.Headers -Name "Access-Control-Allow-Origin"
Assert-True ($acao -eq $AllowedOrigin) "[prod-smoke] CORS allowed origin mismatch. expected='$AllowedOrigin' actual='$acao'"
Write-Host "[prod-smoke] PASS cors-preflight origin=$acao"

$hsts = Get-HeaderValue -Headers $health.Headers -Name "Strict-Transport-Security"
Assert-True (-not [string]::IsNullOrWhiteSpace($hsts)) "[prod-smoke] missing Strict-Transport-Security header"
Write-Host "[prod-smoke] PASS hsts"

Write-Host "[prod-smoke] SUCCESS"
