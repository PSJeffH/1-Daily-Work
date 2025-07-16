<#
.SYNOPSIS
    Performs DNS health checks for domain controllers.
.DESCRIPTION
    Verifies that required SRV and host records exist for each domain controller,
    checks zone transfer settings, and confirms record IP addresses.
#>

Import-Module ActiveDirectory
Import-Module DnsServer

$domain = Get-ADDomain
$zone = $domain.DNSRoot
$dcs = Get-ADDomainController -Filter *

Write-Host "=== DNS Health Check ===" -ForegroundColor Cyan

foreach ($dc in $dcs) {
    $dcName = $dc.HostName
    Write-Host "`n$dcName" -ForegroundColor Yellow

    # Validate host A record
    $aRecord = Get-DnsServerResourceRecord -ZoneName $zone -Name $dc.HostName.Split('.')[0] -RRType A -ErrorAction SilentlyContinue
    if ($aRecord -and $aRecord.RecordData[0].IPv4Address.IPAddressToString -eq $dc.IPv4Address) {
        Write-Host "A record IP matches" -ForegroundColor Green
    } else {
        Write-Warning "A record mismatch or missing"
    }

    # Check SRV records
    $srvPaths = @(
        "_ldap._tcp.$zone",
        "_kerberos._tcp.$zone",
        "_ldap._tcp.dc._msdcs.$zone",
        "_kerberos._tcp.dc._msdcs.$zone"
    )
    foreach ($path in $srvPaths) {
        if (-not (Resolve-DnsName -Type SRV -Name $path -DnsOnly -ErrorAction SilentlyContinue | Where-Object { $_.NameHost -eq $dcName })) {
            Write-Warning "Missing SRV record $path for $dcName"
        }
    }
}

# Zone transfer settings
Write-Host "`nZone Transfer Settings" -ForegroundColor Cyan
Get-DnsServerZone -Name $zone | Select-Object ZoneName, ZoneType, AllowZoneTransfer
