#requires -Modules ActiveDirectory
<#!
.SYNOPSIS
    Finds Active Directory users with specified titles.
.DESCRIPTION
    Searches Active Directory for user accounts whose Title attribute matches one
    of the strings provided via the Titles parameter. The output includes the
    same attribute set as Find-ADUsersMissingTitle.ps1 and can be exported to
    HTML, CSV, or Excel.
.PARAMETER Titles
    One or more title strings to match. Defaults to common service-style titles
    such as "Service Account" or "Admin Account".
!>

[CmdletBinding()]
param(
    [string[]]$Titles = @(
        'Service Account',
        'Resource Account',
        'Admin Account',
        'Test Account'
    ),
    [switch]$ExportHtml,
    [switch]$ExportCsv,
    [switch]$ExportExcel,
    [string]$OutputDirectory = $PSScriptRoot
)

$properties = @(
    'Company','SamAccountName','Name','DisplayName','EmployeeNumber','EmployeeID',
    'EmployeeType','UserPrincipalName','Mail','Department','Title','Description',
    'DistinguishedName','PasswordLastSet','PasswordExpired','PasswordNeverExpires',
    'LogonCount','LastLogonDate','WhenCreated','MemberOf','extensionAttribute1',
    'extensionAttribute2','extensionAttribute3','extensionAttribute4',
    'extensionAttribute5','extensionAttribute6','extensionAttribute7',
    'extensionAttribute8','extensionAttribute9','extensionAttribute10',
    'extensionAttribute11','extensionAttribute12','extensionAttribute13',
    'extensionAttribute14','extensionAttribute15','Enabled'
)

# Build an LDAP filter to match any of the provided titles
$escaped = $Titles | ForEach-Object { $_ -replace "'", "''" }
$filter = ($escaped | ForEach-Object { "(Title -eq '$_')" }) -join ' -or '

$users = Get-ADUser -Filter $filter -Properties $properties
$results = $users | Select-Object $properties

if ($ExportHtml) {
    $htmlPath = Join-Path $OutputDirectory 'ADUsersWithTitles.html'
    $results | ConvertTo-Html -Property $properties | Out-File -Encoding utf8 $htmlPath
}

if ($ExportCsv) {
    $csvPath = Join-Path $OutputDirectory 'ADUsersWithTitles.csv'
    $results | Export-Csv -NoTypeInformation -Path $csvPath
}

if ($ExportExcel) {
    if (Get-Module -ListAvailable -Name ImportExcel) {
        $xlsxPath = Join-Path $OutputDirectory 'ADUsersWithTitles.xlsx'
        $results | Export-Excel -Path $xlsxPath -WorksheetName Users
    } else {
        Write-Warning 'Excel export requires the ImportExcel module.'
    }
}

$results
