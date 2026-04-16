param(
    [string]$FlutterDir = "",
    [string]$GoogleServicesPath = "",
    [string]$KeyPropertiesPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if ([string]::IsNullOrWhiteSpace($FlutterDir)) {
    $FlutterDir = Join-Path $repoRoot "flutter_vocabmaster"
}
if ([string]::IsNullOrWhiteSpace($GoogleServicesPath)) {
    $GoogleServicesPath = Join-Path $FlutterDir "android\app\google-services.json"
}
if ([string]::IsNullOrWhiteSpace($KeyPropertiesPath)) {
    $KeyPropertiesPath = Join-Path $FlutterDir "android\key.properties"
}

function Read-KeyValueFile {
    param([string]$Path)

    $map = @{}
    foreach ($line in Get-Content -Path $Path) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $trimmed = $line.Trim()
        if ($trimmed.StartsWith("#")) {
            continue
        }

        $separatorIndex = $trimmed.IndexOf("=")
        if ($separatorIndex -lt 1) {
            continue
        }

        $key = $trimmed.Substring(0, $separatorIndex).Trim()
        $value = $trimmed.Substring($separatorIndex + 1).Trim()
        if (-not [string]::IsNullOrWhiteSpace($key)) {
            $map[$key] = $value
        }
    }

    return $map
}

function Get-KeytoolPath {
    $command = Get-Command keytool.exe -ErrorAction SilentlyContinue
    if ($command -and -not [string]::IsNullOrWhiteSpace($command.Source)) {
        return $command.Source
    }

    if (-not [string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
        $javaHomeCandidate = Join-Path $env:JAVA_HOME "bin\keytool.exe"
        if (Test-Path $javaHomeCandidate) {
            return $javaHomeCandidate
        }
    }

    $knownCandidates = @(
        "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe",
        "C:\Program Files\Java\jdk-22\bin\keytool.exe",
        "C:\Program Files\Java\jdk-21\bin\keytool.exe",
        "C:\Program Files\Java\jdk-17\bin\keytool.exe"
    )

    foreach ($candidate in $knownCandidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    $javaRoot = "C:\Program Files\Java"
    if (Test-Path $javaRoot) {
        $discovered = Get-ChildItem -Path $javaRoot -Recurse -Filter keytool.exe -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($discovered) {
            return $discovered.FullName
        }
    }

    throw "[google-signin-check] keytool.exe not found. Install JDK or set JAVA_HOME."
}

function Resolve-KeystorePath {
    param(
        [string]$StoreFile,
        [string]$KeyPropertiesFilePath,
        [string]$FlutterProjectDir
    )

    if ([string]::IsNullOrWhiteSpace($StoreFile)) {
        throw "[google-signin-check] key.properties is missing 'storeFile'."
    }

    if (Test-Path $StoreFile) {
        return (Resolve-Path $StoreFile).Path
    }

    $androidDir = Join-Path $FlutterProjectDir "android"
    $appDir = Join-Path $androidDir "app"
    $keyPropsDir = Split-Path -Parent $KeyPropertiesFilePath
    $candidates = @(
        (Join-Path $keyPropsDir $StoreFile),
        (Join-Path $androidDir $StoreFile),
        (Join-Path $appDir $StoreFile)
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return (Resolve-Path $candidate).Path
        }
    }

    throw "[google-signin-check] Keystore file '$StoreFile' not found relative to android/app or key.properties."
}

function Normalize-Fingerprint {
    param([string]$Value)

    return (($Value -replace "[:\s]", "").Trim().ToLowerInvariant())
}

function Format-Fingerprint {
    param([string]$NormalizedValue)

    if ([string]::IsNullOrWhiteSpace($NormalizedValue)) {
        return ""
    }

    $upper = $NormalizedValue.ToUpperInvariant()
    $pairs = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $upper.Length; $i += 2) {
        $length = [Math]::Min(2, $upper.Length - $i)
        $pairs.Add($upper.Substring($i, $length))
    }

    return ($pairs -join ":")
}

if (-not (Test-Path $GoogleServicesPath)) {
    throw "[google-signin-check] google-services.json not found at '$GoogleServicesPath'."
}
if (-not (Test-Path $KeyPropertiesPath)) {
    throw "[google-signin-check] key.properties not found at '$KeyPropertiesPath'."
}

$googleServices = Get-Content -Path $GoogleServicesPath -Raw | ConvertFrom-Json
$packageNames = New-Object System.Collections.Generic.List[string]
$certificateHashes = New-Object System.Collections.Generic.List[string]

