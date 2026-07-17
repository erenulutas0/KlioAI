param(
    [string]$Root = "",
    [switch]$IncludeLocalSecretFiles,
    [switch]$FailOnWarnings
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
} else {
    $Root = (Resolve-Path $Root).Path
}

$excludedDirectories = @(
    ".git",
    ".dart_tool",
    ".gradle",
    ".idea",
    ".m2-repo",
    "build",
    "coverage",
    "node_modules",
    "target"
)

if (-not $IncludeLocalSecretFiles) {
    $excludedDirectories += "secrets"
}

$includedExtensions = @(
    "",
    ".conf",
    ".css",
    ".dart",
    ".env",
    ".example",
    ".gradle",
    ".html",
    ".java",
    ".js",
    ".json",
    ".kt",
    ".md",
    ".properties",
    ".ps1",
    ".sh",
    ".sql",
    ".swift",
    ".ts",
    ".txt",
    ".xml",
    ".yaml",
    ".yml"
)

$includedNames = @(
    ".env.example",
    "Caddyfile",
    "Dockerfile"
)

$patterns = @(
    @{
        Name = "GroqApiKey"
        Severity = "HIGH"
        Regex = [regex]'gsk_[A-Za-z0-9_-]{20,}'
    },
    @{
        Name = "JwtSecretAssignment"
        Severity = "HIGH"
        Regex = [regex]'APP_SECURITY_JWT_SECRET\s*=\s*(?!\$\{|\$env:|<|CHANGE_ME|changeme|example|dummy|your-|"|'''')\S+'
    },
    @{
        Name = "GoogleServiceAccountPrivateKeyJson"
        Severity = "HIGH"
        Regex = [regex]'"private_key"\s*:\s*"-----BEGIN PRIVATE KEY-----'
    },
    @{
        Name = "PemPrivateKey"
        Severity = "HIGH"
        Regex = [regex]'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'
    },
    @{
        Name = "GoogleApiKey"
        Severity = "WARN"
        Regex = [regex]'AIza[0-9A-Za-z_-]{35}'
    }
)

function Get-RelativePath {
    param([string]$Path)

    $relative = [System.IO.Path]::GetRelativePath($Root, $Path)
    return $relative.Replace("\", "/")
}

function Test-IsExcludedPath {
    param([string]$Path)

    $relative = Get-RelativePath -Path $Path
    $segments = $relative -split "[/\\]"
    foreach ($segment in $segments) {
        if ($excludedDirectories -contains $segment) {
            return $true
        }
    }
    return $false
}

function Test-IsIncludedTextFile {
    param([System.IO.FileInfo]$File)

    if (-not $IncludeLocalSecretFiles -and $File.Name -eq ".env") {
        return $false
    }

    if ($includedNames -contains $File.Name) {
        return $true
    }
    return $includedExtensions -contains $File.Extension
}

function Test-IsAllowedFinding {
    param(
        [string]$PatternName,
        [string]$RelativePath
    )

    if ($PatternName -eq "PemPrivateKey" -and $RelativePath -eq "scripts/scan-repo-secrets.ps1") {
        return $true
    }

    if ($PatternName -eq "PemPrivateKey" -and $RelativePath -eq "backend/src/main/java/com/ingilizce/calismaapp/service/GooglePlaySubscriptionVerificationService.java") {
        return $true
    }

    if ($PatternName -eq "JwtSecretAssignment" -and $RelativePath -eq "scripts/rotate-prod-runtime-secrets-vps.ps1") {
        return $true
    }

    return $false
}

$findings = New-Object System.Collections.Generic.List[object]

Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
    Where-Object { -not (Test-IsExcludedPath -Path $_.FullName) } |
    Where-Object { Test-IsIncludedTextFile -File $_ } |
    ForEach-Object {
        $file = $_
        $relative = Get-RelativePath -Path $file.FullName
        $lineNumber = 0

        try {
            Get-Content -LiteralPath $file.FullName -ErrorAction Stop | ForEach-Object {
                $lineNumber++
                $line = $_
                foreach ($pattern in $patterns) {
                    if ($pattern.Regex.IsMatch($line)) {
                        if (Test-IsAllowedFinding -PatternName $pattern.Name -RelativePath $relative) {
                            continue
                        }
                        $findings.Add([pscustomobject]@{
                            Severity = $pattern.Severity
                            Pattern = $pattern.Name
                            Path = $relative
                            Line = $lineNumber
                        }) | Out-Null
                    }
                }
            }
        } catch {
            Write-Warning ("Skipped unreadable file {0}: {1}" -f $relative, $_.Exception.Message)
        }
    }

$highFindings = @($findings | Where-Object { $_.Severity -eq "HIGH" })
$warningFindings = @($findings | Where-Object { $_.Severity -eq "WARN" })

if ($findings.Count -eq 0) {
    Write-Host "[secret-scan] PASS: no configured secret patterns found."
    exit 0
}

foreach ($finding in ($findings | Sort-Object Severity, Pattern, Path, Line)) {
    Write-Host ("[secret-scan] {0}: {1} at {2}:{3}" -f $finding.Severity, $finding.Pattern, $finding.Path, $finding.Line)
}

if ($highFindings.Count -gt 0) {
    Write-Error ("[secret-scan] FAILED: {0} high-risk finding(s). Values are intentionally not printed." -f $highFindings.Count)
    exit 1
}

if ($FailOnWarnings -and $warningFindings.Count -gt 0) {
    Write-Error ("[secret-scan] FAILED: {0} warning finding(s) and -FailOnWarnings was set." -f $warningFindings.Count)
    exit 1
}

Write-Host ("[secret-scan] PASS: no high-risk secrets found. Warning findings: {0}." -f $warningFindings.Count)
exit 0
