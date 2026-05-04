[CmdletBinding()]
param(
    [string]$OutputPath = ".\\DC-Upgrade-Precheck",
    [switch]$SkipEventLogs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function New-OutputFolder {
    param([string]$Path)
    if (-not (Test-Path -Path $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Test-Module {
    param([string]$Name)
    if (-not (Get-Module -ListAvailable -Name $Name)) {
        throw "Required module '$Name' is not available. Install RSAT/AD PowerShell tools first."
    }
}

Test-Module -Name ActiveDirectory
Import-Module ActiveDirectory

New-OutputFolder -Path $OutputPath
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

Write-Info "Collecting domain and DC inventory"
$domain = Get-ADDomain
$forest = Get-ADForest
$dcs = Get-ADDomainController -Filter * | Sort-Object HostName

$inventory = foreach ($dc in $dcs) {
    [PSCustomObject]@{
        HostName              = $dc.HostName
        Site                  = $dc.Site
        IPv4Address           = $dc.IPv4Address
        IsGlobalCatalog       = $dc.IsGlobalCatalog
        OperatingSystem       = $dc.OperatingSystem
        OperatingSystemVersion= $dc.OperatingSystemVersion
    }
}

$inventory | Export-Csv -NoTypeInformation -Path (Join-Path $OutputPath "dc-inventory-$timestamp.csv")

Write-Info "Collecting FSMO role owners"
$fsm = [PSCustomObject]@{
    DomainNamingMaster = $forest.DomainNamingMaster
    SchemaMaster       = $forest.SchemaMaster
    RIDMaster          = $domain.RIDMaster
    PDCEmulator        = $domain.PDCEmulator
    InfrastructureMaster = $domain.InfrastructureMaster
}
$fsm | Export-Csv -NoTypeInformation -Path (Join-Path $OutputPath "fsmo-owners-$timestamp.csv")

Write-Info "Running dcdiag summary"
$dcdiagOut = Join-Path $OutputPath "dcdiag-$timestamp.txt"
cmd /c "dcdiag /e /q" | Out-File -FilePath $dcdiagOut -Encoding utf8

Write-Info "Running repadmin summary"
$repadminOut = Join-Path $OutputPath "repadmin-replsummary-$timestamp.txt"
cmd /c "repadmin /replsummary" | Out-File -FilePath $repadminOut -Encoding utf8

if (-not $SkipEventLogs) {
    Write-Info "Collecting recent critical AD/DNS/system events (last 7 days)"
    $start = (Get-Date).AddDays(-7)
    $logs = @('Directory Service','DNS Server','System')
    $events = foreach ($log in $logs) {
        try {
            Get-WinEvent -FilterHashtable @{LogName=$log; StartTime=$start; Level=1,2}
        }
        catch {
            Write-Warning "Unable to read log '$log': $($_.Exception.Message)"
        }
    }
    $events |
        Select-Object TimeCreated, Id, LevelDisplayName, LogName, MachineName, ProviderName, Message |
        Export-Csv -NoTypeInformation -Path (Join-Path $OutputPath "critical-events-$timestamp.csv")
}

$summary = [PSCustomObject]@{
    ForestName            = $forest.Name
    DomainName            = $domain.DNSRoot
    DomainMode            = $domain.DomainMode
    ForestMode            = $forest.ForestMode
    TotalDomainControllers= $dcs.Count
    Server2016DCs         = ($inventory | Where-Object { $_.OperatingSystem -match '2016' }).Count
    OutputFolder          = (Resolve-Path $OutputPath).Path
    CollectedAtUtc        = (Get-Date).ToUniversalTime().ToString('u')
}

$summary | Format-List | Out-String | Tee-Object -FilePath (Join-Path $OutputPath "precheck-summary-$timestamp.txt")
Write-Info "Precheck complete. Output saved to $OutputPath"
