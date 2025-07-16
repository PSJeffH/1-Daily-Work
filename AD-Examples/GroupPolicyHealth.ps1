<#
.SYNOPSIS
    Validates Group Policy objects and link status across the domain.
.DESCRIPTION
    Checks that GPOs are linked and applied correctly and highlights any permission inconsistencies.
#>

Import-Module GroupPolicy
Import-Module ActiveDirectory

Write-Host "=== Group Policy Health ===" -ForegroundColor Cyan
$gpos = Get-GPO -All
foreach ($gpo in $gpos) {
    $links = Get-GPOLink -Guid $gpo.Id -ErrorAction SilentlyContinue
    if (-not $links) {
        Write-Warning "$($gpo.DisplayName) has no links"
    }
}

$permissionIssues = @()
foreach ($gpo in $gpos) {
    $acl = Get-GPPermission -Guid $gpo.Id -All
    if ($acl | Where-Object { $_.Permission -eq 'GpoApply' -and $_.Denied }) {
        $permissionIssues += $gpo.DisplayName
    }
}

if ($permissionIssues) {
    Write-Host "\nGPOs with permission issues:" -ForegroundColor Yellow
    $permissionIssues
} else {
    Write-Host "\nNo permission issues found." -ForegroundColor Green
}
