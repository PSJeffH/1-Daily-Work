#requires -Modules ExchangeOnlineManagement
<#+
.SYNOPSIS
    Exports distribution group details from on-premises Exchange and Exchange Online.
.DESCRIPTION
    Collects distribution groups and outputs properties like Name, DisplayName,
    Department, Notes, ManagedBy, Title and member count. Results are exported
    to CSV files. Ensure you have an on-prem Exchange session and are connected
    to Exchange Online before running the script.
.PARAMETER OutputDirectory
    Directory where CSV files will be written. Defaults to the script directory.
#>

[CmdletBinding()]
param(
    [string]$OutputDirectory = $PSScriptRoot
)

if (-not (Test-Path $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

$properties = @(
    'Name','DisplayName','Alias','PrimarySmtpAddress','Department','Notes',
    'ManagedBy','Title','MemberCount','GroupType'
)

$onPremResults = @()
try {
    $onPremGroups = Get-DistributionGroup -ResultSize Unlimited
    foreach ($g in $onPremGroups) {
        $members = Get-DistributionGroupMember -Identity $g.Identity -ResultSize Unlimited -ErrorAction SilentlyContinue
        $managerName = $null
        if ($g.ManagedBy) {
            try { $managerName = (Get-Recipient $g.ManagedBy).DisplayName } catch {}
        }
        $onPremResults += [pscustomobject]@{
            Name              = $g.Name
            DisplayName       = $g.DisplayName
            Alias             = $g.Alias
            PrimarySmtpAddress = $g.PrimarySmtpAddress
            Department        = $g.Department
            Notes             = $g.Notes
            ManagedBy         = $managerName
            Title             = $g.Title
            MemberCount       = $members.Count
            GroupType         = 'OnPrem'
        }
    }
} catch {
    Write-Warning "Failed to retrieve on-premises distribution groups: $_"
}

$onlineResults = @()
try {
    $onlineGroups = Get-DistributionGroup -ResultSize Unlimited
    foreach ($g in $onlineGroups) {
        $members = Get-DistributionGroupMember -Identity $g.Identity -ResultSize Unlimited -ErrorAction SilentlyContinue
        $managerName = $null
        if ($g.ManagedBy) {
            try { $managerName = (Get-Recipient $g.ManagedBy).DisplayName } catch {}
        }
        $onlineResults += [pscustomobject]@{
            Name              = $g.Name
            DisplayName       = $g.DisplayName
            Alias             = $g.Alias
            PrimarySmtpAddress = $g.PrimarySmtpAddress
            Department        = $g.Department
            Notes             = $g.Notes
            ManagedBy         = $managerName
            Title             = $g.Title
            MemberCount       = $members.Count
            GroupType         = 'ExchangeOnline'
        }
    }
} catch {
    Write-Warning "Failed to retrieve Exchange Online distribution groups: $_"
}

if ($onPremResults) {
    $onPremCsv = Join-Path $OutputDirectory 'DistributionGroups-OnPrem.csv'
    $onPremResults | Select-Object $properties | Export-Csv -NoTypeInformation -Path $onPremCsv
    Write-Host "Saved on-premises results to $onPremCsv" -ForegroundColor Green
}

if ($onlineResults) {
    $onlineCsv = Join-Path $OutputDirectory 'DistributionGroups-Online.csv'
    $onlineResults | Select-Object $properties | Export-Csv -NoTypeInformation -Path $onlineCsv
    Write-Host "Saved Exchange Online results to $onlineCsv" -ForegroundColor Green
}
