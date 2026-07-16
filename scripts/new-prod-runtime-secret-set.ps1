param(
    [string]$OutputPath = "",
    [int]$Bytes = 48,
    [switch]$IncludePostgresPassword,
    [switch]$IncludeRtdnSecret,
    [switch]$ShowValues
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($Bytes -lt 32) {
    throw "[secret-generator] Bytes must be >= 32 for production runtime secrets."
}

function New-SecretValue {
    param([int]$LengthBytes)

    $bytes = [byte[]]::new($LengthBytes)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    return [Convert]::ToBase64String($bytes).TrimEnd("=") -replace "\+", "-" -replace "/", "_"
}

$entries = [ordered]@{
    "APP_SECURITY_JWT_SECRET" = New-SecretValue -LengthBytes $Bytes
    "SPRING_DATA_REDIS_PASSWORD" = New-SecretValue -LengthBytes $Bytes
    "REDIS_PASSWORD" = $null
    "SPRING_DATA_REDIS_SECURITY_PASSWORD" = New-SecretValue -LengthBytes $Bytes
    "REDIS_SECURITY_PASSWORD" = $null
}

$entries["REDIS_PASSWORD"] = $entries["SPRING_DATA_REDIS_PASSWORD"]
$entries["REDIS_SECURITY_PASSWORD"] = $entries["SPRING_DATA_REDIS_SECURITY_PASSWORD"]

if ($IncludePostgresPassword) {
    $entries["POSTGRES_PASSWORD"] = New-SecretValue -LengthBytes $Bytes
    $entries["SPRING_DATASOURCE_PASSWORD"] = $entries["POSTGRES_PASSWORD"]
}

if ($IncludeRtdnSecret) {
    $entries["APP_SUBSCRIPTION_GOOGLE_PLAY_RTDN_SHARED_SECRET"] = New-SecretValue -LengthBytes $Bytes
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Generated runtime secret set. Do not commit.") | Out-Null
$lines.Add("# Generated at UTC: $((Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ"))") | Out-Null

foreach ($key in $entries.Keys) {
    $lines.Add("$key=$($entries[$key])") | Out-Null
}

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $resolvedParent = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($resolvedParent) -and -not (Test-Path -LiteralPath $resolvedParent -PathType Container)) {
        New-Item -ItemType Directory -Path $resolvedParent | Out-Null
    }
    Set-Content -LiteralPath $OutputPath -Value $lines -Encoding UTF8NoBOM
    Write-Host "[secret-generator] Wrote secret set to: $OutputPath"
    Write-Host "[secret-generator] Do not commit or paste this file into chat."
}

Write-Host "[secret-generator] Generated keys:"
foreach ($key in $entries.Keys) {
    if ($ShowValues) {
        Write-Host ("{0}={1}" -f $key, $entries[$key])
    } else {
        Write-Host ("{0}=<generated length={1}>" -f $key, $entries[$key].Length)
    }
}

if ([string]::IsNullOrWhiteSpace($OutputPath) -and -not $ShowValues) {
    Write-Host "[secret-generator] Values hidden. Pass -OutputPath <path> to write them to a local secret file."
}
