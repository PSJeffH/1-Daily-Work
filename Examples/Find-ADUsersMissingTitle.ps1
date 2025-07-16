#requires -Modules ActiveDirectory

<#!
.SYNOPSIS
    Finds Active Directory users missing a Title.
.DESCRIPTION
    Searches Active Directory for user accounts where the Title attribute is empty or not set.
    Outputs the list of users so administrators can update the records.
!>

Get-ADUser -Filter { Title -notlike '*' } -Properties Title |
    Select-Object Name, SamAccountName, Title
