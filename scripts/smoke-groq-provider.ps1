param(
    [string]$ApiKey = "",
    [string]$ApiUrl = "https://api.groq.com/openai/v1/chat/completions",
    [string[]]$Models = @("openai/gpt-oss-20b", "openai/gpt-oss-120b"),
    [switch]$JsonMode,
    [string]$DotEnvPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$apiKeySource = ""

if ([string]::IsNullOrWhiteSpace($DotEnvPath)) {
    $DotEnvPath = Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")).Path ".env"
}

function Read-DotEnvValue {
    param(
        [string]$Path,
        [string]$Name
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return ""
    }

    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match "^\s*#") {
            continue
        }
        if ($line -match "^\s*$([regex]::Escape($Name))=(.*)$") {
            return $matches[1].Trim().Trim('"').Trim("'")
        }
    }
    return ""
}

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    $ApiKey = [Environment]::GetEnvironmentVariable("GROQ_API_KEY")
    if (-not [string]::IsNullOrWhiteSpace($ApiKey)) {
        $apiKeySource = "environment"
    }
}

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    $ApiKey = Read-DotEnvValue -Path $DotEnvPath -Name "GROQ_API_KEY"
    if (-not [string]::IsNullOrWhiteSpace($ApiKey)) {
        $apiKeySource = ".env"
    }
} elseif ([string]::IsNullOrWhiteSpace($apiKeySource)) {
    $apiKeySource = "parameter"
}

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    throw "[groq-smoke] GROQ_API_KEY not found in env or .env. Pass -ApiKey or set env."
}

function Get-SecretFingerprint {
    param([string]$Value)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    return [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value))).Replace("-", "").Substring(0, 12)
}

function Invoke-GroqModelSmoke {
    param([string]$Model)

    $body = @{
        model = $Model
        messages = @(
            @{
                role = "system"
                content = "Reply with a tiny valid response."
            },
            @{
                role = "user"
                content = if ($JsonMode) { "Return ONLY JSON: {`"ok`":true}" } else { "Say OK." }
            }
        )
        temperature = 0
        # gpt-oss models are reasoning models: Groq bills/counts an internal
        # "reasoning" trace before the visible "content" field, even for a
        # trivial prompt (~25 reasoning tokens observed for "Say OK."). A
        # tight max_tokens (previously 32) lets reasoning consume the whole
        # budget and leaves content empty, failing this smoke check even
        # though the model/key are perfectly fine.
        max_tokens = 200
    }

    if ($JsonMode) {
        $body.response_format = @{
            type = "json_object"
        }
    }

    $headers = @{
        Authorization = "Bearer $ApiKey"
        "Content-Type" = "application/json"
    }

    $response = Invoke-WebRequest `
        -Uri $ApiUrl `
        -Method POST `
        -Headers $headers `
        -Body ($body | ConvertTo-Json -Depth 12) `
        -ContentType "application/json" `
        -UseBasicParsing `
        -SkipHttpErrorCheck `
        -TimeoutSec 45

    if ([int]$response.StatusCode -lt 200 -or [int]$response.StatusCode -ge 300) {
        $summary = $response.Content
        if ($summary.Length -gt 500) {
            $summary = $summary.Substring(0, 500)
        }
        throw "[groq-smoke] Model '$Model' failed with HTTP $($response.StatusCode): $summary"
    }

    $json = $response.Content | ConvertFrom-Json
    $content = [string]$json.choices[0].message.content
    if ([string]::IsNullOrWhiteSpace($content)) {
        throw "[groq-smoke] Model '$Model' returned empty content."
    }

    Write-Host "[groq-smoke] PASS model=$Model response_length=$($content.Length)"
}

Write-Host "[groq-smoke] Starting Groq provider smoke. Models=$($Models -join ', ') JsonMode=$JsonMode"
Write-Host "[groq-smoke] Key source=$apiKeySource length=$($ApiKey.Length) sha12=$(Get-SecretFingerprint -Value $ApiKey)"
foreach ($model in $Models) {
    Invoke-GroqModelSmoke -Model $model
}
Write-Host "[groq-smoke] SUCCESS"