foreach ($client in @($googleServices.client)) {
    $androidClientInfo = $client.client_info.android_client_info
    if ($androidClientInfo -and -not [string]::IsNullOrWhiteSpace([string]$androidClientInfo.package_name)) {
        $packageNames.Add([string]$androidClientInfo.package_name)
    }

    foreach ($oauthClient in @($client.oauth_client)) {
        if ([string]$oauthClient.client_type -ne "1") {
            continue
        }

        $androidInfo = $oauthClient.android_info
        if (-not $androidInfo) {
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$androidInfo.package_name)) {
            $packageNames.Add([string]$androidInfo.package_name)
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$androidInfo.certificate_hash)) {
            $certificateHashes.Add([string]$androidInfo.certificate_hash)
        }
    }
}

$normalizedGoogleHashes = @($certificateHashes | ForEach-Object { Normalize-Fingerprint $_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
if ($normalizedGoogleHashes.Count -eq 0) {
    throw "[google-signin-check] No Android OAuth certificate hashes found in google-services.json."
}

$keyProperties = Read-KeyValueFile -Path $KeyPropertiesPath
foreach ($requiredKey in @("storeFile", "storePassword", "keyAlias", "keyPassword")) {
    if (-not $keyProperties.ContainsKey($requiredKey) -or [string]::IsNullOrWhiteSpace([string]$keyProperties[$requiredKey])) {
        throw "[google-signin-check] key.properties is missing '$requiredKey'."
    }
}

$keystorePath = Resolve-KeystorePath -StoreFile $keyProperties["storeFile"] -KeyPropertiesFilePath $KeyPropertiesPath -FlutterProjectDir $FlutterDir
$keytoolPath = Get-KeytoolPath
$keytoolOutput = & $keytoolPath -list -v -keystore $keystorePath -alias $keyProperties["keyAlias"] -storepass $keyProperties["storePassword"] -keypass $keyProperties["keyPassword"]
if ($LASTEXITCODE -ne 0) {
    throw "[google-signin-check] keytool failed to read keystore '$keystorePath'."
}

$keytoolText = $keytoolOutput -join "`n"
$sha1Match = [regex]::Match($keytoolText, "SHA1:\s*([A-F0-9:]+)", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$sha256Match = [regex]::Match($keytoolText, "SHA256:\s*([A-F0-9:]+)", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
if (-not $sha1Match.Success) {
    throw "[google-signin-check] Could not parse SHA1 fingerprint from keystore output."
}

$localSha1 = Normalize-Fingerprint $sha1Match.Groups[1].Value
$localSha256 = if ($sha256Match.Success) { Normalize-Fingerprint $sha256Match.Groups[1].Value } else { "" }
$packageList = @($packageNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
$matchingHash = $normalizedGoogleHashes -contains $localSha1

if (-not $matchingHash) {
    Write-Host "[google-signin-check] FAIL: release upload keystore SHA-1 is not present in google-services.json Android OAuth clients."
    Write-Host "[google-signin-check] package=$($packageList -join ',')"
    Write-Host "[google-signin-check] local_upload_sha1=$(Format-Fingerprint $localSha1)"
    if (-not [string]::IsNullOrWhiteSpace($localSha256)) {
        Write-Host "[google-signin-check] local_upload_sha256=$(Format-Fingerprint $localSha256)"
    }
    foreach ($hash in $normalizedGoogleHashes) {
        Write-Host "[google-signin-check] google_services_sha1=$(Format-Fingerprint $hash)"
    }
    Write-Host "[google-signin-check] NEXT: add the current upload-key SHA-1/SHA-256 and Google Play App Signing SHA-1/SHA-256 to Firebase + Google Cloud OAuth, then download a refreshed google-services.json and rebuild the Play test artifact."
    exit 1
}

Write-Host "[google-signin-check] PASS: upload keystore SHA-1 exists in google-services.json."
Write-Host "[google-signin-check] package=$($packageList -join ',')"
Write-Host "[google-signin-check] local_upload_sha1=$(Format-Fingerprint $localSha1)"
if (-not [string]::IsNullOrWhiteSpace($localSha256)) {
    Write-Host "[google-signin-check] local_upload_sha256=$(Format-Fingerprint $localSha256)"
}
Write-Host "[google-signin-check] NOTE: Play-distributed builds also require Google Play App Signing fingerprints to be registered in Firebase + Google Cloud OAuth."
