param(
    [string]$BackendBaseUrl = "http://localhost:8082",
    [Parameter(Mandatory = $true)][long]$UserId,
    [Parameter(Mandatory = $true)][string]$PurchaseToken,
    [string]$ProductId = "pro_monthly_subscription",
    [string]$PackageName = "",
    [string]$AccessToken = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Mask-Secret {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }
    if ($Value.Length -le 8) {
        return "****"
    }
    return "$($Value.Substring(0, 4))...$($Value.Substring($Value.Length - 4))"
}

if ([string]::IsNullOrWhiteSpace($PackageName)) {
    $PackageName = $env:APP_SUBSCRIPTION_GOOGLE_PLAY_PACKAGE_NAME
}

if ([string]::IsNullOrWhiteSpace($PackageName)) {
    throw "PackageName is required. Pass -PackageName or set APP_SUBSCRIPTION_GOOGLE_PLAY_PACKAGE_NAME."
}

$uri = "$($BackendBaseUrl.TrimEnd('/'))/api/subscription/verify/google"
$headers = @{
    "X-User-Id" = "$UserId"
    "Content-Type" = "application/json"
}
if (-not [string]::IsNullOrWhiteSpace($AccessToken)) {
    $headers["Authorization"] = "Bearer $AccessToken"
}

$body = @{
    purchaseToken = $PurchaseToken
    productId = $ProductId
    packageName = $PackageName
} | ConvertTo-Json -Depth 4

Write-Host "[google-live-smoke] POST $uri"
Write-Host "[google-live-smoke] UserId=$UserId ProductId=$ProductId PackageName=$PackageName PurchaseToken=$(Mask-Secret $PurchaseToken)"

try {
    $response = Invoke-WebRequest -Uri $uri -Method POST -Headers $headers -Body $body -UseBasicParsing -SkipHttpErrorCheck
    $statusCode = [int]$response.StatusCode
    $parsed = $null
    try {
        $parsed = $response.Content | ConvertFrom-Json
    } catch {
        $parsed = $response.Content
    }
    Write-Host "[google-live-smoke] HTTP $statusCode"
    if ($parsed -is [string]) {
        Write-Output $parsed
    } else {
        $parsed | ConvertTo-Json -Depth 8
    }
    if ($statusCode -ge 200 -and $statusCode -lt 300) {
        exit 0
    }
    exit 1
} catch {
    Write-Host "[google-live-smoke] FAILED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
