param(
    [string]$Repository = "",
    [string]$EnvironmentName = "production-backend",
    [int]$WaitTimerMinutes = 0,
    [string[]]$ReviewerUsernames = @(),
    [string]$Token = "",
    [switch]$Execute
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

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

function Invoke-GitHubApi {
    param(
        [string]$Method,
        [string]$Uri,
        [hashtable]$Headers,
        [object]$Body = $null
    )

    if ($null -eq $Body) {
        return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers
    }

    $jsonBody = $Body | ConvertTo-Json -Depth 20
    return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -ContentType "application/json" -Body $jsonBody
}

if ([string]::IsNullOrWhiteSpace($Repository)) {
    $Repository = Get-RepositoryFromOrigin
}
if ($Repository -notmatch "^[^/]+/[^/]+$") {
    throw "Repository must be in owner/repo format. Received '$Repository'."
}
if ($WaitTimerMinutes -lt 0 -or $WaitTimerMinutes -gt 43200) {
    throw "WaitTimerMinutes must be between 0 and 43200."
}

Write-Host "[environment-protection] Repository: $Repository"
Write-Host "[environment-protection] Environment: $EnvironmentName"
Write-Host "[environment-protection] Wait timer minutes: $WaitTimerMinutes"
Write-Host "[environment-protection] Reviewer usernames: $($ReviewerUsernames -join ', ')"

if (-not $Execute) {
    Write-Host "[environment-protection] DRY RUN only. Re-run with -Execute and a repo-admin GITHUB_TOKEN/GH_TOKEN to apply."
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Token)) {
    $Token = $env:GITHUB_TOKEN
}
if ([string]::IsNullOrWhiteSpace($Token)) {
    $Token = $env:GH_TOKEN
}
if ([string]::IsNullOrWhiteSpace($Token)) {
    throw "A GitHub token is required for -Execute. Set GITHUB_TOKEN or GH_TOKEN, or pass -Token."
}

$headers = @{
    Accept                 = "application/vnd.github+json"
    Authorization          = "Bearer $Token"
    "X-GitHub-Api-Version" = "2022-11-28"
}

$deploymentBranchPolicy = @{
    protected_branches     = $true
    custom_branch_policies = $false
}

$body = [ordered]@{
    wait_timer               = $WaitTimerMinutes
    deployment_branch_policy = $deploymentBranchPolicy
}

if ($ReviewerUsernames.Count -gt 0) {
    $reviewers = @()
    foreach ($username in $ReviewerUsernames) {
        if ([string]::IsNullOrWhiteSpace($username)) {
            continue
        }
        $user = Invoke-GitHubApi -Method Get -Uri "https://api.github.com/users/$username" -Headers $headers
        $reviewers += @{
            type = "User"
            id   = [int64]$user.id
        }
    }
    if ($reviewers.Count -gt 0) {
        $body.reviewers = $reviewers
    }
}

$encodedEnvironment = [System.Uri]::EscapeDataString($EnvironmentName)
$url = "https://api.github.com/repos/$Repository/environments/$encodedEnvironment"
Invoke-GitHubApi -Method Put -Uri $url -Headers $headers -Body $body | Out-Null

Write-Host "[environment-protection] SUCCESS environment protection updated."

