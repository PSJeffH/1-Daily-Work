<#
.SYNOPSIS
    Checks service status on all domain controllers.
.DESCRIPTION
    Verifies that core services like Active Directory Domain Services, DNS Server, Netlogon, and others are running on each domain controller.
#>

Import-Module ActiveDirectory

$services = @('NTDS','DNS','Netlogon','Kdc','W32Time','DFSR')
$dcs = Get-ADDomainController -Filter *

Write-Host "=== Domain Controller Services ===" -ForegroundColor Cyan
foreach ($dc in $dcs) {
    Write-Host "`n$($dc.HostName)" -ForegroundColor Yellow
    foreach ($svc in $services) {
        $status = Get-Service -ComputerName $dc.HostName -Name $svc -ErrorAction SilentlyContinue
        if ($status) {
            Write-Host "$svc : $($status.Status)" -ForegroundColor Green
        } else {
            Write-Warning "Service $svc not found"
        }
    }
}
