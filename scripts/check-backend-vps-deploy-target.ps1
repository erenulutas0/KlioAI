param(
    [string]$SshTarget = "root@84.46.251.95",
    [string]$RemoteBackendPath = "/opt/vocabmaster/backend-src/backend",
    [string]$RemoteDeployDir = "/opt/vocabmaster/deploy",
    [string]$RemoteComposeFile = "docker-compose.app.yml",
    [string]$BackendService = "backend",
    [string]$BackendContainer = "vocabmaster-backend",
    [string[]]$SshOptions = @("-o", "BatchMode=yes", "-o", "ConnectTimeout=15"),
    [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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

    Write-Host "[deploy-target-check] RUN: $Command $($Arguments -join ' ')"
    if ([string]::IsNullOrEmpty($InputString)) {
        & $Command @Arguments
    } else {
        $InputString | & $Command @Arguments
    }
    if ($LASTEXITCODE -ne 0) {
        throw "[deploy-target-check] command failed: $Command (exit=$LASTEXITCODE)"
    }
}

Write-Host "[deploy-target-check] Backend VPS target check plan"
Write-Host "[deploy-target-check]   ssh target:          $SshTarget"
Write-Host "[deploy-target-check]   remote backend path: $RemoteBackendPath"
Write-Host "[deploy-target-check]   remote deploy dir:   $RemoteDeployDir"
Write-Host "[deploy-target-check]   compose file:        $RemoteComposeFile"
Write-Host "[deploy-target-check]   service/container:   $BackendService / $BackendContainer"

if (-not $Execute) {
    Write-Host "[deploy-target-check] DRY RUN only. Re-run with -Execute for a read-only SSH check."
    exit 0
}

$remoteScript = @"
set -euo pipefail

REMOTE_BACKEND_PATH=$(ConvertTo-BashSingleQuoted $RemoteBackendPath)
REMOTE_DEPLOY_DIR=$(ConvertTo-BashSingleQuoted $RemoteDeployDir)
REMOTE_COMPOSE_FILE=$(ConvertTo-BashSingleQuoted $RemoteComposeFile)
BACKEND_SERVICE=$(ConvertTo-BashSingleQuoted $BackendService)
BACKEND_CONTAINER=$(ConvertTo-BashSingleQuoted $BackendContainer)

fail() {
  echo "[deploy-target-check] FAIL: `$*" >&2
  exit 1
}

pass() {
  echo "[deploy-target-check] PASS: `$*"
}

echo "[deploy-target-check] Remote host: `$(hostname)"
test -d "`$REMOTE_DEPLOY_DIR" || fail "deploy dir missing: `$REMOTE_DEPLOY_DIR"
pass "deploy dir exists"

test -f "`$REMOTE_DEPLOY_DIR/`$REMOTE_COMPOSE_FILE" || fail "compose file missing: `$REMOTE_DEPLOY_DIR/`$REMOTE_COMPOSE_FILE"
pass "compose file exists"

test -d "`$REMOTE_BACKEND_PATH" || fail "backend source dir missing: `$REMOTE_BACKEND_PATH"
test -f "`$REMOTE_BACKEND_PATH/Dockerfile" || fail "backend Dockerfile missing under `$REMOTE_BACKEND_PATH"
test -f "`$REMOTE_BACKEND_PATH/pom.xml" || fail "backend pom.xml missing under `$REMOTE_BACKEND_PATH"
test -d "`$REMOTE_BACKEND_PATH/src/main" || fail "backend src/main missing under `$REMOTE_BACKEND_PATH"
pass "backend source shape looks valid"

cd "`$REMOTE_DEPLOY_DIR"
docker compose -f "`$REMOTE_COMPOSE_FILE" config --services | grep -Fx "`$BACKEND_SERVICE" >/dev/null || fail "compose service not found: `$BACKEND_SERVICE"
pass "compose service exists"

configured_context=`$(docker compose -f "`$REMOTE_COMPOSE_FILE" config | awk -v service="`$BACKEND_SERVICE" '
  `$0 ~ "^  " service ":" { in_service=1; next }
  in_service && /^  [a-zA-Z0-9_.-]+:/ { in_service=0 }
  in_service && `$1 == "context:" { print `$2; exit }
')

if [ -z "`$configured_context" ]; then
  fail "could not read backend build.context from docker compose config"
fi

resolved_context=`$(realpath -m "`$configured_context")
resolved_backend=`$(realpath -m "`$REMOTE_BACKEND_PATH")
echo "[deploy-target-check] compose build.context=`$resolved_context"
echo "[deploy-target-check] expected backend path=`$resolved_backend"

if [ "`$resolved_context" != "`$resolved_backend" ]; then
  fail "compose build.context does not match RemoteBackendPath"
fi
pass "compose build.context matches RemoteBackendPath"

container_status=`$(docker inspect -f '{{.State.Status}}' "`$BACKEND_CONTAINER" 2>/dev/null || true)
if [ -z "`$container_status" ]; then
  fail "backend container not found: `$BACKEND_CONTAINER"
fi
echo "[deploy-target-check] container status=`$container_status"

container_health=`$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' "`$BACKEND_CONTAINER")
echo "[deploy-target-check] container health=`$container_health"

if [ "`$container_health" != "healthy" ]; then
  fail "backend container is not healthy"
fi
pass "backend container is healthy"

docker exec "`$BACKEND_CONTAINER" sh -lc 'curl -fsS http://localhost:8082/actuator/health' >/tmp/klioai-target-check-health.json
grep -q '"status":"UP"' /tmp/klioai-target-check-health.json || fail "internal health is not UP"
cat /tmp/klioai-target-check-health.json
echo
pass "internal actuator health is UP"

echo "[deploy-target-check] SUCCESS"
"@

Invoke-Native -Command "ssh" -Arguments @($SshOptions + @($SshTarget, "bash -s")) -InputString $remoteScript
