param(
    [string]$ProjectName = "flutter-project-main"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($env:APP_SECURITY_JWT_SECRET)) {
    $env:APP_SECURITY_JWT_SECRET = "local-dev-placeholder"
    Write-Host "[db-parity] INFO: APP_SECURITY_JWT_SECRET not set; using temporary placeholder for compose parsing."
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$composeBase = Join-Path $repoRoot "docker-compose.yml"
$composeSmoke = Join-Path $repoRoot "docker-compose.smoke.yml"

function Invoke-Compose {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    & docker compose -p $ProjectName -f $composeBase -f $composeSmoke @Args
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose failed: $($Args -join ' ')"
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

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

Write-Host "[db-parity] Checking running stack (project=$ProjectName)..."
$null = Invoke-Compose @("ps")

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

Write-Host "[db-parity] SUCCESS: parity checks passed."
