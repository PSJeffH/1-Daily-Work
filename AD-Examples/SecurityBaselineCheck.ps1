<#
.SYNOPSIS
    Audits key security settings for compliance with recommended best practices.
.DESCRIPTION
    Checks password complexity, account lockout policy, and other common security baseline settings.
#>

Import-Module ActiveDirectory

Write-Host "=== Security Baseline ===" -ForegroundColor Cyan

$passwordPolicy = Get-ADDefaultDomainPasswordPolicy

[PSCustomObject]@{
    MinPasswordLength       = $passwordPolicy.MinPasswordLength
    PasswordHistoryCount    = $passwordPolicy.PasswordHistoryCount
    ComplexityEnabled       = $passwordPolicy.ComplexityEnabled
    LockoutThreshold        = $passwordPolicy.LockoutThreshold
    LockoutDurationMinutes  = $passwordPolicy.LockoutDuration.TotalMinutes
    LockoutObservationWindow = $passwordPolicy.LockoutObservationWindow.TotalMinutes
}
