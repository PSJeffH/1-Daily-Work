<#
.SYNOPSIS
    Checks Active Directory replication health across all domain controllers.
.DESCRIPTION
    Reports replication partner status, lingering objects, and any replication failures found in the forest.
#>

Import-Module ActiveDirectory

$dcs = Get-ADDomainController -Filter *

Write-Host "=== Replication Status ===" -ForegroundColor Cyan
foreach ($dc in $dcs) {
    Write-Host "`n$($dc.HostName)" -ForegroundColor Yellow
    Get-ADReplicationPartnerMetadata -Target $dc.HostName -Scope Server |
        Select-Object Partner, LastReplicationSuccess, LastReplicationResult, ConsecutiveReplicationFailures
}

Write-Host "`n=== Replication Failures ===" -ForegroundColor Cyan
Get-ADReplicationFailure -Scope Forest |
    Select-Object Server, FirstFailureTime, FailureCount, FailureType

Write-Host "`n=== Lingering Objects ===" -ForegroundColor Cyan
foreach ($dc in $dcs) {
    $lingering = Get-ADReplicationLingeringObject -Server $dc.HostName -NamingContext (Get-ADDomain).DistinguishedName -ErrorAction SilentlyContinue
    if ($lingering) {
        $lingering | Select-Object Server, DistinguishedName, LastOriginatingChangeTime
    }
}
