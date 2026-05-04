param(
    [string]$ProjectName = "english-app-smoke",
    [int]$BackendPort = 18082,
    [int]$BackendSocketPort = 19092,
    [int]$PostgresPort = 15432,
    [int]$RedisPort = 16379,
    [switch]$KeepContainers
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$composeBase = Join-Path $repoRoot "docker-compose.yml"
$composeSmoke = Join-Path $repoRoot "docker-compose.smoke.yml"
$baseUrl = "http://localhost:$BackendPort"

# Keep compose interpolation deterministic for this smoke run.
if (-not $env:GROQ_API_KEY) {
    $env:GROQ_API_KEY = "smoke-test-key"
}
if (-not $env:APP_SECURITY_JWT_SECRET) {
    $env:APP_SECURITY_JWT_SECRET = "smoke-test-jwt-secret-smoke-test-jwt-secret-32"
}
$env:POSTGRES_PORT = "$PostgresPort"
$env:REDIS_PORT = "$RedisPort"
$env:BACKEND_HTTP_PORT = "$BackendPort"
$env:BACKEND_SOCKET_PORT = "$BackendSocketPort"

function Invoke-Compose {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    & docker compose -p $ProjectName -f $composeBase -f $composeSmoke @Args
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose failed: $($Args -join ' ')"
    }
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

function Wait-ApiReady {
    param([string]$Url, [int]$Attempts = 90, [int]$SleepSeconds = 2)
    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            $response = Invoke-RestMethod -Method Get -Uri "$Url/api"
            if ($response.message -eq "English Learning App API") {
                Write-Host "[smoke] API ready (attempt $i/$Attempts)"
                return
            }
        } catch {
            # Keep polling until timeout.
        }
        Start-Sleep -Seconds $SleepSeconds
    }
    throw "API not ready after $Attempts attempts: $Url/api"
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

function Invoke-PostgresScalar {
    param([string]$Sql)

    $output = Invoke-Compose @(
        "exec", "-T", "postgres",
        "psql", "-U", "postgres", "-d", "EnglishApp",
        "-t", "-A", "-c", $Sql
    )

    $lines = @($output | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ -ne "" })
    if ($lines.Count -eq 0) {
        return ""
    }

    return $lines[-1]
}

function Assert-CoreDbParity {
    $migrationDir = Join-Path $repoRoot "backend\src\main\resources\db\migration"
    $versions = @(
        Get-ChildItem -Path $migrationDir -Filter "V*.sql" |
            ForEach-Object {
                if ($_.BaseName -match "^V(\d+)__") {
                    [int]$matches[1]
                }
            } |
            Where-Object { $_ -ne $null }
    )

    Assert-True ($versions.Count -gt 0) "No Flyway migration files found in $migrationDir"
    $expectedLatest = ($versions | Measure-Object -Maximum).Maximum

    $currentLatestRaw = Invoke-PostgresScalar "SELECT COALESCE(MAX(version::int), 0) FROM flyway_schema_history WHERE success = true AND version ~ '^[0-9]+$';"
    [int]$currentLatest = 0
    if (-not [int]::TryParse($currentLatestRaw, [ref]$currentLatest)) {
        throw "Could not parse current Flyway version from DB output: '$currentLatestRaw'"
    }

    Assert-True ($currentLatest -eq $expectedLatest) "Flyway version mismatch. DB=$currentLatest, expected latest migration=$expectedLatest"

    $coreTables = @(
        "users",
        "subscription_plans",
        "payment_transactions",
        "words",
        "sentences",
        "word_reviews",
        "sentence_practices",
        "user_progress",
        "user_achievements"
    )

    foreach ($tableName in $coreTables) {
        $exists = Invoke-PostgresScalar "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='$tableName');"
        Assert-True ($exists -eq "t") "Missing core table: $tableName"
    }

    $requiredIndexes = @(
        "idx_sentence_practices_user_difficulty_created_date",
        "idx_word_reviews_review_date",
        "idx_words_user_learned_date",
        "idx_payment_transactions_user_created_at"
    )

    foreach ($indexName in $requiredIndexes) {
        $exists = Invoke-PostgresScalar "SELECT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='$indexName');"
        Assert-True ($exists -eq "t") "Missing required index: $indexName"
    }

    $hasWordUniq = Invoke-PostgresScalar @"
SELECT EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE schemaname='public'
      AND tablename='words'
      AND indexdef ILIKE '%UNIQUE INDEX%'
      AND indexdef ILIKE '%(user_id, english_word)%'
);
"@
    Assert-True ($hasWordUniq -eq "t") "Missing unique protection on words(user_id, english_word)."

    $hasTransactionUniq = Invoke-PostgresScalar @"
