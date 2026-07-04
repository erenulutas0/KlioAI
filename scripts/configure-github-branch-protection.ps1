param(
    [string]$Repository = "",
    [string]$Branch = "main",
    [string[]]$RequiredCheckContexts = @(
        "db-readiness",
        "flutter-quality",
        "trivy-fs"
    ),
    [string]$Token = "",
    [switch]$Execute
)

$ErrorActionPreference = "Stop"

function Get-RepositoryFromOrigin {
    $remote = git remote get-url origin 2>$null
    if (-not $remote) {
        throw "Could not infer repository because git remote 'origin' is not configured. Pass -Repository owner/repo."
    }

    if ($remote -match "github\.com[:/]([^/]+)/([^/.]+)(?:\.git)?$") {
        return "$($Matches[1])/$($Matches[2])"
    }

    throw "Could not infer GitHub owner/repo from origin '$remote'. Pass -Repository owner/repo."
}

if ([string]::IsNullOrWhiteSpace($Repository)) {
    $Repository = Get-RepositoryFromOrigin
}

if ($Repository -notmatch "^[^/]+/[^/]+$") {
    throw "Repository must be in owner/repo format. Received '$Repository'."
}

if (-not $RequiredCheckContexts -or $RequiredCheckContexts.Count -eq 0) {
    throw "At least one required check context is required."
}

if ([string]::IsNullOrWhiteSpace($Token)) {
    $Token = $env:GITHUB_TOKEN
}
if ([string]::IsNullOrWhiteSpace($Token)) {
    $Token = $env:GH_TOKEN
}

$payload = [ordered]@{
    required_status_checks = [ordered]@{
        strict   = $true
        contexts = $RequiredCheckContexts
    }
    enforce_admins                 = $false
    required_pull_request_reviews  = [ordered]@{
        dismiss_stale_reviews           = $true
        require_code_owner_reviews      = $false
        required_approving_review_count = 1
    }
    restrictions                     = $null
    required_linear_history          = $false
    allow_force_pushes               = $false
    allow_deletions                  = $false
    required_conversation_resolution = $true
}

$json = $payload | ConvertTo-Json -Depth 10
$url = "https://api.github.com/repos/$Repository/branches/$Branch/protection"

Write-Host "[branch-protection] Repository: $Repository"
Write-Host "[branch-protection] Branch: $Branch"
Write-Host "[branch-protection] Required contexts:"
foreach ($context in $RequiredCheckContexts) {
    Write-Host "  - $context"
}
Write-Host "[branch-protection] Pull request reviews: 1 approval, stale approvals dismissed"
Write-Host "[branch-protection] Force pushes: disabled"
Write-Host "[branch-protection] Deletions: disabled"
Write-Host "[branch-protection] Conversation resolution: required"

if (-not $Execute) {
    Write-Host "[branch-protection] DRY RUN only. Re-run with -Execute and a GITHUB_TOKEN/GH_TOKEN to apply."
    Write-Host "[branch-protection] API endpoint: $url"
    Write-Host "[branch-protection] Payload:"
    Write-Host $json
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Token)) {
    throw "A GitHub token is required for -Execute. Set GITHUB_TOKEN or GH_TOKEN, or pass -Token."
}

$headers = @{
    Accept                 = "application/vnd.github+json"
    Authorization          = "Bearer $Token"
    "X-GitHub-Api-Version" = "2022-11-28"
}

Write-Host "[branch-protection] Applying branch protection through GitHub API."
$response = Invoke-RestMethod -Method Put -Uri $url -Headers $headers -ContentType "application/json" -Body $json

Write-Host "[branch-protection] SUCCESS branch protection updated."
Write-Host "[branch-protection] Protected URL: $($response.url)"
