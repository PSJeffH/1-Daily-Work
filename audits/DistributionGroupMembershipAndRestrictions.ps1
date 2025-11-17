#requires -Modules ExchangeOnlineManagement
<#+
.SYNOPSIS
    Builds detailed distribution group membership and sender restriction reports.
.DESCRIPTION
    Collects membership information for one or more distribution groups and
    exports two CSV files:
        1. DistributionGroupMembers.csv – one row per member that includes the
           requested identity, contact and employment related attributes.
        2. AcceptMessagesOnlyFrom.csv – one row per explicit sender restriction
           showing whether a user or group is allowed to send to the target
           distribution group. When a group is listed as an allowed sender, its
           members are expanded in the report.
    Connect to Exchange Online (and/or an on-premises Exchange session) before
    running the script.
.PARAMETER DistributionGroup
    Optional list of distribution group identities. When omitted, all available
    groups are processed.
.PARAMETER OutputDirectory
    Directory where the CSV files will be written. Defaults to the script
    location.
.EXAMPLE
    .\DistributionGroupMembershipAndRestrictions.ps1 -DistributionGroup "All Staff"

    Generates the member and sender restriction CSV files for the "All Staff"
    distribution group.
#>

[CmdletBinding()]
param(
    [string[]]$DistributionGroup,
    [string]$OutputDirectory = $PSScriptRoot
)

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

$availableCommands = @{
    GetRecipient             = [bool](Get-Command -Name 'Get-Recipient' -ErrorAction SilentlyContinue)
    GetUser                  = [bool](Get-Command -Name 'Get-User' -ErrorAction SilentlyContinue)
    GetMailbox               = [bool](Get-Command -Name 'Get-Mailbox' -ErrorAction SilentlyContinue)
    GetMailContact           = [bool](Get-Command -Name 'Get-MailContact' -ErrorAction SilentlyContinue)
    GetDistributionGroup     = [bool](Get-Command -Name 'Get-DistributionGroup' -ErrorAction SilentlyContinue)
    GetDistributionGroupMember = [bool](Get-Command -Name 'Get-DistributionGroupMember' -ErrorAction SilentlyContinue)
    GetADUser                = [bool](Get-Command -Name 'Get-ADUser' -ErrorAction SilentlyContinue)
}

$recipientCache = @{}
function Resolve-DirectoryObject {
    param(
        [Parameter(Mandatory)]
        [object]$Identity
    )

    if (-not $Identity) { return $null }

    $key = $Identity.ToString()
    if ($recipientCache.ContainsKey($key)) {
        return $recipientCache[$key]
    }

    $result = $null
    if ($availableCommands.GetRecipient) {
        try { $result = Get-Recipient -Identity $Identity -ErrorAction Stop } catch {}
    }
    if (-not $result -and $availableCommands.GetUser) {
        try { $result = Get-User -Identity $Identity -ErrorAction Stop } catch {}
    }
    if (-not $result -and $availableCommands.GetMailbox) {
        try { $result = Get-Mailbox -Identity $Identity -ErrorAction Stop } catch {}
    }
    if (-not $result -and $availableCommands.GetMailContact) {
        try { $result = Get-MailContact -Identity $Identity -ErrorAction Stop } catch {}
    }
    if (-not $result -and $availableCommands.GetDistributionGroup) {
        try { $result = Get-DistributionGroup -Identity $Identity -ErrorAction Stop } catch {}
    }
    if (-not $result -and $availableCommands.GetADUser) {
        try { $result = Get-ADUser -Identity $Identity -Properties * -ErrorAction Stop } catch {}
    }

    $recipientCache[$key] = $result
    return $result
}

function Get-AcceptedSenderEntries {
    param(
        [Parameter(Mandatory)]
        $Group
    )

    $values = @()
    foreach ($propertyName in 'AcceptMessagesOnlyFrom','AcceptMessagesOnlyFromDLMembers','AcceptMessagesOnlyFromSendersOrMembers') {
        $propertyValue = $Group.$propertyName
        if ($propertyValue) {
            $values += $propertyValue
        }
    }
    return $values | Where-Object { $_ } | Select-Object -Unique
}

$groupsToProcess = @()
if ($DistributionGroup -and $DistributionGroup.Count -gt 0) {
    foreach ($identity in $DistributionGroup) {
        try {
            $group = Get-DistributionGroup -Identity $identity -ErrorAction Stop
            $groupsToProcess += $group
        } catch {
            Write-Warning "Unable to locate distribution group '$identity': $_"
        }
    }
} else {
    try {
        $groupsToProcess = Get-DistributionGroup -ResultSize Unlimited
    } catch {
        throw "Unable to retrieve distribution groups: $_"
    }
}

if (-not $groupsToProcess) {
    throw 'No distribution groups found to process.'
}

$memberReport = @()
$acceptReport = @()

