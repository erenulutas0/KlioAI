param(
    [string]$ProjectName = "flutter-project-main",
    [string]$BackendService = "backend"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$thisScriptPath = (Resolve-Path $PSCommandPath).Path

function Resolve-BackendContainer {
    param(
        [string]$ComposeProject,
        [string]$ServiceName
    )

    $containerIdRaw = & docker compose -p $ComposeProject ps -q $ServiceName 2>$null | Select-Object -First 1
    $containerId = [string]$containerIdRaw
    if (-not [string]::IsNullOrWhiteSpace($containerId)) {
        return $containerId.Trim()
    }

    $containerNameRaw = & docker ps --filter "label=com.docker.compose.project=$ComposeProject" --filter "label=com.docker.compose.service=$ServiceName" --format "{{.Names}}" 2>$null | Select-Object -First 1
    $containerName = [string]$containerNameRaw
    if (-not [string]::IsNullOrWhiteSpace($containerName)) {
        return $containerName.Trim()
    }

    throw "[runtime-prod-flags] Backend container not found for project '$ComposeProject' service '$ServiceName'."
}

function Read-EnvMap {
    param([string]$ContainerRef)

    $lines = & docker inspect $ContainerRef --format "{{range .Config.Env}}{{println .}}{{end}}"
    if ($LASTEXITCODE -ne 0) {
        throw "[runtime-prod-flags] Failed to read environment from container '$ContainerRef'."
    }

    $map = @{}
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        $idx = $line.IndexOf("=")
        if ($idx -lt 1) {
            continue
        }
        $key = $line.Substring(0, $idx)
        $value = $line.Substring($idx + 1)
        $map[$key] = $value
    }
    return $map
}

function Get-ValueOrEmpty {
    param(
        [hashtable]$Map,
        [string]$Key
    )

    if ($Map.ContainsKey($Key)) {
        return [string]$Map[$Key]
    }
    return ""
}

$containerRef = Resolve-BackendContainer -ComposeProject $ProjectName -ServiceName $BackendService
$envMap = Read-EnvMap -ContainerRef $containerRef

$errors = @()

$jwtEnforce = Get-ValueOrEmpty -Map $envMap -Key "APP_SECURITY_JWT_ENFORCE_AUTH"
if ($jwtEnforce.Trim().ToLowerInvariant() -ne "true") {
    $errors += "APP_SECURITY_JWT_ENFORCE_AUTH must be true (actual='$jwtEnforce')."
}

$mockVerification = Get-ValueOrEmpty -Map $envMap -Key "APP_SUBSCRIPTION_MOCK_VERIFICATION_ENABLED"
if ($mockVerification.Trim().ToLowerInvariant() -ne "false") {
    $errors += "APP_SUBSCRIPTION_MOCK_VERIFICATION_ENABLED must be false (actual='$mockVerification')."
}

$groqApiKey = Get-ValueOrEmpty -Map $envMap -Key "GROQ_API_KEY"
if ([string]::IsNullOrWhiteSpace($groqApiKey)) {
    $errors += "GROQ_API_KEY must be set (actual is empty)."
}

$jwtSecret = Get-ValueOrEmpty -Map $envMap -Key "APP_SECURITY_JWT_SECRET"
$weakSecrets = @("dummy", "change-me", "changeme", "dev-secret", "test", "password")
$jwtSecretNormalized = $jwtSecret.Trim().ToLowerInvariant()
if ([string]::IsNullOrWhiteSpace($jwtSecret)) {
    $errors += "APP_SECURITY_JWT_SECRET must be set (actual is empty)."
} elseif ($weakSecrets -contains $jwtSecretNormalized) {
    $errors += "APP_SECURITY_JWT_SECRET uses a placeholder/weak value ('$jwtSecret')."
}

$subscriptionPagePath = Join-Path $repoRoot "flutter_vocabmaster/lib/screens/subscription_page.dart"
if (-not (Test-Path $subscriptionPagePath)) {
    $errors += "Subscription page not found at '$subscriptionPagePath'."
} else {
    $subscriptionPageContent = Get-Content -Path $subscriptionPagePath -Raw
    if ($subscriptionPageContent -notmatch "SUBSCRIPTION_DEMO_MODE'\s*,\s*defaultValue:\s*false") {
        $errors += "Subscription demo flag default must be false in subscription_page.dart."
    }
    if ($subscriptionPageContent -match "\bDEMO_MODE\b\s*=\s*true") {
        $errors += "Found legacy hardcoded DEMO_MODE=true in subscription_page.dart."
    }
    if ($subscriptionPageContent -match "SUBSCRIPTION_DEMO_MODE'\s*,\s*defaultValue:\s*true") {
        $errors += "SUBSCRIPTION_DEMO_MODE default must not be true."
    }
}

$guardPaths = @()
$workflowDir = Join-Path $repoRoot ".github/workflows"
if (Test-Path $workflowDir) {
    $guardPaths += (Get-ChildItem -Path $workflowDir -Recurse -File -Include *.yml,*.yaml)
}
$guardPaths += (Get-ChildItem -Path $PSScriptRoot -Recurse -File -Include *.ps1 | Where-Object {
    (Resolve-Path $_.FullName).Path -ne $thisScriptPath
})

foreach ($pathItem in $guardPaths) {
    $content = Get-Content -Path $pathItem.FullName -Raw
    if ($content -match "--dart-define=SUBSCRIPTION_DEMO_MODE=true" -or $content -match "SUBSCRIPTION_DEMO_MODE\s*=\s*true") {
        $errors += "Release guard violation: '$($pathItem.FullName)' contains SUBSCRIPTION_DEMO_MODE=true."
    }
}

if ($errors.Count -gt 0) {
    Write-Host "[runtime-prod-flags] FAIL: production runtime guards not satisfied."
    foreach ($errorItem in $errors) {
        Write-Host "[runtime-prod-flags] - $errorItem"
    }
    exit 1
}

$groqLength = $groqApiKey.Length
$secretLength = $jwtSecret.Length
Write-Host "[runtime-prod-flags] PASS: runtime production guardrails satisfied."
Write-Host "[runtime-prod-flags] INFO: container=$containerRef groq_api_key_len=$groqLength jwt_secret_len=$secretLength"
