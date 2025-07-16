<#
.SYNOPSIS
    Reports on user accounts with passwords expiring soon.
.DESCRIPTION
    Lists users whose passwords will expire within a specified number of days or have not been changed for an extended period.
#>

param(
    [int]$ExpiresInDays = 14,
    [int]$StaleAfterDays = 90
)

Import-Module ActiveDirectory

$now = Get-Date
$expireThreshold = $now.AddDays($ExpiresInDays)
$staleThreshold = $now.AddDays(-$StaleAfterDays)

$users = Get-ADUser -Filter {Enabled -eq $true -and PasswordNeverExpires -eq $false} -Properties DisplayName,PasswordLastSet,PasswordNeverExpires,msDS-UserPasswordExpiryTimeComputed

$results = foreach ($u in $users) {
    $expiry = [datetime]::FromFileTime($u.'msDS-UserPasswordExpiryTimeComputed')
    if ($expiry -le $expireThreshold -or $u.PasswordLastSet -le $staleThreshold) {
        [PSCustomObject]@{
            User            = $u.DisplayName
            PasswordExpires = $expiry
            PasswordLastSet = $u.PasswordLastSet
        }
    }
}

$results | Sort-Object PasswordExpires | Format-Table -AutoSize