SELECT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'payment_transactions'::regclass
      AND contype = 'u'
      AND pg_get_constraintdef(oid) ILIKE '%(transaction_id)%'
);
"@
    Assert-True ($hasTransactionUniq -eq "t") "Missing unique constraint on payment_transactions(transaction_id)."

    Write-Host "[smoke] DB parity checks passed (schema, versions, indexes, constraints)."
}

$canCompose = $false

try {
    Test-DockerReady
    $canCompose = $true

    Write-Host "[smoke] Cleaning previous stack and volumes..."
    Invoke-Compose @("down", "--volumes", "--remove-orphans")

    Write-Host "[smoke] Starting clean stack (postgres + redis + backend)..."
    Invoke-Compose @("up", "-d", "--build", "postgres", "redis", "backend")

    Wait-ApiReady -Url $baseUrl
    Assert-CoreDbParity

    Write-Host "[smoke] Checking subscription plans endpoint..."
    $plans = @(Invoke-RestMethod -Method Get -Uri "$baseUrl/api/subscription/plans")
    Assert-True ($plans.Count -ge 1) "Expected seeded subscription plans, got 0."

    $email = "smoke_$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())@local.test"
    $password = "SmokePass123!"

    Write-Host "[smoke] Registering a test user..."
    $registerBody = @{
        email = $email
        password = $password
        displayName = "Smoke User"
    } | ConvertTo-Json

    $registerResponse = Invoke-RestMethod -Method Post -Uri "$baseUrl/api/auth/register" -ContentType "application/json" -Body $registerBody
    Assert-True ([bool]$registerResponse.success) "Registration failed."
    $userId = [long]$registerResponse.userId
    Assert-True ($userId -gt 0) "Registration did not return a valid userId."

    Write-Host "[smoke] Logging in with created user..."
    $loginBody = @{
        emailOrTag = $email
        password = $password
    } | ConvertTo-Json

    $loginResponse = Invoke-RestMethod -Method Post -Uri "$baseUrl/api/auth/login" -ContentType "application/json" -Body $loginBody
    Assert-True ([bool]$loginResponse.success) "Login failed."

    Write-Host "[smoke] Creating and reading a word as critical flow..."
    $createWordBody = @{
        englishWord = "smoke-word"
        turkishMeaning = "deneme"
        learnedDate = (Get-Date).ToString("yyyy-MM-dd")
        notes = "smoke-test"
        difficulty = "easy"
    } | ConvertTo-Json

    $createdWord = Invoke-RestMethod -Method Post -Uri "$baseUrl/api/words" -ContentType "application/json" -Headers @{ "X-User-Id" = "$userId" } -Body $createWordBody
    $wordId = [long]$createdWord.id
    Assert-True ($wordId -gt 0) "Word creation failed: no id returned."

    $words = @(Invoke-RestMethod -Method Get -Uri "$baseUrl/api/words" -Headers @{ "X-User-Id" = "$userId" })
    $found = @($words | Where-Object { [long]$_.id -eq $wordId }).Count -gt 0
    Assert-True $found "Created word was not returned by /api/words."

    Write-Host "[smoke] SUCCESS: clean DB smoke checks passed."
    Write-Host "[smoke] Base URL: $baseUrl"
    Write-Host "[smoke] UserId: $userId, WordId: $wordId, PlanCount: $($plans.Count)"
} finally {
    if ($canCompose -and -not $KeepContainers) {
        Write-Host "[smoke] Cleaning smoke stack..."
        try {
            Invoke-Compose @("down", "--volumes", "--remove-orphans")
        } catch {
            Write-Warning "[smoke] Cleanup failed: $($_.Exception.Message)"
        }
    } elseif ($canCompose) {
        Write-Host "[smoke] Keeping containers running (ProjectName=$ProjectName)."
    }
}
