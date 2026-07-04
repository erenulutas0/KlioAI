param(
    [string]$Repository = "",
    [string]$Token = "",
    [string]$FlutterProjectDir = "flutter_vocabmaster",
    [string]$KeyPropertiesPath = "",
    [string]$KeystorePath = "",
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

function Read-PropertiesFile {
    param([string]$Path)

    $map = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#")) {
            continue
        }

        $idx = $trimmed.IndexOf("=")
        if ($idx -le 0) {
            continue
        }

        $key = $trimmed.Substring(0, $idx).Trim()
        $value = $trimmed.Substring($idx + 1).Trim()
        $map[$key] = $value
    }
    return $map
}

function Resolve-RepoPath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }
    return (Join-Path (Get-Location) $Path)
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
        Write-Host "[github-secrets] Installing temporary libsodium-wrappers dependency under $Path."
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

$flutterDir = Resolve-RepoPath $FlutterProjectDir
if (-not (Test-Path -LiteralPath $flutterDir -PathType Container)) {
    throw "Flutter project directory not found: $flutterDir"
}

if ([string]::IsNullOrWhiteSpace($KeyPropertiesPath)) {
    $KeyPropertiesPath = Join-Path $flutterDir "android\key.properties"
} else {
    $KeyPropertiesPath = Resolve-RepoPath $KeyPropertiesPath
}
if (-not (Test-Path -LiteralPath $KeyPropertiesPath -PathType Leaf)) {
    throw "Android key.properties not found: $KeyPropertiesPath"
}

$props = Read-PropertiesFile -Path $KeyPropertiesPath
foreach ($requiredKey in @("storePassword", "keyPassword", "keyAlias", "storeFile")) {
    if (-not $props.ContainsKey($requiredKey) -or [string]::IsNullOrWhiteSpace($props[$requiredKey])) {
        throw "key.properties is missing '$requiredKey'."
    }
}

if ([string]::IsNullOrWhiteSpace($KeystorePath)) {
    $candidateFromApp = Join-Path (Join-Path $flutterDir "android\app") $props["storeFile"]
    $candidateFromAndroid = Join-Path (Join-Path $flutterDir "android") $props["storeFile"]
    if (Test-Path -LiteralPath $candidateFromApp -PathType Leaf) {
        $KeystorePath = $candidateFromApp
    } elseif (Test-Path -LiteralPath $candidateFromAndroid -PathType Leaf) {
        $KeystorePath = $candidateFromAndroid
    } else {
        throw "Could not find keystore referenced by key.properties storeFile='$($props["storeFile"])'."
    }
} else {
    $KeystorePath = Resolve-RepoPath $KeystorePath
}
if (-not (Test-Path -LiteralPath $KeystorePath -PathType Leaf)) {
    throw "Keystore not found: $KeystorePath"
}

$keystoreBase64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($KeystorePath))
$secrets = [ordered]@{
    ANDROID_KEYSTORE_BASE64  = $keystoreBase64
    ANDROID_KEYSTORE_PASSWORD = $props["storePassword"]
    ANDROID_KEY_PASSWORD      = $props["keyPassword"]
    ANDROID_KEY_ALIAS         = $props["keyAlias"]
}

Write-Host "[github-secrets] Repository: $Repository"
Write-Host "[github-secrets] Key properties: $KeyPropertiesPath"
Write-Host "[github-secrets] Keystore: $KeystorePath"
Write-Host "[github-secrets] Secrets to configure:"
foreach ($name in $secrets.Keys) {
    Write-Host ("  - {0} (length={1})" -f $name, $secrets[$name].Length)
}

if (-not $Execute) {
    Write-Host "[github-secrets] DRY RUN only. Re-run with -Execute and a repo-admin GITHUB_TOKEN/GH_TOKEN to upload secrets."
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
    $SodiumWorkDir = Join-Path $env:TEMP "klioai-github-secrets-libsodium"
}

$headers = @{
    Accept                 = "application/vnd.github+json"
    Authorization          = "Bearer $Token"
    "X-GitHub-Api-Version" = "2022-11-28"
}

$publicKeyUrl = "https://api.github.com/repos/$Repository/actions/secrets/public-key"
$publicKey = Invoke-GitHubApi -Method Get -Uri $publicKeyUrl -Headers $headers
$encryptScript = Initialize-SodiumWorkDir -Path $SodiumWorkDir

foreach ($name in $secrets.Keys) {
    Write-Host "[github-secrets] Uploading $name."
    $encryptedValue = Protect-GitHubSecretValue -EncryptScript $encryptScript -WorkDir $SodiumWorkDir -PublicKey $publicKey.key -Value $secrets[$name]
    $secretUrl = "https://api.github.com/repos/$Repository/actions/secrets/$name"
    Invoke-GitHubApi -Method Put -Uri $secretUrl -Headers $headers -Body @{
        encrypted_value = $encryptedValue
        key_id          = $publicKey.key_id
    } | Out-Null
}

Write-Host "[github-secrets] SUCCESS Android signing secrets uploaded."
