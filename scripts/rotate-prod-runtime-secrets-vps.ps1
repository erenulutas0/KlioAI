param(
    [string]$SshTarget = "root@84.46.251.95",
    [string]$RemoteDeployDir = "/opt/vocabmaster/deploy",
    [string]$RemoteSecretsDir = "/opt/vocabmaster/secrets",
    [string]$RemoteBackupDir = "/opt/vocabmaster/backups/deploy",
    [bool]$RotateJwt = $true,
    [bool]$RotateRedis = $true,
    [bool]$RotateRedisSecurity = $true,
    [bool]$RotateRtdn = $false,
    [int]$Bytes = 48,
    [switch]$Execute
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ($Bytes -lt 32) {
    throw "[secret-rotation] Bytes must be >= 32 for production runtime secrets."
}

function New-SecretValue {
    param([int]$LengthBytes)

    $bytes = [byte[]]::new($LengthBytes)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    return [Convert]::ToBase64String($bytes).TrimEnd("=") -replace "\+", "-" -replace "/", "_"
}

$plannedKeys = New-Object System.Collections.Generic.List[string]
$secretEntries = [ordered]@{
    ROTATE_JWT            = $(if ($RotateJwt) { "1" } else { "0" })
    ROTATE_REDIS          = $(if ($RotateRedis) { "1" } else { "0" })
    ROTATE_REDIS_SECURITY = $(if ($RotateRedisSecurity) { "1" } else { "0" })
    ROTATE_RTDN           = $(if ($RotateRtdn) { "1" } else { "0" })
}

if ($RotateJwt) {
    $secretEntries.APP_SECURITY_JWT_SECRET = New-SecretValue -LengthBytes $Bytes
    $plannedKeys.Add("APP_SECURITY_JWT_SECRET") | Out-Null
}
if ($RotateRedis) {
    $secretEntries.REDIS_PASSWORD = New-SecretValue -LengthBytes $Bytes
    $secretEntries.SPRING_DATA_REDIS_PASSWORD = $secretEntries.REDIS_PASSWORD
    $plannedKeys.Add("REDIS_PASSWORD") | Out-Null
    $plannedKeys.Add("SPRING_DATA_REDIS_PASSWORD") | Out-Null
}
if ($RotateRedisSecurity) {
    $secretEntries.REDIS_SECURITY_PASSWORD = New-SecretValue -LengthBytes $Bytes
    $secretEntries.SPRING_DATA_REDIS_SECURITY_PASSWORD = $secretEntries.REDIS_SECURITY_PASSWORD
    $plannedKeys.Add("REDIS_SECURITY_PASSWORD") | Out-Null
    $plannedKeys.Add("SPRING_DATA_REDIS_SECURITY_PASSWORD") | Out-Null
}
if ($RotateRtdn) {
    $secretEntries.APP_SUBSCRIPTION_GOOGLE_PLAY_RTDN_SHARED_SECRET = New-SecretValue -LengthBytes $Bytes
    $plannedKeys.Add("APP_SUBSCRIPTION_GOOGLE_PLAY_RTDN_SHARED_SECRET") | Out-Null
}

Write-Host "[secret-rotation] Target: $SshTarget"
Write-Host "[secret-rotation] Remote deploy dir: $RemoteDeployDir"
Write-Host "[secret-rotation] Remote secrets dir: $RemoteSecretsDir"
Write-Host "[secret-rotation] Remote backup dir: $RemoteBackupDir"
Write-Host "[secret-rotation] Planned rotated keys:"
foreach ($key in $plannedKeys) {
    Write-Host "  - $key"
}
Write-Host "[secret-rotation] Not rotated by this script: GROQ_API_KEY, Google/Firebase service-account files, PostgreSQL password."
Write-Host "[secret-rotation] Impact: JWT rotation can force mobile users to sign in again; Redis rotation recreates Redis and backend containers."

if (-not $Execute) {
    Write-Host "[secret-rotation] DRY RUN only. Re-run with -Execute during a quiet window to apply."
    exit 0
}

if ($plannedKeys.Count -eq 0) {
    throw "[secret-rotation] Nothing selected to rotate."
}

$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$localSecretFile = Join-Path $env:TEMP "klioai-runtime-rotation-$stamp.env"
$localRemoteScript = Join-Path $env:TEMP "klioai-runtime-rotation-$stamp.sh"
$remoteSecretFile = "/tmp/klioai-runtime-rotation-$stamp.env"
$remoteScriptFile = "/tmp/klioai-runtime-rotation-$stamp.sh"

try {
    $secretLines = New-Object System.Collections.Generic.List[string]
    foreach ($key in $secretEntries.Keys) {
        $secretLines.Add("$key=$($secretEntries[$key])") | Out-Null
    }
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($localSecretFile, (($secretLines -join "`n") + "`n"), $utf8NoBom)

    $remoteScriptContent = @'
set -euo pipefail

secret_file="$1"
remote_secrets_dir="$2"
remote_deploy_dir="$3"
remote_backup_dir="$4"

backend_env="$remote_secrets_dir/backend.env"
redis_env="$remote_secrets_dir/redis.env"
redis_security_env="$remote_secrets_dir/redis-security.env"

set -a
. "$secret_file"
set +a

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
install -d -m 700 "$remote_backup_dir"

copy_if_exists() {
  src="$1"
  label="$2"
  if [ -f "$src" ]; then
    dst="$remote_backup_dir/${label}-pre-secret-rotation-${timestamp}.env"
    cp "$src" "$dst"
    chmod 600 "$dst"
    echo "[secret-rotation] Backup: $dst"
  fi
}

set_key() {
  file="$1"
  key="$2"
  value="$3"
  if [ ! -f "$file" ]; then
    echo "[secret-rotation] Missing env file: $file" >&2
    exit 1
  fi
  tmp="${file}.tmp.$$"
  awk -v k="$key" -v v="$value" '
    BEGIN { done = 0 }
    index($0, k "=") == 1 { print k "=" v; done = 1; next }
    { print }
    END { if (done == 0) print k "=" v }
  ' "$file" > "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

copy_if_exists "$backend_env" "backend-env"
copy_if_exists "$redis_env" "redis-env"
copy_if_exists "$redis_security_env" "redis-security-env"

if [ "${ROTATE_JWT:-0}" = "1" ]; then
  set_key "$backend_env" APP_SECURITY_JWT_SECRET "$APP_SECURITY_JWT_SECRET"
  echo "[secret-rotation] Rotated APP_SECURITY_JWT_SECRET"
fi

if [ "${ROTATE_REDIS:-0}" = "1" ]; then
  set_key "$backend_env" SPRING_DATA_REDIS_PASSWORD "$SPRING_DATA_REDIS_PASSWORD"
  set_key "$redis_env" REDIS_PASSWORD "$REDIS_PASSWORD"
  echo "[secret-rotation] Rotated Redis application password pair"
fi

if [ "${ROTATE_REDIS_SECURITY:-0}" = "1" ]; then
  set_key "$backend_env" SPRING_DATA_REDIS_SECURITY_PASSWORD "$SPRING_DATA_REDIS_SECURITY_PASSWORD"
  set_key "$redis_security_env" REDIS_SECURITY_PASSWORD "$REDIS_SECURITY_PASSWORD"
  echo "[secret-rotation] Rotated Redis security password pair"
fi

if [ "${ROTATE_RTDN:-0}" = "1" ]; then
  set_key "$backend_env" APP_SUBSCRIPTION_GOOGLE_PLAY_RTDN_SHARED_SECRET "$APP_SUBSCRIPTION_GOOGLE_PLAY_RTDN_SHARED_SECRET"
  echo "[secret-rotation] Rotated APP_SUBSCRIPTION_GOOGLE_PLAY_RTDN_SHARED_SECRET"
fi

rm -f "$secret_file"

wait_container_health() {
  container="$1"
  attempts="${2:-40}"
  for i in $(seq 1 "$attempts"); do
    status="$(docker inspect -f '{{.State.Health.Status}}' "$container" 2>/dev/null || true)"
    echo "[secret-rotation] $container health attempt $i/$attempts: ${status:-unknown}"
    if [ "$status" = "healthy" ]; then
      return 0
    fi
    sleep 3
  done
  echo "[secret-rotation] $container did not become healthy" >&2
  docker logs --tail=120 "$container" >&2 || true
  return 1
}

wait_backend_actuator() {
  attempts="${1:-40}"
  for i in $(seq 1 "$attempts"); do
    if docker exec vocabmaster-backend sh -lc 'curl -fsS http://localhost:8082/actuator/health' ; then
      return 0
    fi
    echo "[secret-rotation] backend actuator attempt $i/$attempts failed; waiting"
    sleep 3
  done
  docker logs --tail=160 vocabmaster-backend >&2 || true
  return 1
}

cd "$remote_deploy_dir"
if [ "${ROTATE_REDIS:-0}" = "1" ] || [ "${ROTATE_REDIS_SECURITY:-0}" = "1" ]; then
  docker compose -f docker-compose.app.yml up -d --force-recreate redis redis-security
fi
docker compose -f docker-compose.app.yml up -d --no-deps --force-recreate backend

if [ "${ROTATE_REDIS:-0}" = "1" ]; then
  wait_container_health vocabmaster-redis 40
fi
if [ "${ROTATE_REDIS_SECURITY:-0}" = "1" ]; then
  wait_container_health vocabmaster-redis-security 40
fi
wait_container_health vocabmaster-backend 40
wait_backend_actuator 40

echo "[secret-rotation] SUCCESS runtime secret rotation applied."
'@
    [System.IO.File]::WriteAllText($localRemoteScript, ($remoteScriptContent + "`n"), $utf8NoBom)

    Write-Host "[secret-rotation] Uploading temporary rotation payload without printing values."
    scp -q $localSecretFile "${SshTarget}:$remoteSecretFile"
    scp -q $localRemoteScript "${SshTarget}:$remoteScriptFile"

    Write-Host "[secret-rotation] Applying rotation on VPS."
    ssh -o BatchMode=yes -o ConnectTimeout=15 $SshTarget "chmod 600 '$remoteSecretFile' '$remoteScriptFile' && bash '$remoteScriptFile' '$remoteSecretFile' '$RemoteSecretsDir' '$RemoteDeployDir' '$RemoteBackupDir'; status=`$?; rm -f '$remoteSecretFile' '$remoteScriptFile'; exit `$status"
    if ($LASTEXITCODE -ne 0) {
        throw "[secret-rotation] Remote rotation failed."
    }

    Write-Host "[secret-rotation] SUCCESS"
} finally {
    Remove-Item -LiteralPath $localSecretFile -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $localRemoteScript -Force -ErrorAction SilentlyContinue
}
