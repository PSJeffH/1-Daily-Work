<#
.SYNOPSIS
    Generates a report of inactive or disabled user and computer accounts.
.DESCRIPTION
    Finds accounts disabled or not logged in for a specified number of days and outputs the results.
#>

param(
    [int]$InactiveDays = 90
)

Import-Module ActiveDirectory

$since = (Get-Date).AddDays(-$InactiveDays)

$disabled = Get-ADObject -LDAPFilter '(&(objectClass=user)(|(userAccountControl:1.2.840.113556.1.4.803:=2)(userAccountControl:1.2.840.113556.1.4.803:=16)))' -Properties samAccountName,whenChanged

$inactiveUsers = Get-ADUser -Filter {Enabled -eq $true -and LastLogonDate -lt $since} -Properties LastLogonDate
$inactiveComputers = Get-ADComputer -Filter {Enabled -eq $true -and LastLogonDate -lt $since} -Properties LastLogonDate

Write-Host "=== Disabled Accounts ===" -ForegroundColor Cyan
$disabled | Select-Object samAccountName,whenChanged | Format-Table -AutoSize

Write-Host "\n=== Inactive Users ===" -ForegroundColor Cyan
$inactiveUsers | Select-Object SamAccountName,LastLogonDate | Format-Table -AutoSize

Write-Host "\n=== Inactive Computers ===" -ForegroundColor Cyan
$inactiveComputers | Select-Object SamAccountName,LastLogonDate | Format-Table -AutoSize
