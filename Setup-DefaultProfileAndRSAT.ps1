<#+
.SYNOPSIS
    Creates a default PowerShell profile and installs RSAT tools.
.DESCRIPTION
    Ensures the $PROFILE file exists, creating any directories needed, and
    installs Remote Server Administration Tools (RSAT) using Windows
    capabilities if they are not already present.
#>

# Create the profile file if it does not exist
if (!(Test-Path -Path $PROFILE)) {
    $profileDir = Split-Path -Parent $PROFILE
    if (!(Test-Path -Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }
    New-Item -ItemType File -Path $PROFILE -Force | Out-Null
    Add-Content -Path $PROFILE -Value '# Default PowerShell profile'
    Write-Host "Created profile at $PROFILE" -ForegroundColor Green
} else {
    Write-Host "Profile already exists at $PROFILE" -ForegroundColor Yellow
}

# Install RSAT tools
$rsatCapabilities = Get-WindowsCapability -Online | Where-Object { $_.Name -like 'Rsat.*' -and $_.State -ne 'Installed' }

if ($rsatCapabilities) {
    foreach ($capability in $rsatCapabilities) {
        Write-Host "Installing $($capability.Name)" -ForegroundColor Cyan
        Add-WindowsCapability -Name $capability.Name -Online
    }
} else {
    Write-Host "RSAT tools are already installed" -ForegroundColor Green
}
