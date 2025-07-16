#requires -Modules ActiveDirectory

<#!
.SYNOPSIS
    Sets extension attributes for newly created Active Directory users.
.DESCRIPTION
    Searches Active Directory for user accounts created within the last week.
    If a user's employeeID begins with "10" the script sets values on
    extensionAttribute1, extensionAttribute2 and extensionAttribute3.
!>

$LastWeek = (Get-Date).AddDays(-7)

# Extension attribute values to apply
$attributes = @{
    extensionAttribute1 = 'Value1'
    extensionAttribute2 = 'Value2'
    extensionAttribute3 = 'Value3'
}

$NewUsers = Get-ADUser -Filter * -Properties whenCreated, employeeID | Where-Object {
    $_.whenCreated -ge $LastWeek -and $_.employeeID -like '10*'
}

foreach ($user in $NewUsers) {
    Set-ADUser -Identity $user -Replace $attributes
}
