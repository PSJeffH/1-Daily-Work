# Requires: ActiveDirectory module and ImportExcel module (Install-Module ImportExcel -Scope CurrentUser)

Import-Module ActiveDirectory
Import-Module ImportExcel

$timestamp = Get-Date -Format "yyyyMMdd-HHmm"
$outputPath = "C:\AuditReports"
$excelFile = "$outputPath\DepartmentAudit-$timestamp.xlsx"
$htmlFile = "$outputPath\DepartmentAudit-$timestamp.html"

if (-not (Test-Path $outputPath)) {
    New-Item -Path $outputPath -ItemType Directory -Force
}

# Step 1: Get AD users and department info
$users = Get-ADUser -Filter * -Properties Department, DisplayName, Title, EmailAddress, Enabled |
    Select-Object Name, SamAccountName, Department, Title, EmailAddress, Enabled

# Step 2: Group and count by Department
$grouped = $users | Group-Object Department | Sort-Object Count -Descending

# Step 3: Summary stats
$summary = [PSCustomObject]@{
    Timestamp            = $timestamp
    TotalDepartments     = ($grouped | Where-Object { $_.Name -ne $null }).Count
    TotalUsers           = $users.Count
    DisabledUsers        = ($users | Where-Object { -not $_.Enabled }).Count
    UnassignedDepartment = ($users | Where-Object { [string]::IsNullOrWhiteSpace($_.Department) }).Count
}

# Step 4: Export Excel with Pivot Table
$users | Export-Excel -Path $excelFile -WorksheetName 'RawData' -AutoSize -TableName 'UserData'

$excelPkg = Open-ExcelPackage -Path $excelFile
Add-PivotTable -ExcelPackage $excelPkg -SourceWorkSheet 'RawData' -PivotTableName 'DeptSummary' -Address "I1" `
    -RowFields Department -DataField @{ Name = 'SamAccountName'; Function = 'Count' }

Close-ExcelPackage $excelPkg

# Step 5: Create HTML Summary
$htmlContent = @"
<html>
<head>
    <title>Department Audit Report</title>
    <style>
        body { font-family: Arial; margin: 20px; }
        table, th, td { border: 1px solid black; border-collapse: collapse; padding: 5px; }
        th { background-color: #f2f2f2; }
        h2 { color: #2a3f5f; }
    </style>
</head>
<body>
    <h2>Department Audit Summary</h2>
    <p><strong>Generated:</strong> $($summary.Timestamp)</p>
    <table>
        <tr><th>Total Users</th><td>$($summary.TotalUsers)</td></tr>
        <tr><th>Total Departments</th><td>$($summary.TotalDepartments)</td></tr>
        <tr><th>Disabled Users</th><td>$($summary.DisabledUsers)</td></tr>
        <tr><th>Users Without Department</th><td>$($summary.UnassignedDepartment)</td></tr>
    </table>

    <h2>Department Breakdown</h2>
    <table>
        <tr><th>Department</th><th>User Count</th></tr>
"@

foreach ($entry in $grouped) {
    $dept = if ($entry.Name) { $entry.Name } else { "<i>Unassigned</i>" }
    $htmlContent += "<tr><td>$dept</td><td>$($entry.Count)</td></tr>`n"
}

$htmlContent += @"
    </table>
</body>
</html>
"@

$htmlContent | Out-File -FilePath $htmlFile -Encoding UTF8

Write-Host "✅ HTML report: $htmlFile"
Write-Host "✅ Excel report: $excelFile"
