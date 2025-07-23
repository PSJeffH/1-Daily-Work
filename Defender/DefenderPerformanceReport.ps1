<#
.SYNOPSIS
  Evaluates Microsoft Defender performance impact on Windows Server.
  Includes CPU usage, RAM usage, Defender settings, and exclusions.

.NOTES
  Tested on Windows Server 2016+
#>

# Define key Defender processes to watch
$defenderProcesses = @('MsMpEng', 'Sense', 'SecurityHealthService')

# Gather process usage info
$processInfo = Get-Process | Where-Object { $defenderProcesses -contains $_.Name } | Select-Object Name, Id, CPU, @{Name="MemoryMB"; Expression={[math]::Round($_.WorkingSet64 / 1MB, 2)}}

# Get Defender configuration
$avStatus = Get-MpComputerStatus
$avPrefs  = Get-MpPreference

# Gather exclusions
$exclusions = @{
    Paths     = $avPrefs.ExclusionPath -join ', '
    Processes = $avPrefs.ExclusionProcess -join ', '
    Extensions = $avPrefs.ExclusionExtension -join ', '
}

# Output summary
$report = [PSCustomObject]@{
    'RealTime Protection' = $avStatus.RealTimeProtectionEnabled
    'Behavior Monitoring' = $avStatus.BehaviorMonitorEnabled
    'EDR Block Mode'      = $avStatus.IsTamperProtected
    'Performance Mode'    = $avPrefs.PerformanceModeEnabled
    'MAPS Reporting'      = $avPrefs.MAPSReporting
    'Cloud Protection'    = $avPrefs.CloudBlockLevel
    'CPU Usage (MsMpEng)' = ($processInfo | Where-Object Name -eq 'MsMpEng').CPU
    'Memory (MsMpEng)'    = ($processInfo | Where-Object Name -eq 'MsMpEng').MemoryMB
    'CPU Usage (Sense)'   = ($processInfo | Where-Object Name -eq 'Sense').CPU
    'Memory (Sense)'      = ($processInfo | Where-Object Name -eq 'Sense').MemoryMB
    'Exclusions (Paths)'  = $exclusions.Paths
    'Exclusions (Procs)'  = $exclusions.Processes
    'Exclusions (Exts)'   = $exclusions.Extensions
}

# Display the summary
$report | Format-List

# Optional: Export to CSV
$report | Export-Csv -Path "$env:USERPROFILE\Desktop\DefenderPerformanceReport.csv" -NoTypeInformation
Write-Host "`nCSV exported to: $env:USERPROFILE\Desktop\DefenderPerformanceReport.csv" -ForegroundColor Green
