param(
    [string]$Repository = "",
    [string]$Branch = "main",
    [string]$WorkflowFile = "backend-vps-deploy.yml",
    [string]$Label = "github-manual",
    [ValidateSet("true", "false")]
    [string]$NoCache = "false",
    [ValidateSet("true", "false")]
    [string]$SkipPublicSmoke = "false",
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

if ([string]::IsNullOrWhiteSpace($Repository)) {
    $Repository = Get-RepositoryFromOrigin
}
if ($Repository -notmatch "^[^/]+/[^/]+$") {
    throw "Repository must be in owner/repo format. Received '$Repository'."
}

Write-Host "[backend-dispatch] Repository: $Repository"
Write-Host "[backend-dispatch] Branch/ref: $Branch"
Write-Host "[backend-dispatch] Workflow: $WorkflowFile"
Write-Host "[backend-dispatch] Label: $Label"
Write-Host "[backend-dispatch] No cache: $NoCache"
Write-Host "[backend-dispatch] Skip public smoke: $SkipPublicSmoke"

if (-not $Execute) {
    Write-Host "[backend-dispatch] DRY RUN only. Re-run with -Execute and GITHUB_TOKEN/GH_TOKEN after VPS deploy secrets and environment protection are configured."
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

$body = @{
    ref    = $Branch
    inputs = @{
        label             = $Label
        no_cache          = $NoCache
        skip_public_smoke = $SkipPublicSmoke
    }
} | ConvertTo-Json -Depth 10

$url = "https://api.github.com/repos/$Repository/actions/workflows/$WorkflowFile/dispatches"
Invoke-RestMethod -Method Post -Uri $url -Headers $headers -ContentType "application/json" -Body $body

Write-Host "[backend-dispatch] SUCCESS workflow dispatch requested."

