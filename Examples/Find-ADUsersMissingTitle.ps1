#requires -Modules ActiveDirectory

<#!
.SYNOPSIS
    Finds Active Directory users missing a Title.
.DESCRIPTION
    Searches Active Directory for user accounts where the Title attribute is empty or not set.
    You can optionally exclude specific titles such as service accounts using the
    ExcludedTitles parameter. Supports exporting the results to HTML, CSV,
    or Excel.
!>

[CmdletBinding()]
param(
    [switch]$ExportHtml,
    [switch]$ExportCsv,
    [switch]$ExportExcel,
    [string]$OutputDirectory = $PSScriptRoot,
    [string[]]$ExcludedTitles = @(
        'Service Account',
        'Resource Account',
        'Admin Account',
        'Test Account'
    )
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

$filter = "Title -notlike '*'"
if ($ExcludedTitles -and $ExcludedTitles.Count -gt 0) {
    foreach ($title in $ExcludedTitles) {
        $escaped = $title -replace "'", "''"
        $filter += " -and Title -ne '$escaped'"
    }
}

$users = Get-ADUser -Filter $filter -Properties $properties
$results = $users | Select-Object $properties

if ($ExportHtml) {
    $htmlPath = Join-Path $OutputDirectory 'ADUsersMissingTitle.html'
    $results | ConvertTo-Html -Property $properties | Out-File -Encoding utf8 $htmlPath
}

if ($ExportCsv) {
    $csvPath = Join-Path $OutputDirectory 'ADUsersMissingTitle.csv'
    $results | Export-Csv -NoTypeInformation -Path $csvPath
}

if ($ExportExcel) {
    if (Get-Module -ListAvailable -Name ImportExcel) {
        $xlsxPath = Join-Path $OutputDirectory 'ADUsersMissingTitle.xlsx'
        $results | Export-Excel -Path $xlsxPath -WorksheetName Users
    } else {
        Write-Warning 'Excel export requires the ImportExcel module.'
    }
}

$results
