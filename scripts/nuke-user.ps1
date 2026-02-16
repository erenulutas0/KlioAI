param(
    [string]$Email = "",
    [long]$UserId = 0,
    [string]$Database = "EnglishApp",
    [string]$DbUser = "postgres",
    [string]$ProjectName = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$composeFile = Join-Path $repoRoot "docker-compose.yml"

# Ensure docker-compose interpolation has required vars even for exec-only flows.
if (-not $env:APP_SECURITY_JWT_SECRET -or $env:APP_SECURITY_JWT_SECRET.Trim().Length -eq 0) {
    $env:APP_SECURITY_JWT_SECRET = "dev-local-jwt-secret"
}
if (-not $env:POSTGRES_USER -or $env:POSTGRES_USER.Trim().Length -eq 0) {
    $env:POSTGRES_USER = $DbUser
}
if (-not $env:POSTGRES_PASSWORD -or $env:POSTGRES_PASSWORD.Trim().Length -eq 0) {
    $env:POSTGRES_PASSWORD = "postgres"
}

function Test-DockerReady {
    $dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
    if ($null -eq $dockerCmd) {
        throw "Docker CLI not found in PATH."
    }
    $null = & docker info --format "{{.ServerVersion}}" 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Docker daemon is not reachable. Start Docker Desktop and retry."
    }
}

function Invoke-Compose {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    $baseArgs = @("compose", "-f", $composeFile)
    if ($ProjectName -and $ProjectName.Trim().Length -gt 0) {
        $baseArgs = @("compose", "-p", $ProjectName, "-f", $composeFile)
    }

    & docker @baseArgs @Args
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose failed: $($Args -join ' ')"
    }
}

function Invoke-PostgresScalar {
    param([string]$Sql)

    $output = Invoke-Compose @(
        "exec", "-T", "postgres",
        "psql", "-U", $DbUser, "-d", $Database,
        "-t", "-A", "-c", $Sql
    )

    $lines = @($output | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ -ne "" })
    if ($lines.Count -eq 0) {
        return ""
    }
    return $lines[-1]
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

Test-DockerReady

if (($UserId -le 0) -and (-not $Email -or $Email.Trim().Length -eq 0)) {
    throw "Provide -UserId or -Email."
}

if ($UserId -le 0) {
    $safeEmail = $Email.Replace("'", "''")
    $raw = Invoke-PostgresScalar "SELECT id FROM users WHERE email = '$safeEmail' LIMIT 1;"
    [long]$parsed = 0
    if (-not [long]::TryParse($raw, [ref]$parsed)) {
        throw "User not found by email: $Email"
    }
    $UserId = $parsed
}

Assert-True ($UserId -gt 0) "Invalid user id: $UserId"

Write-Host "[nuke-user] Resetting learning data for userId=$UserId..."

$sqlTemplate = @'
BEGIN;

-- Core learning data
DELETE FROM sentence_practices WHERE user_id = __USER_ID__;
DELETE FROM word_reviews WHERE word_id IN (SELECT id FROM words WHERE user_id = __USER_ID__);
DELETE FROM sentences WHERE word_id IN (SELECT id FROM words WHERE user_id = __USER_ID__);
DELETE FROM words WHERE user_id = __USER_ID__;

-- Reset XP/streak (ensure a row exists; don't assume a UNIQUE(user_id) constraint)
UPDATE user_progress
SET total_xp = 0,
    level = 1,
    current_streak = 0,
    longest_streak = 0,
    last_activity_date = NULL,
    updated_at = now()
WHERE user_id = __USER_ID__;

INSERT INTO user_progress (user_id, total_xp, level, current_streak, longest_streak, last_activity_date, created_at, updated_at)
SELECT __USER_ID__, 0, 1, 0, 0, NULL, now(), now()
WHERE NOT EXISTS (SELECT 1 FROM user_progress WHERE user_id = __USER_ID__);

-- Optional tables (if present)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'user_daily_stats'
  ) THEN
    EXECUTE 'DELETE FROM user_daily_stats WHERE user_id = __USER_ID__';
  END IF;
END
$$;

COMMIT;
'@

$sql = $sqlTemplate.Replace('__USER_ID__', $UserId.ToString())

$null = Invoke-Compose @(
    "exec", "-T", "postgres",
    "psql", "-U", $DbUser, "-d", $Database,
    "-v", "ON_ERROR_STOP=1",
    "-c", $sql
)

$wordsLeft = Invoke-PostgresScalar "SELECT COUNT(*) FROM words WHERE user_id = $UserId;"
$practiceLeft = Invoke-PostgresScalar "SELECT COUNT(*) FROM sentence_practices WHERE user_id = $UserId;"
$xp = Invoke-PostgresScalar "SELECT total_xp FROM user_progress WHERE user_id = $UserId;"
$streak = Invoke-PostgresScalar "SELECT current_streak FROM user_progress WHERE user_id = $UserId;"

Write-Host "[nuke-user] Done."
Write-Host "[nuke-user] words=$wordsLeft, sentence_practices=$practiceLeft, total_xp=$xp, current_streak=$streak"
