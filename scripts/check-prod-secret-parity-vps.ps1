param(
    [string]$SshTarget = "root@84.46.251.95",
    [string]$RemoteSecretsDir = "/opt/vocabmaster/secrets",
    [string]$RemoteDeployDir = "/opt/vocabmaster/deploy",
    [string]$RemoteComposeFile = "docker-compose.app.yml",
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

    Write-Host "[secret-parity] RUN: $Command $($Arguments -join ' ')"
    if ([string]::IsNullOrEmpty($InputString)) {
        & $Command @Arguments
    } else {
        $InputString | & $Command @Arguments
    }
    if ($LASTEXITCODE -ne 0) {
        throw "[secret-parity] command failed: $Command (exit=$LASTEXITCODE)"
    }
}

Write-Host "[secret-parity] Production secret parity check plan"
Write-Host "[secret-parity]   ssh target:        $SshTarget"
Write-Host "[secret-parity]   remote secrets:    $RemoteSecretsDir"
Write-Host "[secret-parity]   remote deploy dir: $RemoteDeployDir"
Write-Host "[secret-parity]   compose file:      $RemoteComposeFile"
Write-Host "[secret-parity]   backend container: $BackendContainer"
Write-Host "[secret-parity] Secret values are never printed by this script."

if (-not $Execute) {
    Write-Host "[secret-parity] DRY RUN only. Re-run with -Execute for a read-only SSH check."
    exit 0
}

$remoteScript = @"
set -euo pipefail

REMOTE_SECRETS_DIR=$(ConvertTo-BashSingleQuoted $RemoteSecretsDir)
REMOTE_DEPLOY_DIR=$(ConvertTo-BashSingleQuoted $RemoteDeployDir)
REMOTE_COMPOSE_FILE=$(ConvertTo-BashSingleQuoted $RemoteComposeFile)
BACKEND_CONTAINER=$(ConvertTo-BashSingleQuoted $BackendContainer)

BACKEND_ENV="`$REMOTE_SECRETS_DIR/backend.env"
REDIS_ENV="`$REMOTE_SECRETS_DIR/redis.env"
REDIS_SECURITY_ENV="`$REMOTE_SECRETS_DIR/redis-security.env"

fail() {
  echo "[secret-parity] FAIL: `$*" >&2
  exit 1
}

pass() {
  echo "[secret-parity] PASS: `$*"
}

warn() {
  echo "[secret-parity] WARN: `$*"
}

get_env() {
  local file="`$1"
  local key="`$2"
  awk -F= -v k="`$key" '
    `$0 ~ "^[[:space:]]*#" { next }
    `$1 == k {
      sub("^[^=]*=", "", `$0)
      print `$0
      exit
    }
  ' "`$file"
}

require_file() {
  local file="`$1"
  test -f "`$file" || fail "missing file: `$file"
  pass "file exists: `$file"
  local mode
  mode=`$(stat -c '%a' "`$file")
  echo "[secret-parity] file mode `$file=`$mode"
  case "`$mode" in
    600|640|400|440) pass "file permissions are tight enough for `$file" ;;
    *) fail "file permissions are too broad for `$file; expected 600/640/400/440" ;;
  esac
}

require_present() {
  local file="`$1"
  local key="`$2"
  local min_len="`$3"
  local value
  value=`$(get_env "`$file" "`$key")
  if [ -z "`$value" ]; then
    fail "`$key is missing or empty in `$file"
  fi
  local len
  len=`${#value}
  if [ "`$len" -lt "`$min_len" ]; then
    fail "`$key in `$file is shorter than required minimum length `$min_len"
  fi
  pass "`$key present in `$file (length=`$len)"
}

require_bool() {
  local file="`$1"
  local key="`$2"
  local expected="`$3"
  local value
  value=`$(get_env "`$file" "`$key" | tr '[:upper:]' '[:lower:]')
  if [ "`$value" != "`$expected" ]; then
    fail "`$key expected `$expected in `$file"
  fi
  pass "`$key=`$expected in `$file"
}

require_equal() {
  local left_file="`$1"
  local left_key="`$2"
  local right_file="`$3"
  local right_key="`$4"
  local left_value
  local right_value
  left_value=`$(get_env "`$left_file" "`$left_key")
  right_value=`$(get_env "`$right_file" "`$right_key")
  if [ -z "`$left_value" ] || [ -z "`$right_value" ]; then
    fail "cannot compare `$left_key and `$right_key because one side is empty"
  fi
  if [ "`$left_value" != "`$right_value" ]; then
    fail "`$left_key and `$right_key do not match"
  fi
  pass "`$left_key matches `$right_key"
}

require_file "`$BACKEND_ENV"
require_file "`$REDIS_ENV"
require_file "`$REDIS_SECURITY_ENV"

