param(
    [string]$BaseUrl = "https://api.klioai.app",
    [Parameter(Mandatory = $true)]
    [string]$AccessToken,
    [long]$UserId = 0,
    [string]$Message = "Please reply with one short friendly English sentence.",
    [switch]$SkipTokenConsumingChecks
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Decode-JwtUserId {
    param([string]$Token)
    try {
        $parts = $Token.Split(".")
        if ($parts.Length -lt 2) {
            return 0
        }
        $payload = $parts[1].Replace("-", "+").Replace("_", "/")
        switch ($payload.Length % 4) {
            2 { $payload += "==" }
            3 { $payload += "=" }
        }
        $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload))
        $claims = $json | ConvertFrom-Json
        foreach ($name in @("userId", "uid", "sub", "id")) {
            if ($null -ne $claims.$name) {
                $parsed = 0L
                if ([long]::TryParse([string]$claims.$name, [ref]$parsed)) {
                    return $parsed
                }
            }
        }
    } catch {
        return 0
    }
    return 0
}

function Invoke-KlioApi {
    param(
        [ValidateSet("GET", "POST")]
        [string]$Method,
        [string]$Uri,
        [hashtable]$Headers = @{},
        [object]$Body = $null
    )

    $params = @{
        Method             = $Method
        Uri                = $Uri
        Headers            = $Headers
        UseBasicParsing    = $true
        SkipHttpErrorCheck = $true
        TimeoutSec         = 45
    }

    if ($null -ne $Body) {
        $params.ContentType = "application/json"
        $params.Body = ($Body | ConvertTo-Json -Depth 10)
    }

    $response = Invoke-WebRequest @params
    $json = $null
    if (-not [string]::IsNullOrWhiteSpace($response.Content)) {
        try {
            $json = $response.Content | ConvertFrom-Json -AsHashtable
        } catch {
            $json = $null
        }
    }

    [PSCustomObject]@{
        StatusCode = [int]$response.StatusCode
        Json       = $json
        Raw        = $response.Content
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

if ($UserId -le 0) {
    $UserId = Decode-JwtUserId -Token $AccessToken
}

Assert-True ($UserId -gt 0) "UserId could not be resolved. Pass -UserId explicitly."

$root = $BaseUrl.TrimEnd("/")
$headers = @{
    "Authorization" = "Bearer $AccessToken"
    "X-User-Id"     = "$UserId"
    "Content-Type"  = "application/json"
}

Write-Host "[ai-chat-smoke] BaseUrl=$root UserId=$UserId"

$health = Invoke-KlioApi -Method GET -Uri "$root/actuator/health"
Assert-True ($health.StatusCode -eq 200) "health expected HTTP 200, got $($health.StatusCode)"
Write-Host "[ai-chat-smoke] PASS health"

$quota = Invoke-KlioApi -Method GET -Uri "$root/api/chatbot/quota/status" -Headers $headers
Assert-True ($quota.StatusCode -eq 200) "quota/status expected HTTP 200, got $($quota.StatusCode)"
Assert-True ($null -ne $quota.Json) "quota/status did not return JSON"
$aiAccessEnabled = if ($quota.Json.ContainsKey("aiAccessEnabled")) { [bool]$quota.Json["aiAccessEnabled"] } else { $false }
$planCode = if ($quota.Json.ContainsKey("planCode")) { [string]$quota.Json["planCode"] } else { "UNKNOWN" }
Assert-True $aiAccessEnabled "quota/status says aiAccessEnabled=false for plan $planCode"
Write-Host "[ai-chat-smoke] PASS quota plan=$planCode aiAccessEnabled=$aiAccessEnabled"

if ($SkipTokenConsumingChecks) {
    Write-Host "[ai-chat-smoke] SKIP chatbot/chat token-consuming check"
    Write-Host "[ai-chat-smoke] SUCCESS"
    exit 0
}

$chat = Invoke-KlioApi -Method POST -Uri "$root/api/chatbot/chat" -Headers $headers -Body @{
    message = $Message
    scenario = "smoke"
}

Assert-True ($chat.StatusCode -eq 200) "chatbot/chat expected HTTP 200, got $($chat.StatusCode). Body: $($chat.Raw)"
Assert-True ($null -ne $chat.Json) "chatbot/chat did not return JSON"
$reply = if ($chat.Json.ContainsKey("response")) { [string]$chat.Json["response"] } else { "" }
Assert-True (-not [string]::IsNullOrWhiteSpace($reply)) "chatbot/chat returned an empty response"

Write-Host "[ai-chat-smoke] PASS chatbot/chat response_length=$($reply.Length)"

$sentences = Invoke-KlioApi -Method POST -Uri "$root/api/chatbot/generate-sentences" -Headers $headers -Body @{
    word = "focus"
    levels = @("B1")
    lengths = @("medium")
}

Assert-True ($sentences.StatusCode -eq 200) "generate-sentences expected HTTP 200, got $($sentences.StatusCode). Body: $($sentences.Raw)"
Assert-True ($null -ne $sentences.Json) "generate-sentences did not return JSON"
$count = if ($sentences.Json.ContainsKey("count")) { [int]$sentences.Json["count"] } else { 0 }
Assert-True ($count -ge 1) "generate-sentences returned no sentences"
Write-Host "[ai-chat-smoke] PASS generate-sentences count=$count"
Write-Host "[ai-chat-smoke] SUCCESS"
