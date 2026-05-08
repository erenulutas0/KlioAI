param(
    [string]$ProjectName = "english-app-smoke",
    [string]$ComposeFile = "",
    [string]$ComposeOverrideFile = "",
    [string]$PostgresService = "postgres",
    [string]$PostgresDatabase = "EnglishApp",
    [string]$PostgresUser = "postgres",
    [string]$RestoreImage = "postgres:15-alpine",
    [string]$RestoreContainerName = "klio-backup-restore-check",
    [string]$RestoreDatabase = "restore_check"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if ([string]::IsNullOrWhiteSpace($ComposeFile)) {
    $ComposeFile = Join-Path $repoRoot "docker-compose.yml"
}
if ([string]::IsNullOrWhiteSpace($ComposeOverrideFile)) {
    $ComposeOverrideFile = Join-Path $repoRoot "docker-compose.smoke.yml"
}

$backupPath = Join-Path ([System.IO.Path]::GetTempPath()) "klio-backup-restore-check-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()).dump"
$sourceDumpPath = "/tmp/klio-backup-restore-check.dump"

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

function Invoke-Compose {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

    $composeArgs = @("-p", $ProjectName, "-f", $ComposeFile)
    if (-not [string]::IsNullOrWhiteSpace($ComposeOverrideFile) -and (Test-Path $ComposeOverrideFile)) {
        $composeArgs += @("-f", $ComposeOverrideFile)
    }
    $composeArgs += $Args

    & docker compose @composeArgs
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose failed: $($Args -join ' ')"
    }
}

function Invoke-Docker {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    & docker @Args
    if ($LASTEXITCODE -ne 0) {
        throw "docker failed: $($Args -join ' ')"
    }
}

function Invoke-RestoreScalar {
    param([string]$Sql)
    $output = Invoke-Docker @(
        "exec", $RestoreContainerName,
        "psql", "-h", "127.0.0.1", "-U", "postgres", "-d", $RestoreDatabase,
        "-t", "-A", "-c", $Sql
    )
    $lines = @($output | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ -ne "" })
    if ($lines.Count -eq 0) {
        return ""
    }
    return $lines[-1]
}

function Wait-RestorePostgres {
    for ($i = 1; $i -le 45; $i++) {
        & docker exec $RestoreContainerName pg_isready -h 127.0.0.1 -U postgres -d $RestoreDatabase *> $null
        if ($LASTEXITCODE -eq 0) {
            return
        }
        Start-Sleep -Seconds 1
    }
    throw "Restore PostgreSQL container did not become ready."
}

try {
    $dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
    Assert-True ($null -ne $dockerCmd) "Docker CLI not found in PATH."

    Write-Host "[backup-restore] Creating pg_dump from compose service '$PostgresService'..."
    Invoke-Compose @(
        "exec", "-T", $PostgresService,
        "sh", "-lc",
        "pg_dump -U $PostgresUser -d $PostgresDatabase -Fc -f $sourceDumpPath"
    )

    $sourceContainerId = (Invoke-Compose @("ps", "-q", $PostgresService) | Select-Object -First 1).Trim()
    Assert-True (-not [string]::IsNullOrWhiteSpace($sourceContainerId)) "Could not resolve source Postgres container id."

    Invoke-Docker @("cp", "${sourceContainerId}:$sourceDumpPath", $backupPath)
    Assert-True (Test-Path $backupPath) "Backup dump was not copied to host."
    Assert-True ((Get-Item $backupPath).Length -gt 0) "Backup dump is empty."

    Write-Host "[backup-restore] Starting isolated restore container '$RestoreContainerName'..."
    & docker rm -f $RestoreContainerName *> $null
    Invoke-Docker @(
        "run", "-d",
        "--name", $RestoreContainerName,
        "-e", "POSTGRES_PASSWORD=postgres",
        "-e", "POSTGRES_DB=$RestoreDatabase",
        $RestoreImage
    )
    Wait-RestorePostgres

    Invoke-Docker @("cp", $backupPath, "${RestoreContainerName}:/tmp/restore.dump")
    Invoke-Docker @(
        "exec", $RestoreContainerName,
        "pg_restore", "-h", "127.0.0.1", "-U", "postgres", "-d", $RestoreDatabase,
        "--no-owner", "--no-privileges",
        "/tmp/restore.dump"
    )

    $tableCountRaw = Invoke-RestoreScalar "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';"
    [int]$tableCount = 0
    Assert-True ([int]::TryParse($tableCountRaw, [ref]$tableCount)) "Could not parse restored table count: '$tableCountRaw'"
    Assert-True ($tableCount -ge 10) "Restored table count too low: $tableCount"

    $usersExists = Invoke-RestoreScalar "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='users');"
    Assert-True ($usersExists -eq "t") "Restored DB missing users table."

    $flywayVersion = Invoke-RestoreScalar "SELECT COALESCE(MAX(version::int), 0) FROM flyway_schema_history WHERE success = true AND version ~ '^[0-9]+$';"
    Assert-True (-not [string]::IsNullOrWhiteSpace($flywayVersion)) "Restored DB missing Flyway history."

    Write-Host "[backup-restore] SUCCESS: backup restored into isolated DB. tables=$tableCount flyway_latest=$flywayVersion"
} finally {
    Write-Host "[backup-restore] Cleanup..."
    & docker rm -f $RestoreContainerName *> $null
    if (Test-Path $backupPath) {
        Remove-Item -LiteralPath $backupPath -Force
    }
    try {
        Invoke-Compose @("exec", "-T", $PostgresService, "rm", "-f", $sourceDumpPath)
    } catch {
        Write-Warning "[backup-restore] Source dump cleanup failed: $($_.Exception.Message)"
    }
}
