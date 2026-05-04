[CmdletBinding()]
param(
    [string]$OutputPath = ".\\DC-Upgrade-Postcheck"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Green
}

function New-OutputFolder {
    param([string]$Path)
    if (-not (Test-Path -Path $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

Import-Module ActiveDirectory
New-OutputFolder -Path $OutputPath
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

Write-Info "Collecting post-upgrade DC inventory"
$dcs = Get-ADDomainController -Filter * | Sort-Object HostName
$inventory = $dcs | Select-Object HostName, Site, IPv4Address, IsGlobalCatalog, OperatingSystem, OperatingSystemVersion
$inventory | Export-Csv -NoTypeInformation -Path (Join-Path $OutputPath "post-dc-inventory-$timestamp.csv")

Write-Info "Checking for remaining Windows Server 2016 DCs"
$legacy = $inventory | Where-Object { $_.OperatingSystem -match '2016' }
$legacy | Export-Csv -NoTypeInformation -Path (Join-Path $OutputPath "remaining-2016-dcs-$timestamp.csv")

Write-Info "Running health commands"
cmd /c "dcdiag /e /q" | Out-File -FilePath (Join-Path $OutputPath "post-dcdiag-$timestamp.txt") -Encoding utf8
cmd /c "repadmin /replsummary" | Out-File -FilePath (Join-Path $OutputPath "post-repadmin-replsummary-$timestamp.txt") -Encoding utf8

Write-Info "Sampling authentication-related events from last 48 hours"
$start = (Get-Date).AddHours(-48)
$authEvents = Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$start; Level=1,2} |
    Where-Object { $_.ProviderName -in @('NETLOGON','Microsoft-Windows-GroupPolicy') }

$authEvents |
    Select-Object TimeCreated, Id, LevelDisplayName, MachineName, ProviderName, Message |
    Export-Csv -NoTypeInformation -Path (Join-Path $OutputPath "auth-events-48h-$timestamp.csv")

$summary = [PSCustomObject]@{
    TotalDomainControllers = $dcs.Count
    RemainingServer2016DCs = $legacy.Count
    PostCheckUtc           = (Get-Date).ToUniversalTime().ToString('u')
    OutputFolder           = (Resolve-Path $OutputPath).Path
}

$summary | Format-List | Out-String | Tee-Object -FilePath (Join-Path $OutputPath "postcheck-summary-$timestamp.txt")

if ($legacy.Count -gt 0) {
    Write-Warning "Postcheck complete but legacy 2016 DCs remain. Review remaining-2016-dcs report."
}
else {
    Write-Info "Postcheck complete. No Windows Server 2016 DCs detected."
}
