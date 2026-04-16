param(
    [string]$ProjectName = "flutter-project-main",
    [string]$BackendService = "backend",
    [string]$RedisService = "redis",
    [string]$SecurityRedisService = "redis-security",
    [string]$RedisHost = "app-redis-main",
    [string]$SecurityRedisHost = "app-redis-security"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-ComposeContainerId {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Project,
        [Parameter(Mandatory = $true)]
        [string]$Service
    )

    $lines = & docker ps `
        --filter "label=com.docker.compose.project=$Project" `
        --filter "label=com.docker.compose.service=$Service" `
        --format "{{.ID}}"
    if ($LASTEXITCODE -ne 0) {
        throw "docker ps failed while looking up service '$Service'."
    }

    [array]$ids = @(
        $lines |
            ForEach-Object { $_.ToString().Trim() } |
            Where-Object { $_ -ne "" }
    )

    if ($ids.Count -eq 0) {
        throw "Service '$Service' is not running for project '$Project'."
    }
    if ($ids.Count -gt 1) {
        throw "Service '$Service' has multiple running containers for project '$Project'."
    }

    return $ids[0]
}

function Get-NetworkMap {
    param([string]$ContainerId)
    $json = & docker inspect $ContainerId --format "{{json .NetworkSettings.Networks}}"
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($json)) {
        throw "Failed to inspect networks for container '$ContainerId'."
    }
    return ($json | ConvertFrom-Json)
}

function Get-PrimaryProjectNetworkName {
    param(
        [string]$Project,
        [object]$NetworkMap
    )

    [array]$names = @($NetworkMap.PSObject.Properties | ForEach-Object { $_.Name })
    if ($names.Count -eq 0) {
        throw "Container has no attached networks."
    }

    [array]$projectMatches = @($names | Where-Object { $_ -like "$Project*" })
    if ($projectMatches.Count -eq 1) {
        return $projectMatches[0]
    }
    if ($projectMatches.Count -gt 1) {
        [array]$appNetwork = @($projectMatches | Where-Object { $_ -like "*_app-network" })
        if ($appNetwork.Count -eq 1) {
            return $appNetwork[0]
        }
        throw "Could not uniquely determine project network from: $($projectMatches -join ', ')"
    }

    if ($names.Count -eq 1) {
        return $names[0]
    }

    throw "Could not determine project network. Attached networks: $($names -join ', ')"
}

function Get-ContainerIpOnNetwork {
    param(
        [string]$ContainerId,
        [string]$NetworkName
    )

    $map = Get-NetworkMap -ContainerId $ContainerId
    $entry = $map.PSObject.Properties | Where-Object { $_.Name -eq $NetworkName } | Select-Object -First 1
    if ($null -eq $entry) {
        throw "Container '$ContainerId' is not attached to network '$NetworkName'."
    }

    $ip = $entry.Value.IPAddress
    if ([string]::IsNullOrWhiteSpace($ip)) {
        throw "Container '$ContainerId' has no IP on network '$NetworkName'."
    }
    return $ip
}

function Resolve-HostFromContainer {
    param(
        [string]$ContainerId,
        [string]$HostName
    )

    $output = & docker exec $ContainerId sh -lc "getent hosts $HostName || true"
    if ($LASTEXITCODE -ne 0) {
        throw "docker exec failed while resolving '$Host'."
    }

    [array]$lines = @(
        $output |
            ForEach-Object { $_.ToString().Trim() } |
            Where-Object { $_ -ne "" }
    )

    return $lines
}

function Assert-SingleHostResolution {
    param(
        [string]$HostName,
        [string[]]$Lines
    )

    if ($Lines.Count -eq 0) {
        throw "Host '$HostName' does not resolve from backend container."
    }
    if ($Lines.Count -gt 1) {
        throw "Host '$HostName' resolves to multiple records from backend container: $($Lines -join ' | ')"
    }
}

function Get-ResolvedIpFromGetentLine {
    param([string]$Line)
    [array]$parts = @($Line -split "\s+" | Where-Object { $_ -ne "" })
    if ($parts.Count -lt 1) {
        throw "Unexpected getent output line: '$Line'"
    }
    return $parts[0]
}

Write-Host "[runtime-isolation] Checking compose project '$ProjectName'..."

$backendId = Get-ComposeContainerId -Project $ProjectName -Service $BackendService
$redisId = Get-ComposeContainerId -Project $ProjectName -Service $RedisService
$securityRedisId = Get-ComposeContainerId -Project $ProjectName -Service $SecurityRedisService

$backendNetworks = Get-NetworkMap -ContainerId $backendId
$projectNetwork = Get-PrimaryProjectNetworkName -Project $ProjectName -NetworkMap $backendNetworks

$expectedRedisIp = Get-ContainerIpOnNetwork -ContainerId $redisId -NetworkName $projectNetwork
$expectedSecurityRedisIp = Get-ContainerIpOnNetwork -ContainerId $securityRedisId -NetworkName $projectNetwork

[array]$redisLines = @(Resolve-HostFromContainer -ContainerId $backendId -HostName $RedisHost)
[array]$securityLines = @(Resolve-HostFromContainer -ContainerId $backendId -HostName $SecurityRedisHost)

Assert-SingleHostResolution -HostName $RedisHost -Lines $redisLines
Assert-SingleHostResolution -HostName $SecurityRedisHost -Lines $securityLines

$resolvedRedisIp = Get-ResolvedIpFromGetentLine -Line $redisLines[0]
$resolvedSecurityRedisIp = Get-ResolvedIpFromGetentLine -Line $securityLines[0]

if ($resolvedRedisIp -ne $expectedRedisIp) {
    throw "Host '$RedisHost' resolved to '$resolvedRedisIp', expected '$expectedRedisIp' for project redis service."
}
if ($resolvedSecurityRedisIp -ne $expectedSecurityRedisIp) {
    throw "Host '$SecurityRedisHost' resolved to '$resolvedSecurityRedisIp', expected '$expectedSecurityRedisIp' for project redis-security service."
}

Write-Host "[runtime-isolation] PASS: backend host resolution is deterministic."
Write-Host "[runtime-isolation] INFO: network=$projectNetwork redis=$resolvedRedisIp redis-security=$resolvedSecurityRedisIp"