require_present "`$BACKEND_ENV" "SPRING_DATASOURCE_PASSWORD" 16
require_present "`$BACKEND_ENV" "SPRING_DATA_REDIS_PASSWORD" 16
require_present "`$BACKEND_ENV" "SPRING_DATA_REDIS_SECURITY_PASSWORD" 16
require_present "`$BACKEND_ENV" "GROQ_API_KEY" 20
require_present "`$BACKEND_ENV" "APP_SECURITY_JWT_SECRET" 32
require_present "`$BACKEND_ENV" "APP_SECURITY_AUTH_GOOGLE_CLIENT_IDS" 10
require_present "`$BACKEND_ENV" "APP_SUBSCRIPTION_GOOGLE_PLAY_PACKAGE_NAME" 3
require_present "`$BACKEND_ENV" "APP_SUBSCRIPTION_GOOGLE_PLAY_SERVICE_ACCOUNT_FILE" 3

rtdn_enabled=`$(get_env "`$BACKEND_ENV" "APP_SUBSCRIPTION_GOOGLE_PLAY_RTDN_ENABLED" | tr '[:upper:]' '[:lower:]')
if [ "`$rtdn_enabled" = "true" ] || [ "`$rtdn_enabled" = "1" ] || [ "`$rtdn_enabled" = "yes" ]; then
  require_present "`$BACKEND_ENV" "APP_SUBSCRIPTION_GOOGLE_PLAY_RTDN_SHARED_SECRET" 32
else
  pass "RTDN is not enabled; shared secret is optional"
fi

firebase_enabled=`$(get_env "`$BACKEND_ENV" "APP_PUSH_FIREBASE_ENABLED" | tr '[:upper:]' '[:lower:]')
if [ "`$firebase_enabled" = "true" ] || [ "`$firebase_enabled" = "1" ] || [ "`$firebase_enabled" = "yes" ]; then
  require_present "`$BACKEND_ENV" "APP_PUSH_FIREBASE_SERVICE_ACCOUNT_FILE" 3
else
  warn "Firebase Admin push is not enabled in backend.env"
fi

require_present "`$REDIS_ENV" "REDIS_PASSWORD" 16
require_present "`$REDIS_SECURITY_ENV" "REDIS_SECURITY_PASSWORD" 16
require_equal "`$BACKEND_ENV" "SPRING_DATA_REDIS_PASSWORD" "`$REDIS_ENV" "REDIS_PASSWORD"
require_equal "`$BACKEND_ENV" "SPRING_DATA_REDIS_SECURITY_PASSWORD" "`$REDIS_SECURITY_ENV" "REDIS_SECURITY_PASSWORD"

cd "`$REMOTE_DEPLOY_DIR"
docker compose -f "`$REMOTE_COMPOSE_FILE" config >/tmp/klioai-compose-secret-parity.yml
pass "docker compose config renders"

docker inspect "`$BACKEND_CONTAINER" >/dev/null 2>&1 || fail "backend container not found"
backend_health=`$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' "`$BACKEND_CONTAINER")
echo "[secret-parity] backend container health=`$backend_health"
if [ "`$backend_health" != "healthy" ]; then
  fail "backend container is not healthy"
fi
pass "backend container is healthy"

require_container_bool() {
  local key="`$1"
  local expected="`$2"
  local value
  value=`$(docker exec "`$BACKEND_CONTAINER" printenv "`$key" | tr '[:upper:]' '[:lower:]')
  if [ "`$value" != "`$expected" ]; then
    fail "container env `$key expected `$expected"
  fi
  pass "container env `$key=`$expected"
}

require_container_bool "APP_SECURITY_JWT_ENFORCE_AUTH" "true"
require_container_bool "APP_SECURITY_AUTH_GOOGLE_ID_TOKEN_REQUIRED" "true"
require_container_bool "APP_SUBSCRIPTION_MOCK_VERIFICATION_ENABLED" "false"
require_container_bool "APP_SUBSCRIPTION_GOOGLE_PLAY_ENABLED" "true"

docker exec "`$BACKEND_CONTAINER" sh -lc 'test -r /run/secrets/google-play-service-account.json'
pass "backend can read mounted Google Play service-account file"

if [ "`$firebase_enabled" = "true" ] || [ "`$firebase_enabled" = "1" ] || [ "`$firebase_enabled" = "yes" ]; then
  docker exec "`$BACKEND_CONTAINER" sh -lc 'test -r /run/secrets/firebase-admin-service-account.json'
  pass "backend can read mounted Firebase service-account file"
fi

echo "[secret-parity] SUCCESS"
"@

Invoke-Native -Command "ssh" -Arguments @($SshOptions + @($SshTarget, "bash -s")) -InputString $remoteScript
