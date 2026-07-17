param(
    [string]$SshTarget = "root@84.46.251.95",
    [string]$RemoteBackendPath = "/opt/vocabmaster/backend-src/backend",
    [string]$RemoteDeployDir = "/opt/vocabmaster/deploy",
    [string]$RemoteComposeFile = "docker-compose.app.yml",
    [string]$RemoteUploadDir = "/opt/vocabmaster/uploads",
    [string]$RemoteBackupDir = "/opt/vocabmaster/backups/deploy",
    [string]$BackendService = "backend",
    [string]$BackendContainer = "vocabmaster-backend",
    [string]$PublicBaseUrl = "https://api.klioai.app",
    [string]$Label = "manual",
    [string[]]$SshOptions = @("-o", "BatchMode=yes", "-o", "ConnectTimeout=15"),
    [string[]]$ScpOptions = @("-o", "BatchMode=yes", "-o", "ConnectTimeout=15"),
    [int]$HealthAttempts = 40,
    [int]$HealthSleepSeconds = 5,
    [switch]$NoCache,
    [switch]$SkipPublicSmoke,
    [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$backendDir = Join-Path $repoRoot "backend"
$timestamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$safeLabel = ($Label -replace "[^a-zA-Z0-9._-]", "-").Trim("-")
if ([string]::IsNullOrWhiteSpace($safeLabel)) {
    $safeLabel = "manual"
}

$archiveName = "backend-src-codex-$safeLabel-$timestamp.tar.gz"
$archivePath = Join-Path ([System.IO.Path]::GetTempPath()) $archiveName
$remoteArchivePath = "$($RemoteUploadDir.TrimEnd('/'))/$archiveName"
$remoteBackupPath = "$($RemoteBackupDir.TrimEnd('/'))/backend-src-pre-codex-$safeLabel-$timestamp.tar.gz"

function ConvertTo-BashSingleQuoted {
    param([string]$Value)
    return "'" + ($Value -replace "'", "'\''") + "'"
}

function Invoke-Native {
    param(
        [string]$Command,
        [string[]]$Arguments,
        [string]$InputString = ""
    )

    Write-Host "[backend-deploy] RUN: $Command $($Arguments -join ' ')"
    if ([string]::IsNullOrEmpty($InputString)) {
        & $Command @Arguments
    } else {
        $InputString | & $Command @Arguments
    }
    if ($LASTEXITCODE -ne 0) {
        throw "[backend-deploy] command failed: $Command (exit=$LASTEXITCODE)"
    }
}

function Assert-LocalPreconditions {
    if (-not (Test-Path -LiteralPath $backendDir -PathType Container)) {
        throw "[backend-deploy] backend directory not found: $backendDir"
    }

    $dockerfile = Join-Path $backendDir "Dockerfile"
    if (-not (Test-Path -LiteralPath $dockerfile -PathType Leaf)) {
        throw "[backend-deploy] backend Dockerfile not found: $dockerfile"
    }

    if ($HealthAttempts -lt 1) {
        throw "[backend-deploy] HealthAttempts must be >= 1"
    }

    if ($HealthSleepSeconds -lt 1) {
        throw "[backend-deploy] HealthSleepSeconds must be >= 1"
    }
}

function New-BackendArchive {
    if (Test-Path -LiteralPath $archivePath) {
        Remove-Item -LiteralPath $archivePath -Force
    }

    Write-Host "[backend-deploy] Packaging backend source: $archivePath"
    Push-Location $backendDir
    try {
        $tarArgs = @(
            "-czf", $archivePath,
            "--exclude=target",
            "--exclude=.m2-repo",
            "--exclude=.m2",
            "--exclude=.gradle",
            "--exclude=*.log",
            "--exclude=error_log*.txt",
            "--exclude=output*.txt",
            "."
        )
        Invoke-Native -Command "tar" -Arguments $tarArgs
    } finally {
        Pop-Location
    }

    $archive = Get-Item -LiteralPath $archivePath
    if ($archive.Length -le 0) {
        throw "[backend-deploy] archive is empty: $archivePath"
    }

    Write-Host "[backend-deploy] Archive ready: $([math]::Round($archive.Length / 1MB, 2)) MB"
}

function Test-PublicHealth {
    $healthUrl = "$($PublicBaseUrl.TrimEnd('/'))/actuator/health"
    Write-Host "[backend-deploy] Public health check: $healthUrl"
    $response = Invoke-WebRequest -Uri $healthUrl -TimeoutSec 20 -UseBasicParsing
    if ([int]$response.StatusCode -ne 200) {
        throw "[backend-deploy] public health expected 200, got $($response.StatusCode)"
    }
    Write-Host "[backend-deploy] PASS public health"
}

Assert-LocalPreconditions

Write-Host "[backend-deploy] Backend deploy plan"
Write-Host "[backend-deploy]   ssh target:          $SshTarget"
Write-Host "[backend-deploy]   remote backend path: $RemoteBackendPath"
Write-Host "[backend-deploy]   remote deploy dir:   $RemoteDeployDir"
Write-Host "[backend-deploy]   compose file:        $RemoteComposeFile"
Write-Host "[backend-deploy]   service/container:   $BackendService / $BackendContainer"
Write-Host "[backend-deploy]   upload archive:      $remoteArchivePath"
Write-Host "[backend-deploy]   pre-deploy backup:   $remoteBackupPath"
Write-Host "[backend-deploy]   no-cache build:      $([bool]$NoCache)"
Write-Host "[backend-deploy]   public smoke:        $(-not [bool]$SkipPublicSmoke)"

if (-not $Execute) {
    Write-Host "[backend-deploy] DRY RUN only. Re-run with -Execute to package, upload, backup, rebuild, and smoke."
    exit 0
}

New-BackendArchive

$prepareRemote = @"
set -euo pipefail
mkdir -p $(ConvertTo-BashSingleQuoted $RemoteUploadDir) $(ConvertTo-BashSingleQuoted $RemoteBackupDir)
test -d $(ConvertTo-BashSingleQuoted $RemoteDeployDir)
if [ ! -f $(ConvertTo-BashSingleQuoted "$RemoteDeployDir/$RemoteComposeFile") ]; then
  echo "[backend-deploy] missing compose file: $RemoteDeployDir/$RemoteComposeFile" >&2
  exit 1
fi
if [ "${RemoteBackendPath}" = "/" ] || [ "${RemoteBackendPath}" = "/opt" ] || [ "${RemoteBackendPath}" = "/opt/vocabmaster" ]; then
  echo "[backend-deploy] refusing unsafe RemoteBackendPath: $RemoteBackendPath" >&2
  exit 1
fi
case $(ConvertTo-BashSingleQuoted $RemoteBackendPath) in
  /opt/vocabmaster/*) ;;
  *)
    echo "[backend-deploy] RemoteBackendPath must stay under /opt/vocabmaster: $RemoteBackendPath" >&2
    exit 1
    ;;
esac
"@

Invoke-Native -Command "ssh" -Arguments @($SshOptions + @($SshTarget, $prepareRemote))
Invoke-Native -Command "scp" -Arguments @($ScpOptions + @($archivePath, "$SshTarget`:$remoteArchivePath"))

$cacheArg = ""
if ($NoCache) {
    $cacheArg = "--no-cache"
}

$remoteScript = @"
set -euo pipefail

REMOTE_BACKEND_PATH=$(ConvertTo-BashSingleQuoted $RemoteBackendPath)
REMOTE_ARCHIVE_PATH=$(ConvertTo-BashSingleQuoted $remoteArchivePath)
REMOTE_BACKUP_PATH=$(ConvertTo-BashSingleQuoted $remoteBackupPath)
REMOTE_DEPLOY_DIR=$(ConvertTo-BashSingleQuoted $RemoteDeployDir)
REMOTE_COMPOSE_FILE=$(ConvertTo-BashSingleQuoted $RemoteComposeFile)
BACKEND_SERVICE=$(ConvertTo-BashSingleQuoted $BackendService)
BACKEND_CONTAINER=$(ConvertTo-BashSingleQuoted $BackendContainer)
HEALTH_ATTEMPTS=$HealthAttempts
HEALTH_SLEEP_SECONDS=$HealthSleepSeconds
CACHE_ARG=$(ConvertTo-BashSingleQuoted $cacheArg)

echo "[backend-deploy] Remote deploy started."
test -f "`$REMOTE_ARCHIVE_PATH"
mkdir -p "`$REMOTE_BACKEND_PATH" "`$(dirname "`$REMOTE_BACKUP_PATH")"

if find "`$REMOTE_BACKEND_PATH" -mindepth 1 -maxdepth 1 | grep -q .; then
  echo "[backend-deploy] Backing up current backend source to `$REMOTE_BACKUP_PATH"
  tar -czf "`$REMOTE_BACKUP_PATH" -C "`$REMOTE_BACKEND_PATH" .
else
  echo "[backend-deploy] Current backend source path is empty; creating empty backup marker."
  tar -czf "`$REMOTE_BACKUP_PATH" --files-from /dev/null
fi

echo "[backend-deploy] Replacing backend source under `$REMOTE_BACKEND_PATH"
find "`$REMOTE_BACKEND_PATH" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
tar -xzf "`$REMOTE_ARCHIVE_PATH" -C "`$REMOTE_BACKEND_PATH"

cd "`$REMOTE_DEPLOY_DIR"
echo "[backend-deploy] Building backend image."
docker compose -f "`$REMOTE_COMPOSE_FILE" build `$CACHE_ARG "`$BACKEND_SERVICE"

echo "[backend-deploy] Recreating backend container."
docker compose -f "`$REMOTE_COMPOSE_FILE" up -d --no-deps --force-recreate "`$BACKEND_SERVICE"

echo "[backend-deploy] Waiting for backend container health."
for i in `$(seq 1 "`$HEALTH_ATTEMPTS"); do
  status=`$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "`$BACKEND_CONTAINER" 2>/dev/null || true)
  echo "[backend-deploy] health attempt `$i/`$HEALTH_ATTEMPTS: `$status"
  if [ "`$status" = "healthy" ]; then
    break
  fi
  sleep "`$HEALTH_SLEEP_SECONDS"
done

final_status=`$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "`$BACKEND_CONTAINER")
if [ "`$final_status" != "healthy" ]; then
  echo "[backend-deploy] backend did not become healthy; recent logs:" >&2
  docker logs --tail 120 "`$BACKEND_CONTAINER" >&2 || true
  exit 1
fi

docker exec "`$BACKEND_CONTAINER" sh -lc 'curl -fsS http://localhost:8082/actuator/health >/tmp/klioai-health.json && cat /tmp/klioai-health.json'
docker compose -f "`$REMOTE_COMPOSE_FILE" ps "`$BACKEND_SERVICE"

echo "[backend-deploy] SUCCESS remote deploy complete."
echo "[backend-deploy] Backup path: `$REMOTE_BACKUP_PATH"
"@

Invoke-Native -Command "ssh" -Arguments @($SshOptions + @($SshTarget, "bash -s")) -InputString $remoteScript

if (-not $SkipPublicSmoke) {
    Test-PublicHealth
}

Write-Host "[backend-deploy] SUCCESS"
Write-Host "[backend-deploy] Rollback source backup:"
Write-Host "[backend-deploy]   $remoteBackupPath"
Write-Host "[backend-deploy] Rollback outline:"
Write-Host "[backend-deploy]   restore that tarball into $RemoteBackendPath, then run docker compose -f $RemoteComposeFile build $BackendService && docker compose -f $RemoteComposeFile up -d --no-deps --force-recreate $BackendService"

Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue
