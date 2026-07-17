param(
    [string]$BaseUrl = "https://api.klioai.app",
    [Parameter(Mandatory = $true)][string]$AccessToken,
    [long]$UserId = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Decode-JwtUserId {
    param([string]$Token)
    try {
        $parts = $Token.Split(".")
        if ($parts.Length -lt 2) {
            return 0
        }
        $payload = $parts[1].Replace("-", "+").Replace("_", "/")
        switch ($payload.Length % 4) {
            2 { $payload += "==" }
            3 { $payload += "=" }
        }
        $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload))
        $claims = $json | ConvertFrom-Json
        foreach ($name in @("userId", "uid", "sub", "id")) {
            if ($null -ne $claims.$name) {
                $parsed = 0L
                if ([long]::TryParse([string]$claims.$name, [ref]$parsed)) {
                    return $parsed
                }
            }
        }
    } catch {
        return 0
    }
    return 0
}

function Invoke-DiagnosticGet {
    param(
        [string]$Uri,
        [hashtable]$Headers
    )

    $response = Invoke-WebRequest `
        -Uri $Uri `
        -Method GET `
        -Headers $Headers `
        -UseBasicParsing `
        -SkipHttpErrorCheck `
        -TimeoutSec 30

    $parsed = $null
    try {
        $parsed = $response.Content | ConvertFrom-Json
    } catch {
        $parsed = $response.Content
    }

    [PSCustomObject]@{
        StatusCode = [int]$response.StatusCode
        Body       = $parsed
    }
}

if ($UserId -le 0) {
    $UserId = Decode-JwtUserId -Token $AccessToken
}

if ($UserId -le 0) {
    throw "UserId could not be resolved. Pass -UserId explicitly."
}

$root = $BaseUrl.TrimEnd("/")
$headers = @{
    "Authorization" = "Bearer $AccessToken"
    "X-User-Id"     = "$UserId"
    "Content-Type"  = "application/json"
}

Write-Host "[entitlement-diagnostic] BaseUrl=$root UserId=$UserId"

$quota = Invoke-DiagnosticGet -Uri "$root/api/chatbot/quota/status" -Headers $headers
Write-Host "[entitlement-diagnostic] quota/status HTTP $($quota.StatusCode)"
$quota.Body | ConvertTo-Json -Depth 8

$subscription = Invoke-DiagnosticGet -Uri "$root/api/users/$UserId/subscription/status" -Headers $headers
Write-Host "[entitlement-diagnostic] subscription/status HTTP $($subscription.StatusCode)"
$subscription.Body | ConvertTo-Json -Depth 8