foreach ($group in $groupsToProcess) {
    Write-Verbose "Processing group: $($group.DisplayName)"

    $members = @()
    if ($availableCommands.GetDistributionGroupMember) {
        try {
            $members = Get-DistributionGroupMember -Identity $group.Identity -ResultSize Unlimited -ErrorAction Stop
        } catch {
            Write-Warning "Failed to retrieve members for group '$($group.DisplayName)': $_"
        }
    }

    foreach ($member in $members) {
        $memberDetails = Resolve-DirectoryObject -Identity $member.Identity
        if (-not $memberDetails) {
            $memberDetails = $member
        }

        $managerName = $null
        $managerEmail = $null
        if ($memberDetails.Manager) {
            $managerDetails = Resolve-DirectoryObject -Identity $memberDetails.Manager
            if ($managerDetails) {
                $managerName = $managerDetails.DisplayName
                $managerEmail = $managerDetails.PrimarySmtpAddress
            }
        }

        $memberReport += [pscustomobject]@{
            GroupName             = $group.DisplayName
            GroupEmail            = $group.PrimarySmtpAddress
            GroupAlias            = $group.Alias
            GroupDescription      = $group.Notes
            GroupOffice           = $group.Office
            MemberDisplayName     = $memberDetails.DisplayName
            MemberEmail           = $memberDetails.PrimarySmtpAddress
            MemberUPN             = $memberDetails.UserPrincipalName
            MemberType            = $memberDetails.RecipientTypeDetails
            Title                 = $memberDetails.Title
            Department            = $memberDetails.Department
            EmployeeID            = $memberDetails.EmployeeID
            EmployeeNumber        = $memberDetails.EmployeeNumber
            EA1                   = $memberDetails.ExtensionAttribute1
            EA2                   = $memberDetails.ExtensionAttribute2
            EA9                   = $memberDetails.ExtensionAttribute9
            Manager               = $managerName
            ManagerEmail          = $managerEmail
            Description           = $memberDetails.Description
            Office                = $memberDetails.Office
            Division              = $memberDetails.Division
            Company               = $memberDetails.Company
            City                  = $memberDetails.City
            StateOrProvince       = $memberDetails.StateOrProvince
            CountryOrRegion       = $memberDetails.CountryOrRegion
            OfficePhone           = $memberDetails.OfficePhone
            MobilePhone           = $memberDetails.MobilePhone
            SamAccountName        = $memberDetails.SamAccountName
            WhenCreated           = $memberDetails.WhenCreated
        }
    }

    $acceptedSenders = Get-AcceptedSenderEntries -Group $group
    foreach ($entry in $acceptedSenders) {
        $sender = Resolve-DirectoryObject -Identity $entry
        if (-not $sender) {
            Write-Warning "Unable to resolve allowed sender '$entry' for group '$($group.DisplayName)'"
            continue
        }

        $senderIsGroup = $sender.RecipientTypeDetails -match 'Group'
        $senderMembers = $null
        if ($senderIsGroup -and $availableCommands.GetDistributionGroupMember) {
            try {
                $senderMembers = Get-DistributionGroupMember -Identity $sender.Identity -ResultSize Unlimited -ErrorAction Stop |
                    Select-Object -ExpandProperty DisplayName
                if ($senderMembers) {
                    $senderMembers = ($senderMembers | Sort-Object) -join '; '
                }
            } catch {
                Write-Warning "Unable to expand members for allowed sender group '$($sender.DisplayName)': $_"
            }
        }

        $acceptReport += [pscustomobject]@{
            TargetGroupName        = $group.DisplayName
            TargetGroupEmail       = $group.PrimarySmtpAddress
            AllowedSenderType      = if ($senderIsGroup) { 'Group' } else { 'User' }
            AllowedSenderName      = $sender.DisplayName
            AllowedSenderEmail     = $sender.PrimarySmtpAddress
            AllowedSenderDepartment= $sender.Department
            AllowedSenderTitle     = $sender.Title
            AllowedSenderMembers   = $senderMembers
        }
    }
}

$memberCsv = Join-Path $OutputDirectory 'DistributionGroupMembers.csv'
$acceptCsv = Join-Path $OutputDirectory 'AcceptMessagesOnlyFrom.csv'

if ($memberReport.Count -gt 0) {
    $memberReport | Export-Csv -Path $memberCsv -NoTypeInformation -Encoding UTF8
    Write-Host "Saved member report to $memberCsv" -ForegroundColor Green
} else {
    Write-Warning 'No distribution group member data was collected.'
}

if ($acceptReport.Count -gt 0) {
    $acceptReport | Export-Csv -Path $acceptCsv -NoTypeInformation -Encoding UTF8
    Write-Host "Saved AcceptMessagesOnlyFrom report to $acceptCsv" -ForegroundColor Green
} else {
    Write-Warning 'No AcceptMessagesOnlyFrom entries were discovered.'
}
