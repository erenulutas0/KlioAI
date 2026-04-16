param(
    [string]$BaseUrl = "http://localhost:8082",
    [Parameter(Mandatory = $true)]
    [string]$AllowedOrigin,
    [string]$DisallowedOrigin = "http://localhost:8080",
    [string]$PreflightPath = "/api/auth/login",
    [string]$HeaderProbePath = "/actuator/health",
    [int]$TimeoutSec = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-Http {
    param(
        [string]$Method,
        [string]$Uri,
        [hashtable]$Headers
    )

    try {
        $response = Invoke-WebRequest -Method $Method -Uri $Uri -Headers $Headers -TimeoutSec $TimeoutSec -UseBasicParsing -SkipHttpErrorCheck
        return [PSCustomObject]@{
            StatusCode = [int]$response.StatusCode
            Headers = $response.Headers
            Body = $response.Content
        }
    } catch {
        throw
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

    if ($Headers -is [System.Net.Http.Headers.HttpHeaders]) {
        $values = $null
        if ($Headers.TryGetValues($Name, [ref]$values)) {
            return ($values -join ",")
        }
        return $null
    }

    try {
        $value = $Headers[$Name]
    } catch {
        $value = $null
    }

    if ($null -ne $value) {
        if ($value -is [System.Array] -or $value -is [System.Collections.IEnumerable]) {
            return ($value -join ",")
        }
        return [string]$value
    }

    if ($Headers.PSObject.Properties.Name -contains "Keys") {
        foreach ($key in $Headers.Keys) {
            if ($key -ieq $Name) {
                $candidate = $Headers[$key]
                if ($candidate -is [System.Array] -or $candidate -is [System.Collections.IEnumerable]) {
                    return ($candidate -join ",")
                }
                return [string]$candidate
            }
        }
    }

    return $null
}

$normalizedBase = $BaseUrl.TrimEnd("/")
$preflightUri = "$normalizedBase$PreflightPath"
$headersUri = "$normalizedBase$HeaderProbePath"

Write-Host "[security-smoke] base_url=$normalizedBase"
Write-Host "[security-smoke] allowed_origin=$AllowedOrigin disallowed_origin=$DisallowedOrigin"

$allowedPreflight = Invoke-Http -Method "OPTIONS" -Uri $preflightUri -Headers @{
    "Origin" = $AllowedOrigin
    "Access-Control-Request-Method" = "POST"
}
$allowedAcaOrigin = Get-HeaderValue -Headers $allowedPreflight.Headers -Name "Access-Control-Allow-Origin"
$allowedAcaCreds = Get-HeaderValue -Headers $allowedPreflight.Headers -Name "Access-Control-Allow-Credentials"

if ($allowedPreflight.StatusCode -lt 200 -or $allowedPreflight.StatusCode -ge 300) {
    throw "[security-smoke] Allowed-origin preflight failed: status=$($allowedPreflight.StatusCode) uri=$preflightUri"
}
if ($allowedAcaOrigin -ne $AllowedOrigin) {
    throw "[security-smoke] Allowed-origin preflight missing/invalid Access-Control-Allow-Origin. expected='$AllowedOrigin' actual='$allowedAcaOrigin'"
}
if ($allowedAcaCreds -ne "true") {
    throw "[security-smoke] Allowed-origin preflight missing/invalid Access-Control-Allow-Credentials. expected='true' actual='$allowedAcaCreds'"
}
Write-Host "[security-smoke] PASS allowed-origin preflight: status=$($allowedPreflight.StatusCode)"

$blockedPreflight = Invoke-Http -Method "OPTIONS" -Uri $preflightUri -Headers @{
    "Origin" = $DisallowedOrigin
    "Access-Control-Request-Method" = "POST"
}
$blockedAcaOrigin = Get-HeaderValue -Headers $blockedPreflight.Headers -Name "Access-Control-Allow-Origin"
$isBlocked = ($blockedPreflight.StatusCode -eq 403) -or [string]::IsNullOrWhiteSpace($blockedAcaOrigin) -or ($blockedAcaOrigin -ne $DisallowedOrigin)
if (-not $isBlocked) {
    throw "[security-smoke] Disallowed-origin preflight was unexpectedly accepted. status=$($blockedPreflight.StatusCode) acao='$blockedAcaOrigin'"
}
Write-Host "[security-smoke] PASS disallowed-origin preflight: status=$($blockedPreflight.StatusCode) acao='$blockedAcaOrigin'"

$headersResponse = Invoke-Http -Method "GET" -Uri $headersUri -Headers @{
    "Origin" = $AllowedOrigin
    "X-Forwarded-Proto" = "https"
}
if ($headersResponse.StatusCode -lt 200 -or $headersResponse.StatusCode -ge 300) {
    throw "[security-smoke] Header probe request failed: status=$($headersResponse.StatusCode) uri=$headersUri"
}

$requiredExactHeaders = @{
    "X-Content-Type-Options" = "nosniff"
    "X-Frame-Options" = "DENY"
    "Referrer-Policy" = "no-referrer"
}

foreach ($entry in $requiredExactHeaders.GetEnumerator()) {
    $actual = Get-HeaderValue -Headers $headersResponse.Headers -Name $entry.Key
    if ($actual -ne $entry.Value) {
        throw "[security-smoke] Missing/invalid header '$($entry.Key)'. expected='$($entry.Value)' actual='$actual'"
    }
}

$permissionsPolicy = Get-HeaderValue -Headers $headersResponse.Headers -Name "Permissions-Policy"
if ([string]::IsNullOrWhiteSpace($permissionsPolicy)) {
    throw "[security-smoke] Missing Permissions-Policy header"
}

$csp = Get-HeaderValue -Headers $headersResponse.Headers -Name "Content-Security-Policy"
if ([string]::IsNullOrWhiteSpace($csp) -or (-not $csp.Contains("default-src"))) {
    throw "[security-smoke] Missing/invalid Content-Security-Policy header: '$csp'"
}

$hsts = Get-HeaderValue -Headers $headersResponse.Headers -Name "Strict-Transport-Security"
if ([string]::IsNullOrWhiteSpace($hsts) -or (-not $hsts.StartsWith("max-age="))) {
    throw "[security-smoke] Missing/invalid Strict-Transport-Security header: '$hsts'"
}

Write-Host "[security-smoke] PASS security headers probe: status=$($headersResponse.StatusCode)"
Write-Host "[security-smoke] SUCCESS"
