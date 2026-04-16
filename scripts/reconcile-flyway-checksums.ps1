param(
    [string]$ProjectName = "flutter-project-main",
    [string[]]$ComposeFiles = @("docker-compose.yml"),
    [string]$PostgresService = "postgres",
    [string]$Database = "EnglishApp",
    [string]$DbUser = "postgres",
    [string]$DbPassword = "postgres",
    [string]$NetworkName = "",
    [string]$FlywayImage = "flyway/flyway",
    [string]$FlywayPluginVersion = "12.0.0",
    [switch]$AcknowledgeNonProd
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($env:APP_SECURITY_JWT_SECRET)) {
    $env:APP_SECURITY_JWT_SECRET = "local-dev-placeholder"
    Write-Host "[flyway-repair] INFO: APP_SECURITY_JWT_SECRET not set; using temporary placeholder for compose parsing."
}

if (-not $AcknowledgeNonProd) {
    throw "This operation is for NON-PRODUCTION environments only. Re-run with -AcknowledgeNonProd."
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$backendDir = Join-Path $repoRoot "backend"
$migrationDir = Join-Path $backendDir "src/main/resources/db/migration"

if (-not (Test-Path $migrationDir)) {
    throw "Migration directory not found: $migrationDir"
}

$resolvedComposeFiles = $ComposeFiles
if ($resolvedComposeFiles.Count -eq 1 -and $resolvedComposeFiles[0] -match ",") {
    $resolvedComposeFiles = @(
        $resolvedComposeFiles[0].Split(",") |
            ForEach-Object { $_.Trim(" `"'") } |
            Where-Object { $_ -ne "" }
    )
}

$composeFilePaths = @()
foreach ($composeFile in $resolvedComposeFiles) {
    $fullPath = if ([System.IO.Path]::IsPathRooted($composeFile)) { $composeFile } else { Join-Path $repoRoot $composeFile }
    if (-not (Test-Path $fullPath)) {
        throw "Compose file not found: $fullPath"
    }
    $composeFilePaths += $fullPath
}

function Invoke-Compose {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

    $composeArgs = @("compose", "-p", $ProjectName)
    foreach ($path in $composeFilePaths) {
        $composeArgs += @("-f", $path)
    }
    $composeArgs += $Args

    & docker @composeArgs
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose failed: $($Args -join ' ')"
    }
}

function Invoke-PostgresScalar {
    param([string]$Sql)

    $output = Invoke-Compose @(
        "exec", "-T", $PostgresService,
        "psql", "-U", $DbUser, "-d", $Database,
        "-t", "-A", "-c", $Sql
    )

    $lines = @($output | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ -ne "" })
    if ($lines.Count -eq 0) {
        return ""
    }
    return $lines[-1]
}

function Resolve-DockerNetwork {
    $postgresContainerId = Invoke-Compose @("ps", "-q", $PostgresService) | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($postgresContainerId)) {
        throw "Could not resolve container id for service '$PostgresService'."
    }

    if (-not [string]::IsNullOrWhiteSpace($NetworkName)) {
        return $NetworkName
    }

    $networkLines = & docker inspect --format "{{range `$k, `$v := .NetworkSettings.Networks}}{{println `$k}}{{end}}" $postgresContainerId
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to inspect container networks for $postgresContainerId"
    }

    $networks = @(
        $networkLines |
            ForEach-Object { $_.ToString().Trim() } |
            Where-Object { $_ -ne "" }
    )

    if ($networks.Count -eq 0) {
        throw "No docker networks found for postgres container $postgresContainerId"
    }

    $projectMatch = @($networks | Where-Object { $_ -like "$ProjectName*" })
    if ($projectMatch.Count -gt 0) {
        return $projectMatch[0]
    }

    return $networks[0]
}

Write-Host "[flyway-repair] Verifying running stack (project=$ProjectName)..."
$null = Invoke-Compose @("ps")

$resolvedNetwork = Resolve-DockerNetwork
Write-Host "[flyway-repair] Resolved docker network: $resolvedNetwork"

$currentV1Checksum = Invoke-PostgresScalar @"
SELECT COALESCE(checksum::text, 'NULL')
FROM flyway_schema_history
WHERE version ~ '^[0-9]+$' AND version::int = 1 AND success = true
ORDER BY installed_rank DESC
LIMIT 1;
"@

$baselineVersion = Invoke-PostgresScalar @"
SELECT version
FROM flyway_schema_history
WHERE type = 'BASELINE'
ORDER BY installed_rank DESC
LIMIT 1;
"@

if ([string]::IsNullOrWhiteSpace($currentV1Checksum)) {
    if ($baselineVersion -match '^\d+$' -and [int]$baselineVersion -ge 1) {
        Write-Host "[flyway-repair] No version=1 row found. Baseline version is $baselineVersion (expected for baselined environments)."
    } else {
        Write-Warning "[flyway-repair] No applied version=1 row found in flyway_schema_history."
    }
} else {
    Write-Host "[flyway-repair] Current V001 checksum: $currentV1Checksum"
}

$migrationMount = ($migrationDir -replace "\\", "/")
$flywayTag = "${FlywayImage}:$FlywayPluginVersion"
$flywayArgs = @(
    "run",
    "--rm",
    "--network",
    $resolvedNetwork,
    "-v",
    "${migrationMount}:/flyway/sql:ro",
    $flywayTag,
    "-url=jdbc:postgresql://${PostgresService}:5432/$Database",
    "-user=$DbUser",
    "-password=$DbPassword",
    "-locations=filesystem:/flyway/sql",
    "repair"
)

Write-Host "[flyway-repair] Running Flyway repair via container image $flywayTag ..."
& docker @flywayArgs
if ($LASTEXITCODE -ne 0) {
    throw "Flyway repair failed."
}

$updatedV1Checksum = Invoke-PostgresScalar @"
SELECT COALESCE(checksum::text, 'NULL')
FROM flyway_schema_history
WHERE version ~ '^[0-9]+$' AND version::int = 1 AND success = true
ORDER BY installed_rank DESC
LIMIT 1;
"@

if ([string]::IsNullOrWhiteSpace($updatedV1Checksum)) {
    if ($baselineVersion -match '^\d+$' -and [int]$baselineVersion -ge 1) {
        Write-Host "[flyway-repair] Repair completed. Baseline environment has no version=1 row (baseline=$baselineVersion)."
    } else {
        Write-Warning "[flyway-repair] Repair completed, but version=1 row was not found."
    }
} else {
    Write-Host "[flyway-repair] Updated V001 checksum: $updatedV1Checksum"
}

Write-Host "[flyway-repair] SUCCESS: checksum reconciliation completed."
