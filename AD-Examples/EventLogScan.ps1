<#
.SYNOPSIS
    Scans event logs for recent Active Directory related errors and warnings.
.DESCRIPTION
    Retrieves critical and error events from Directory Service, DNS Server and System logs over the last 24 hours for review.
#>

$logs = @('Directory Service','DNS Server','System')
$since = (Get-Date).AddHours(-24)

Write-Host "=== Recent AD Related Events ===" -ForegroundColor Cyan
foreach ($log in $logs) {
    Write-Host "`n$log" -ForegroundColor Yellow
    Get-WinEvent -LogName $log -ErrorAction SilentlyContinue |
        Where-Object { $_.LevelDisplayName -in 'Critical','Error' -and $_.TimeCreated -ge $since } |
        Select-Object TimeCreated, Id, LevelDisplayName, Message
}
