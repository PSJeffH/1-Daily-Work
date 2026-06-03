<#
.SYNOPSIS
    Domain Controller pre-promotion readiness and health check.

.DESCRIPTION
    Runs a practical set of checks before promoting a domain-joined Windows Server
    to an additional Domain Controller. The script validates local networking,
    DNS/DC locator records, time sync, disk capacity, AD metadata, computer
    account health, SYSVOL replication migration state, and existing DC health.

    The script is safe to run on a member server before promotion. Checks that
    require Domain Controller context are skipped unless the local server is
    already a DC.

.PARAMETER OutputPath
    Folder where log, CSV, JSON, and HTML reports are written. Defaults to the
    system drive if available, otherwise the current directory.

.PARAMETER MinimumFreeGB
    Minimum acceptable free disk space per fixed volume. Defaults to 5 GB.

.PARAMETER SkipExternalDns
    Skips the optional external DNS resolution check.

.EXAMPLE
    .\DC_PrePromotion_Check.ps1

.EXAMPLE
    .\DC_PrePromotion_Check.ps1 -OutputPath C:\Temp -MinimumFreeGB 20 -SkipExternalDns
#>

[CmdletBinding()]
param(
    [string]$OutputPath = $(if ($env:SystemDrive) { $env:SystemDrive } else { (Get-Location).Path }),
    [ValidateRange(1, 1024)]
    [int]$MinimumFreeGB = 5,
    [switch]$SkipExternalDns
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$Script:ScriptVersion = '2.0'
$Script:Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$Script:Results = New-Object System.Collections.Generic.List[object]
$Script:PrimaryIPv4 = $null
$Script:ComputerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
$Script:ComputerName = $env:COMPUTERNAME
$Script:Domain = $Script:ComputerSystem.Domain
$Script:IsDomainJoined = [bool]$Script:ComputerSystem.PartOfDomain
$Script:IsDomainController = ($Script:ComputerSystem.DomainRole -in 4, 5)

if (-not (Test-Path -Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

$Script:LogFile = Join-Path -Path $OutputPath -ChildPath "DC_PrePromotion_Check_$($Script:Timestamp).log"
$Script:CSVFile = Join-Path -Path $OutputPath -ChildPath "DC_PrePromotion_Check_$($Script:Timestamp).csv"
$Script:HTMLFile = Join-Path -Path $OutputPath -ChildPath "DC_PrePromotion_Report_$($Script:Timestamp).html"
$Script:JSONFile = Join-Path -Path $OutputPath -ChildPath "DC_PrePromotion_Check_$($Script:Timestamp).json"

function Write-Log {
    param([Parameter(Mandatory)][string]$Message)

    $line = '{0} {1}' -f (Get-Date -Format 's'), $Message
    $line | Out-File -FilePath $Script:LogFile -Append -Encoding UTF8
}

function Write-Status {
    param(
        [Parameter(Mandatory)][string]$Check,
        [Parameter(Mandatory)][ValidateSet('OK', 'WARN', 'FAIL', 'INFO', 'SKIP')][string]$Status,
        [string]$Detail = ''
    )

    $message = if ([string]::IsNullOrWhiteSpace($Detail)) { $Check } else { "$Check - $Detail" }

    switch ($Status) {
        'OK'   { Write-Host "[OK]   $message" -ForegroundColor Green }
        'WARN' { Write-Host "[WARN] $message" -ForegroundColor Yellow }
        'FAIL' { Write-Host "[FAIL] $message" -ForegroundColor Red }
        'INFO' { Write-Host "[INFO] $message" -ForegroundColor Cyan }
        'SKIP' { Write-Host "[SKIP] $message" -ForegroundColor DarkGray }
    }

    Write-Log "$Status : $message"
    $Script:Results.Add([PSCustomObject]@{
        Timestamp = Get-Date
        Check     = $Check
        Status    = $Status
        Detail    = $Detail
    }) | Out-Null
}

function Start-Check {
    param([Parameter(Mandatory)][string]$Title)

    Write-Host "`n===== $Title =====`n" -ForegroundColor Cyan
    Write-Log "`n===== $Title ====="
}

function Test-CommandAvailable {
    param([Parameter(Mandatory)][string]$Name)

    return [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList
    )

    $output = & $FilePath @ArgumentList 2>&1
    [PSCustomObject]@{
        ExitCode = $LASTEXITCODE
        Output   = ($output | Out-String).Trim()
    }
}

function Import-ADModuleIfAvailable {
    if (Get-Module -Name ActiveDirectory) {
        return $true
    }

    if (Get-Module -ListAvailable -Name ActiveDirectory) {
        Import-Module ActiveDirectory -ErrorAction Stop
        return $true
    }

    return $false
}

function Test-StaticIP {
    Start-Check 'Static IPv4 Address Check'

    if (-not (Test-CommandAvailable -Name Get-NetIPAddress)) {
        Write-Status 'Get-NetIPAddress availability' 'FAIL' 'NetTCPIP module is unavailable.'
        return
    }

    $addresses = Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object {
            $_.IPAddress -notlike '169.254.*' -and
            $_.IPAddress -ne '127.0.0.1' -and
            $_.PrefixOrigin -ne 'WellKnown'
        } |
        Sort-Object -Property InterfaceIndex, IPAddress

    if (-not $addresses) {
        Write-Status 'IPv4 address detection' 'FAIL' 'No usable IPv4 address was detected.'
        return
    }

    foreach ($address in $addresses) {
        $detail = 'Address {0}/{1}, PrefixOrigin {2}, InterfaceIndex {3}' -f $address.IPAddress, $address.PrefixLength, $address.PrefixOrigin, $address.InterfaceIndex
        if ($address.PrefixOrigin -eq 'Dhcp') {
            Write-Status 'Static IPv4 requirement' 'FAIL' $detail
        }
        else {
            Write-Status 'Static IPv4 requirement' 'OK' $detail
        }
    }

    $Script:PrimaryIPv4 = ($addresses | Select-Object -First 1).IPAddress
}

function Test-DNSServers {
    Start-Check 'DNS Server IP Configuration'

    if (-not (Test-CommandAvailable -Name Get-DnsClientServerAddress)) {
        Write-Status 'Get-DnsClientServerAddress availability' 'FAIL' 'DnsClient module is unavailable.'
        return
    }

    $dnsServers = Get-DnsClientServerAddress -AddressFamily IPv4 |
        Where-Object { $_.ServerAddresses } |
        ForEach-Object { $_.ServerAddresses } |
        Where-Object { $_ } |
        Select-Object -Unique

    if (-not $dnsServers) {
        Write-Status 'DNS server configuration' 'FAIL' 'No IPv4 DNS servers are configured.'
        return
    }

    Write-Status 'DNS server configuration' 'OK' ($dnsServers -join ', ')

    foreach ($dnsServer in $dnsServers) {
        if ($dnsServer -match '^(8\.8\.8\.8|8\.8\.4\.4|1\.1\.1\.1|1\.0\.0\.1|9\.9\.9\.9)$') {
            Write-Status 'DNS server suitability' 'WARN' "$dnsServer appears to be public DNS; use AD-integrated/internal DNS before DC promotion."
        }

        if (Test-Connection -ComputerName $dnsServer -Count 2 -Quiet -ErrorAction SilentlyContinue) {
            Write-Status 'DNS server reachability' 'OK' "$dnsServer is reachable by ICMP."
        }
        else {
            Write-Status 'DNS server reachability' 'WARN' "$dnsServer did not answer ICMP. DNS may still work if ICMP is blocked."
        }
    }
}

function Test-DNSARecord {
    Start-Check 'DNS A Record Validation'

    if (-not (Test-CommandAvailable -Name Resolve-DnsName)) {
        Write-Status 'Resolve-DnsName availability' 'FAIL' 'DnsClient module is unavailable.'
        return
    }

    $namesToTest = @($Script:ComputerName)
    if ($Script:IsDomainJoined) {
        $namesToTest += '{0}.{1}' -f $Script:ComputerName, $Script:Domain
    }

    foreach ($name in ($namesToTest | Select-Object -Unique)) {
        try {
            $records = Resolve-DnsName -Name $name -Type A -ErrorAction Stop | Where-Object { $_.IPAddress }
            $resolvedAddresses = @($records.IPAddress | Select-Object -Unique)
            if ($resolvedAddresses) {
                $status = if ($Script:PrimaryIPv4 -and ($resolvedAddresses -contains $Script:PrimaryIPv4)) { 'OK' } else { 'WARN' }
                Write-Status 'DNS A record' $status "$name resolves to $($resolvedAddresses -join ', ')."
            }
            else {
                Write-Status 'DNS A record' 'FAIL' "$name returned no A records."
            }
        }
        catch {
            Write-Status 'DNS A record' 'FAIL' "$name failed to resolve. $($_.Exception.Message)"
        }
    }
}

function Test-DNSPTRRecord {
    Start-Check 'Reverse DNS PTR Record Check'

    if (-not $Script:PrimaryIPv4) {
        Write-Status 'PTR record validation' 'SKIP' 'Primary IPv4 address is unavailable.'
        return
    }

    try {
        $ptrRecords = Resolve-DnsName -Name $Script:PrimaryIPv4 -Type PTR -ErrorAction Stop | Where-Object { $_.NameHost }
        if ($ptrRecords) {
            Write-Status 'PTR record validation' 'OK' "$Script:PrimaryIPv4 resolves to $($ptrRecords.NameHost -join ', ')."
        }
        else {
            Write-Status 'PTR record validation' 'WARN' "$Script:PrimaryIPv4 returned no PTR records."
        }
    }
    catch {
        Write-Status 'PTR record validation' 'WARN' "Missing or unavailable PTR record for $Script:PrimaryIPv4."
    }
}

function Test-DNSExternal {
    Start-Check 'External DNS Resolution Check'

    if ($SkipExternalDns) {
        Write-Status 'External DNS resolution' 'SKIP' 'Skipped by parameter.'
        return
    }

    try {
        Resolve-DnsName -Name 'microsoft.com' -Type A -ErrorAction Stop | Out-Null
        Write-Status 'External DNS resolution' 'OK' 'microsoft.com resolved successfully.'
    }
    catch {
        Write-Status 'External DNS resolution' 'WARN' "External DNS lookup failed. This may be expected in isolated networks. $($_.Exception.Message)"
    }
}

function Test-DNSSRVRecords {
    Start-Check 'DNS SRV Record Validation'

    if (-not $Script:IsDomainJoined) {
        Write-Status 'DNS SRV records' 'SKIP' 'Server is not domain joined.'
        return
    }

    $srvRecords = @(
        "_ldap._tcp.$($Script:Domain)",
        "_kerberos._tcp.$($Script:Domain)",
        "_ldap._tcp.dc._msdcs.$($Script:Domain)",
        "_kerberos._tcp.dc._msdcs.$($Script:Domain)"
    )

    foreach ($record in $srvRecords) {
        try {
            $answers = Resolve-DnsName -Name $record -Type SRV -ErrorAction Stop | Where-Object { $_.NameTarget }
            if ($answers) {
                Write-Status 'DNS SRV record' 'OK' "$record returned $($answers.Count) answer(s)."
            }
            else {
                Write-Status 'DNS SRV record' 'FAIL' "$record returned no SRV answers."
            }
        }
        catch {
            Write-Status 'DNS SRV record' 'FAIL' "$record is missing or unreachable."
        }
    }
}

function Test-DefaultGateway {
    Start-Check 'Default Gateway Check'

    if (-not (Test-CommandAvailable -Name Get-NetIPConfiguration)) {
        Write-Status 'Get-NetIPConfiguration availability' 'FAIL' 'NetTCPIP module is unavailable.'
        return
    }

    $gateways = Get-NetIPConfiguration |
        Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } |
        ForEach-Object { $_.IPv4DefaultGateway.NextHop } |
        Where-Object { $_ } |
        Select-Object -Unique

    if (-not $gateways) {
        Write-Status 'Default gateway configuration' 'WARN' 'No IPv4 default gateway is configured on an active adapter.'
        return
    }

    foreach ($gateway in $gateways) {
        if (Test-Connection -ComputerName $gateway -Count 2 -Quiet -ErrorAction SilentlyContinue) {
            Write-Status 'Default gateway reachability' 'OK' "$gateway is reachable."
        }
        else {
            Write-Status 'Default gateway reachability' 'WARN' "$gateway did not answer ICMP. Routing may still work if ICMP is blocked."
        }
    }
}

function Test-TimeSync {
    Start-Check 'Time Synchronization Check'

    try {
        $service = Get-Service -Name w32time -ErrorAction Stop
        if ($service.Status -eq 'Running') {
            Write-Status 'Windows Time service' 'OK' 'Service is running.'
        }
        else {
            Write-Status 'Windows Time service' 'FAIL' "Service status is $($service.Status)."
        }
    }
    catch {
        Write-Status 'Windows Time service' 'FAIL' $_.Exception.Message
    }

    if (-not (Test-CommandAvailable -Name w32tm.exe)) {
        Write-Status 'w32tm availability' 'FAIL' 'w32tm.exe was not found.'
        return
    }

    $status = Invoke-NativeCommand -FilePath 'w32tm.exe' -ArgumentList @('/query', '/status')
    if ($status.ExitCode -eq 0) {
        $source = (($status.Output -split "`r?`n") | Where-Object { $_ -match '^Source:' } | Select-Object -First 1)
        Write-Status 'Time sync status' 'OK' $(if ($source) { $source } else { 'w32tm status query completed.' })
        Write-Log $status.Output
    }
    else {
        Write-Status 'Time sync status' 'WARN' "w32tm /query /status failed with exit code $($status.ExitCode)."
        Write-Log $status.Output
    }
}

function Test-DiskSpace {
    Start-Check 'Disk Capacity Check'

    $volumes = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType = 3"
    if (-not $volumes) {
        Write-Status 'Fixed disk detection' 'WARN' 'No fixed disks were returned by Win32_LogicalDisk.'
        return
    }

    foreach ($volume in $volumes) {
        $freeGB = [Math]::Round(($volume.FreeSpace / 1GB), 2)
        $sizeGB = [Math]::Round(($volume.Size / 1GB), 2)
        $detail = '{0} has {1} GB free of {2} GB total.' -f $volume.DeviceID, $freeGB, $sizeGB
        if ($freeGB -lt $MinimumFreeGB) {
            Write-Status 'Disk free space' 'FAIL' "$detail Minimum required is $MinimumFreeGB GB."
        }
        else {
            Write-Status 'Disk free space' 'OK' $detail
        }
    }
}

function Test-DomainJoinStatus {
    Start-Check 'Domain Join Status'

    if ($Script:IsDomainJoined) {
        Write-Status 'Domain join status' 'OK' "Server is joined to $($Script:Domain)."
    }
    else {
        Write-Status 'Domain join status' 'FAIL' 'Server must be joined to the existing domain before this promotion scenario.'
    }
}

function Test-ADModule {
    Start-Check 'Active Directory PowerShell Module Check'

    if (Import-ADModuleIfAvailable) {
        Write-Status 'Active Directory module' 'OK' 'ActiveDirectory module is available.'
    }
    else {
        Write-Status 'Active Directory module' 'WARN' 'RSAT Active Directory module is unavailable; AD cmdlet-based checks will be skipped.'
    }
}

function Test-FunctionalLevels {
    Start-Check 'AD Forest and Domain Functional Levels'

    if (-not $Script:IsDomainJoined) {
        Write-Status 'Functional levels' 'SKIP' 'Server is not domain joined.'
        return
    }

    if (-not (Import-ADModuleIfAvailable)) {
        Write-Status 'Functional levels' 'SKIP' 'ActiveDirectory module is unavailable.'
        return
    }

    try {
        $domainObject = Get-ADDomain -ErrorAction Stop
        $forestObject = Get-ADForest -ErrorAction Stop
        Write-Status 'Domain functional level' 'OK' $domainObject.DomainMode
        Write-Status 'Forest functional level' 'OK' $forestObject.ForestMode
    }
    catch {
        Write-Status 'Functional levels' 'WARN' $_.Exception.Message
    }
}

function Test-SchemaVersion {
    Start-Check 'Active Directory Schema Version'

    if (-not $Script:IsDomainJoined) {
        Write-Status 'Schema version' 'SKIP' 'Server is not domain joined.'
        return
    }

    if (-not (Import-ADModuleIfAvailable)) {
        Write-Status 'Schema version' 'SKIP' 'ActiveDirectory module is unavailable.'
        return
    }

    $schemaMap = @{
        47 = 'Windows Server 2008 R2'
        56 = 'Windows Server 2012'
        69 = 'Windows Server 2012 R2'
        87 = 'Windows Server 2016/2019/2022/2025'
        88 = 'Windows Server 2025 newer schema update'
    }

    try {
        $rootDse = Get-ADRootDSE -ErrorAction Stop
        $schemaDn = 'CN=Schema,{0}' -f $rootDse.ConfigurationNamingContext
        $schemaVersion = (Get-ADObject -Identity $schemaDn -Properties objectVersion -ErrorAction Stop).objectVersion
        $friendly = if ($schemaMap.ContainsKey([int]$schemaVersion)) { $schemaMap[[int]$schemaVersion] } else { 'Unknown schema mapping' }
        Write-Status 'Schema version' 'OK' "objectVersion $schemaVersion ($friendly)."
    }
    catch {
        Write-Status 'Schema version' 'WARN' $_.Exception.Message
    }
}

function Test-ADSite {
    Start-Check 'AD Site Detection'

    if (-not $Script:IsDomainJoined) {
        Write-Status 'AD site detection' 'SKIP' 'Server is not domain joined.'
        return
    }

    if (-not (Test-CommandAvailable -Name nltest.exe)) {
        Write-Status 'nltest availability' 'FAIL' 'nltest.exe was not found.'
        return
    }

    $site = Invoke-NativeCommand -FilePath 'nltest.exe' -ArgumentList @('/dsgetsite')
    if ($site.ExitCode -eq 0 -and $site.Output) {
        Write-Status 'AD site detection' 'OK' ($site.Output -replace "`r?`n", ' ')
    }
    else {
        Write-Status 'AD site detection' 'WARN' "nltest /dsgetsite failed with exit code $($site.ExitCode). $($site.Output)"
    }
}

function Test-StaleComputerObject {
    Start-Check 'AD Computer Account Health'

    if (-not $Script:IsDomainJoined) {
        Write-Status 'Computer account health' 'SKIP' 'Server is not domain joined.'
        return
    }

    if (-not (Import-ADModuleIfAvailable)) {
        Write-Status 'Computer account health' 'SKIP' 'ActiveDirectory module is unavailable.'
        return
    }

    try {
        $computer = Get-ADComputer -Identity $Script:ComputerName -Properties PasswordLastSet,LastLogonDate,Enabled -ErrorAction Stop
        if ($computer.Enabled) {
            Write-Status 'Computer account enabled' 'OK' 'Computer object is enabled.'
        }
        else {
            Write-Status 'Computer account enabled' 'FAIL' 'Computer object is disabled.'
        }

        Write-Status 'Computer password age' 'OK' "PasswordLastSet: $($computer.PasswordLastSet)."
        Write-Status 'Computer last logon' 'INFO' "LastLogonDate: $($computer.LastLogonDate)."
    }
    catch {
        Write-Status 'Computer account health' 'WARN' $_.Exception.Message
    }
}

function Test-DCLocator {
    Start-Check 'Domain Controller Locator Health'

    if (-not $Script:IsDomainJoined) {
        Write-Status 'DC locator' 'SKIP' 'Server is not domain joined.'
        return
    }

    if (-not (Test-CommandAvailable -Name nltest.exe)) {
        Write-Status 'nltest availability' 'FAIL' 'nltest.exe was not found.'
        return
    }

    $locator = Invoke-NativeCommand -FilePath 'nltest.exe' -ArgumentList @("/dsgetdc:$($Script:Domain)")
    if ($locator.ExitCode -eq 0) {
        Write-Status 'DC locator' 'OK' 'A domain controller was located.'
        Write-Log $locator.Output
    }
    else {
        Write-Status 'DC locator' 'FAIL' "nltest failed with exit code $($locator.ExitCode). $($locator.Output)"
    }
}

function Test-Trusts {
    Start-Check 'Domain Trust Health'

    if (-not $Script:IsDomainJoined) {
        Write-Status 'Trust enumeration' 'SKIP' 'Server is not domain joined.'
        return
    }

    if (-not (Import-ADModuleIfAvailable)) {
        Write-Status 'Trust enumeration' 'SKIP' 'ActiveDirectory module is unavailable.'
        return
    }

    try {
        $trusts = @(Get-ADTrust -Filter * -ErrorAction Stop)
        if ($trusts.Count -eq 0) {
            Write-Status 'Trust enumeration' 'INFO' 'No trusts found. This is normal for a single-domain forest.'
            return
        }

        foreach ($trust in $trusts) {
            Write-Status 'Trust enumeration' 'OK' ('{0}; Direction={1}; Type={2}; Transitive={3}' -f $trust.Name, $trust.Direction, $trust.TrustType, $trust.IsTransitive)
        }
    }
    catch {
        Write-Status 'Trust enumeration' 'WARN' $_.Exception.Message
    }
}

function Test-SYSVOL {
    Start-Check 'SYSVOL and NETLOGON Share Check'

    if (-not $Script:IsDomainController) {
        Write-Status 'SYSVOL and NETLOGON shares' 'SKIP' 'Local server is not currently a domain controller.'
        return
    }

    if (-not (Test-CommandAvailable -Name Get-SmbShare)) {
        Write-Status 'Get-SmbShare availability' 'FAIL' 'SmbShare module is unavailable.'
        return
    }

    $shares = @(Get-SmbShare -ErrorAction Stop | Select-Object -ExpandProperty Name)
    foreach ($shareName in @('SYSVOL', 'NETLOGON')) {
        if ($shares -contains $shareName) {
            Write-Status "$shareName share" 'OK' 'Share exists.'
        }
        else {
            Write-Status "$shareName share" 'FAIL' 'Share is missing.'
        }
    }
}

function Test-SYSVOLReplicationMigrationState {
    Start-Check 'SYSVOL Replication Migration State'

    if (-not $Script:IsDomainJoined) {
        Write-Status 'SYSVOL replication migration state' 'SKIP' 'Server is not domain joined.'
        return
    }

    if (-not (Test-CommandAvailable -Name dfsrmig.exe)) {
        Write-Status 'dfsrmig availability' 'WARN' 'dfsrmig.exe was not found. Install AD DS management tools to check migration state.'
        return
    }

    $state = Invoke-NativeCommand -FilePath 'dfsrmig.exe' -ArgumentList @('/getglobalstate')
    Write-Log $state.Output
    if ($state.ExitCode -ne 0) {
        Write-Status 'SYSVOL replication migration state' 'WARN' "dfsrmig failed with exit code $($state.ExitCode)."
        return
    }

    if ($state.Output -match 'Eliminated') {
        Write-Status 'SYSVOL replication migration state' 'OK' 'DFSR migration global state is Eliminated.'
    }
    elseif ($state.Output -match 'Prepared|Redirected') {
        Write-Status 'SYSVOL replication migration state' 'WARN' 'DFSR migration is in progress; verify before promotion.'
    }
    else {
        Write-Status 'SYSVOL replication migration state' 'FAIL' 'Domain may still depend on deprecated FRS for SYSVOL replication.'
    }
}

function Test-ADReplication {
    Start-Check 'Active Directory Replication Health'

    if (-not $Script:IsDomainController) {
        Write-Status 'AD replication health' 'SKIP' 'Local server is not currently a domain controller.'
        return
    }

    if (-not (Test-CommandAvailable -Name repadmin.exe)) {
        Write-Status 'repadmin availability' 'FAIL' 'repadmin.exe was not found.'
        return
    }

    $replication = Invoke-NativeCommand -FilePath 'repadmin.exe' -ArgumentList @('/replsummary')
    Write-Log $replication.Output
    if ($replication.ExitCode -eq 0 -and $replication.Output -match 'fails/total') {
        if ($replication.Output -match '\s[1-9]\d*\s*/\s*\d+') {
            Write-Status 'AD replication health' 'WARN' 'Replication summary shows one or more failures. Review the log file.'
        }
        else {
            Write-Status 'AD replication health' 'OK' 'Replication summary completed without detected failures.'
        }
    }
    else {
        Write-Status 'AD replication health' 'WARN' "repadmin failed or returned unexpected output. Exit code: $($replication.ExitCode)."
    }
}

function Test-DCDiag {
    Start-Check 'DCDiag Health Check'

    if (-not $Script:IsDomainController) {
        Write-Status 'DCDiag' 'SKIP' 'Local server is not currently a domain controller.'
        return
    }

    if (-not (Test-CommandAvailable -Name dcdiag.exe)) {
        Write-Status 'dcdiag availability' 'FAIL' 'dcdiag.exe was not found.'
        return
    }

    $dcdiag = Invoke-NativeCommand -FilePath 'dcdiag.exe' -ArgumentList @('/q')
    Write-Log $dcdiag.Output
    if ($dcdiag.ExitCode -eq 0 -and [string]::IsNullOrWhiteSpace($dcdiag.Output)) {
        Write-Status 'DCDiag' 'OK' 'dcdiag /q returned no errors.'
    }
    else {
        Write-Status 'DCDiag' 'WARN' 'dcdiag /q returned output or a non-zero exit code. Review the log file.'
    }
}

function Test-ADDSDeploymentPrerequisites {
    Start-Check 'AD DS Deployment Module Prerequisite Check'

    if (-not $Script:IsDomainJoined) {
        Write-Status 'AD DS deployment prerequisites' 'SKIP' 'Server is not domain joined.'
        return
    }

    if (Get-Module -ListAvailable -Name ADDSDeployment) {
        Write-Status 'ADDSDeployment module' 'OK' 'Module is available. Run Test-ADDSDomainControllerInstallation with credentials during your promotion change window for Microsoft prerequisite validation.'
    }
    else {
        Write-Status 'ADDSDeployment module' 'WARN' 'Module is unavailable. Install the AD-Domain-Services role before final promotion validation.'
    }
}

function Export-Reports {
    Start-Check 'Report Export'

    try {
        $Script:Results | Export-Csv -Path $Script:CSVFile -NoTypeInformation -Encoding UTF8
        Write-Status 'CSV report export' 'OK' $Script:CSVFile
    }
    catch {
        Write-Status 'CSV report export' 'FAIL' $_.Exception.Message
    }

    $metadata = [PSCustomObject]@{
        ScriptVersion      = $Script:ScriptVersion
        Timestamp          = $Script:Timestamp
        ComputerName       = $Script:ComputerName
        Domain             = $Script:Domain
        IsDomainJoined     = $Script:IsDomainJoined
        IsDomainController = $Script:IsDomainController
        MinimumFreeGB      = $MinimumFreeGB
    }

    try {
        [PSCustomObject]@{
            Metadata = $metadata
            Results  = $Script:Results
        } | ConvertTo-Json -Depth 8 | Out-File -FilePath $Script:JSONFile -Encoding UTF8
        Write-Status 'JSON report export' 'OK' $Script:JSONFile
    }
    catch {
        Write-Status 'JSON report export' 'FAIL' $_.Exception.Message
    }

    try {
        $style = @'
<style>
body { font-family: Segoe UI, Arial, sans-serif; margin: 20px; }
table { border-collapse: collapse; width: 100%; }
th, td { padding: 8px; border: 1px solid #ccc; text-align: left; }
th { background-color: #333; color: white; }
.OK { color: green; font-weight: bold; }
.WARN { color: #b36b00; font-weight: bold; }
.FAIL { color: red; font-weight: bold; }
.INFO { color: blue; font-weight: bold; }
.SKIP { color: gray; font-weight: bold; }
</style>
'@
        $preContent = "<h1>DC Pre-Promotion Health Check Report</h1><p><strong>Server:</strong> $($Script:ComputerName)<br><strong>Domain:</strong> $($Script:Domain)<br><strong>Timestamp:</strong> $($Script:Timestamp)</p>"
        $Script:Results |
            Select-Object Timestamp, Check, Status, Detail |
            ConvertTo-Html -Title 'DC Pre-Promotion Health Check Report' -Head $style -PreContent $preContent |
            ForEach-Object { $_ -replace '<td>(OK|WARN|FAIL|INFO|SKIP)</td>', '<td class="$1">$1</td>' } |
            Out-File -FilePath $Script:HTMLFile -Encoding UTF8
        Write-Status 'HTML report export' 'OK' $Script:HTMLFile
    }
    catch {
        Write-Status 'HTML report export' 'FAIL' $_.Exception.Message
    }

    if (Test-Path -Path $Script:LogFile) {
        Write-Status 'Log file export' 'OK' $Script:LogFile
    }
    else {
        Write-Status 'Log file export' 'WARN' 'Log file was not found.'
    }
}

function Invoke-DCPrePromotionCheck {
    Write-Host "`n========== Starting DC Pre-Promotion Health Check ==========`n" -ForegroundColor Cyan
    Write-Log '========== Starting DC Pre-Promotion Health Check =========='
    Write-Status 'Script metadata' 'INFO' "Version $($Script:ScriptVersion); Computer $($Script:ComputerName); Domain $($Script:Domain); DomainJoined $($Script:IsDomainJoined); IsDC $($Script:IsDomainController)."

    Test-StaticIP
    Test-DNSServers
    Test-DNSARecord
    Test-DNSPTRRecord
    Test-DNSExternal
    Test-DNSSRVRecords
    Test-DefaultGateway
    Test-TimeSync
    Test-DiskSpace
    Test-DomainJoinStatus
    Test-ADModule
    Test-FunctionalLevels
    Test-SchemaVersion
    Test-ADSite
    Test-StaleComputerObject
    Test-DCLocator
    Test-Trusts
    Test-SYSVOLReplicationMigrationState
    Test-ADDSDeploymentPrerequisites

    if ($Script:IsDomainController) {
        Write-Status 'DC-specific checks' 'INFO' 'Local server is a domain controller; running DC health checks.'
        Test-SYSVOL
        Test-ADReplication
        Test-DCDiag
    }
    else {
        Write-Status 'DC-specific checks' 'SKIP' 'Local server is not yet a domain controller.'
    }

    Export-Reports
    Write-Status 'Promotion readiness reminder' 'INFO' 'Review all FAIL and WARN results before promoting this server to a Domain Controller.'
    Write-Host "`n========== Health Check Complete ==========`n" -ForegroundColor Cyan
}

Invoke-DCPrePromotionCheck
