<#
.SYNOPSIS
    Audits SharePoint Online sites and exports the results to Excel.

.DESCRIPTION
    Connects to the SharePoint Online admin site using the PnP.PowerShell
    module and gathers details about each site collection, including team
    sites. The output includes the site URL, title, template, owners,
    sharing configuration, storage usage and other data useful for planning
    a site rename or migration.  External access information is also
    gathered to determine whether any guest users have access.

    The ImportExcel module is required for exporting to an Excel file.
#>

param(
    [Parameter(Mandatory)]
    [string]$AdminUrl,

    [string]$OutputPath = 'C:\AuditReports'
)

Import-Module PnP.PowerShell
Import-Module ImportExcel

$timestamp = Get-Date -Format 'yyyyMMdd-HHmm'
$excelFile = Join-Path $OutputPath "SharePointSiteAudit-$timestamp.xlsx"

if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

# Connect interactively to the tenant admin site and keep the connection
Connect-PnPOnline -Url $AdminUrl -Interactive
$adminConn = Get-PnPConnection

# Retrieve all site collections except personal OneDrive sites
$sites = Get-PnPTenantSite -IncludeOneDriveSites:$false -Detailed

$results = foreach ($s in $sites) {
    Write-Host "Gathering info for $($s.Url)" -ForegroundColor Cyan
    $owners = @($s.Owner) + $s.SecondaryAdministrators
    $externalUsers = @()
    $groupVisibility = ''

    # connect using the existing token to query users and group info
    try {
        $token = Get-PnPAccessToken -ResourceUrl $s.Url -Connection $adminConn
        Connect-PnPOnline -Url $s.Url -AccessToken $token -ErrorAction Stop
        $externalUsers = Get-PnPUser | Where-Object { $_.UserType -eq 'Guest' } | Select-Object -ExpandProperty Email
        if ($s.GroupId -ne [guid]::Empty) {
            $grp = Get-PnPMicrosoft365Group -Identity $s.GroupId -ErrorAction SilentlyContinue
            if ($grp) { $groupVisibility = $grp.Visibility }
        }
    } catch {
        Write-Warning "Could not retrieve detailed info for $($s.Url): $_"
    } finally {
        Disconnect-PnPOnline -ErrorAction SilentlyContinue | Out-Null
    }

    [PSCustomObject]@{
        Url             = $s.Url
        Title           = $s.Title
        Template        = $s.Template
        Owners          = ($owners -join '; ')
        Created         = $s.Created
        LastModified    = $s.LastContentModifiedDate
        StorageMB       = [math]::Round($s.StorageUsageCurrent / 1MB, 2)
        Department      = $s.Classification
        Sharing         = $s.SharingCapability
        TeamsConnected  = $s.IsTeamsConnected
        GroupVisibility = $groupVisibility
        ExternalUsers   = ($externalUsers -join '; ')
    }
}

# Export to Excel
$results | Export-Excel -Path $excelFile -WorksheetName 'Sites' -AutoSize

Write-Host "✅ Excel report: $excelFile"
