#requires -Modules ActiveDirectory

<#!
.SYNOPSIS
    Sets extension attributes for newly created Active Directory users.
.DESCRIPTION
    Searches Active Directory for user accounts created within the last week whose
    employeeID begins with "10". Accounts with titles such as service accounts
    can be excluded using the ExcludedTitles parameter. Supports exporting the
    list of affected users to HTML, CSV, or Excel.
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

$LastWeek = (Get-Date).AddDays(-7)

# Extension attribute values to apply
$attributes = @{
    extensionAttribute1 = 'Value1'
    extensionAttribute2 = 'Value2'
    extensionAttribute3 = 'Value3'
}

$NewUsers = Get-ADUser -Filter * -Properties $properties | Where-Object {
    $_.whenCreated -ge $LastWeek -and $_.employeeID -like '10*'
}

if ($ExcludedTitles -and $ExcludedTitles.Count -gt 0) {
    $NewUsers = $NewUsers | Where-Object { $_.Title -notin $ExcludedTitles }
}

$results = $NewUsers | Select-Object $properties

if ($ExportHtml) {
    $htmlPath = Join-Path $OutputDirectory 'UpdatedUsers.html'
    $results | ConvertTo-Html -Property $properties | Out-File -Encoding utf8 $htmlPath
}

if ($ExportCsv) {
    $csvPath = Join-Path $OutputDirectory 'UpdatedUsers.csv'
    $results | Export-Csv -NoTypeInformation -Path $csvPath
}

if ($ExportExcel) {
    if (Get-Module -ListAvailable -Name ImportExcel) {
        $xlsxPath = Join-Path $OutputDirectory 'UpdatedUsers.xlsx'
        $results | Export-Excel -Path $xlsxPath -WorksheetName Users
    } else {
        Write-Warning 'Excel export requires the ImportExcel module.'
    }
}

foreach ($user in $NewUsers) {
    Set-ADUser -Identity $user -Replace $attributes
}

$results
