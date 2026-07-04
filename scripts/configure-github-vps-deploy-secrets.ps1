param(
    [string]$Repository = "",
    [string]$EnvironmentName = "production-backend",
    [string]$VpsHost = "84.46.251.95",
    [string]$VpsUser = "root",
    [string]$VpsPort = "22",
    [string]$PrivateKeyPath = "",
    [string]$Token = "",
    [string]$SodiumWorkDir = "",
    [switch]$Execute
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-RepositoryFromOrigin {
    $remote = git remote get-url origin 2>$null
    if (-not $remote) {
        throw "Could not infer repository because git remote 'origin' is not configured. Pass -Repository owner/repo."
    }

    if ($remote -match "github\.com[:/]([^/]+)/([^/.]+)(?:\.git)?$") {
        return "$($Matches[1])/$($Matches[2])"
    }

    throw "Could not infer GitHub owner/repo from origin '$remote'. Pass -Repository owner/repo."
}

function Invoke-GitHubApi {
    param(
        [string]$Method,
        [string]$Uri,
        [hashtable]$Headers,
        [object]$Body = $null
    )

    if ($null -eq $Body) {
        return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers
    }

    $jsonBody = $Body | ConvertTo-Json -Depth 10
    return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -ContentType "application/json" -Body $jsonBody
}

function Initialize-SodiumWorkDir {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }

    $packageJson = Join-Path $Path "package.json"
    if (-not (Test-Path -LiteralPath $packageJson -PathType Leaf)) {
        Push-Location $Path
        try {
            npm init -y --silent | Out-Null
        } finally {
            Pop-Location
        }
    }

    $modulePath = Join-Path $Path "node_modules\libsodium-wrappers"
    if (-not (Test-Path -LiteralPath $modulePath -PathType Container)) {
        Write-Host "[vps-secrets] Installing temporary libsodium-wrappers dependency under $Path."
        Push-Location $Path
        try {
            npm install libsodium-wrappers@0.8.4 --silent | Out-Null
        } finally {
            Pop-Location
        }
    }

    $encryptScript = Join-Path $Path "encrypt-secret.js"
    if (-not (Test-Path -LiteralPath $encryptScript -PathType Leaf)) {
        @'
const fs = require("fs");
const sodium = require("libsodium-wrappers");

(async () => {
  await sodium.ready;
  const input = JSON.parse(fs.readFileSync(0, "utf8"));
  const publicKey = Buffer.from(input.publicKey, "base64");
  const secretValue = Buffer.from(input.value, "utf8");
  const encrypted = sodium.crypto_box_seal(secretValue, publicKey);
  process.stdout.write(Buffer.from(encrypted).toString("base64"));
})().catch((err) => {
  console.error(err && err.stack ? err.stack : String(err));
  process.exit(1);
});
'@ | Set-Content -LiteralPath $encryptScript -Encoding UTF8NoBOM
    }

    return $encryptScript
}

function Protect-GitHubSecretValue {
    param(
        [string]$EncryptScript,
        [string]$WorkDir,
        [string]$PublicKey,
        [string]$Value
    )

    $inputObject = @{
        publicKey = $PublicKey
        value     = $Value
    }
    $inputJson = $inputObject | ConvertTo-Json -Compress

    Push-Location $WorkDir
    try {
        $encrypted = $inputJson | node $EncryptScript
    } finally {
        Pop-Location
    }

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($encrypted)) {
        throw "Failed to encrypt GitHub secret value."
    }
    return $encrypted.Trim()
}

if ([string]::IsNullOrWhiteSpace($Repository)) {
    $Repository = Get-RepositoryFromOrigin
}
if ($Repository -notmatch "^[^/]+/[^/]+$") {
    throw "Repository must be in owner/repo format. Received '$Repository'."
}
if ([string]::IsNullOrWhiteSpace($PrivateKeyPath)) {
    throw "PrivateKeyPath is required. Pass a deploy-only SSH private key path; do not use a personal interactive key if you can avoid it."
}

$privateKey = Get-Content -LiteralPath $PrivateKeyPath -Raw
if ([string]::IsNullOrWhiteSpace($privateKey)) {
    throw "Private key file is empty: $PrivateKeyPath"
}

$secrets = [ordered]@{
    VPS_SSH_HOST        = $VpsHost
    VPS_SSH_USER        = $VpsUser
    VPS_SSH_PORT        = $VpsPort
    VPS_SSH_PRIVATE_KEY = $privateKey
}

Write-Host "[vps-secrets] Repository: $Repository"
Write-Host "[vps-secrets] Environment: $EnvironmentName"
Write-Host "[vps-secrets] Private key path: $PrivateKeyPath"
Write-Host "[vps-secrets] Secrets to configure:"
foreach ($name in $secrets.Keys) {
    Write-Host ("  - {0} (length={1})" -f $name, $secrets[$name].Length)
}

if (-not $Execute) {
    Write-Host "[vps-secrets] DRY RUN only. Re-run with -Execute and a repo-admin GITHUB_TOKEN/GH_TOKEN to upload environment secrets."
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Token)) {
    $Token = $env:GITHUB_TOKEN
}
if ([string]::IsNullOrWhiteSpace($Token)) {
    $Token = $env:GH_TOKEN
}
if ([string]::IsNullOrWhiteSpace($Token)) {
    throw "A GitHub token is required for -Execute. Set GITHUB_TOKEN or GH_TOKEN, or pass -Token."
}

if ([string]::IsNullOrWhiteSpace($SodiumWorkDir)) {
    $SodiumWorkDir = Join-Path $env:TEMP "klioai-github-environment-secrets-libsodium"
}

$headers = @{
    Accept                 = "application/vnd.github+json"
    Authorization          = "Bearer $Token"
    "X-GitHub-Api-Version" = "2022-11-28"
}

$encodedEnvironment = [System.Uri]::EscapeDataString($EnvironmentName)
$publicKeyUrl = "https://api.github.com/repos/$Repository/environments/$encodedEnvironment/secrets/public-key"
$publicKey = Invoke-GitHubApi -Method Get -Uri $publicKeyUrl -Headers $headers
$encryptScript = Initialize-SodiumWorkDir -Path $SodiumWorkDir

foreach ($name in $secrets.Keys) {
    Write-Host "[vps-secrets] Uploading $name."
    $encryptedValue = Protect-GitHubSecretValue -EncryptScript $encryptScript -WorkDir $SodiumWorkDir -PublicKey $publicKey.key -Value $secrets[$name]
    $secretUrl = "https://api.github.com/repos/$Repository/environments/$encodedEnvironment/secrets/$name"
    Invoke-GitHubApi -Method Put -Uri $secretUrl -Headers $headers -Body @{
        encrypted_value = $encryptedValue
        key_id          = $publicKey.key_id
    } | Out-Null
}

Write-Host "[vps-secrets] SUCCESS VPS deploy environment secrets uploaded."

