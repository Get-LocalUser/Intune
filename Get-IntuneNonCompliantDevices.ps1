# Microsoft Graph Beta
if (-not (Get-InstalledModule -Name Microsoft.Graph.Beta)) {
    Write-Host "Installing Graph module. This will take a few minutes..." -ForegroundColor Yellow
    Install-Module -Name Microsoft.Graph.Beta -Scope CurrentUser -Force -Verbose
}
Import-Module Microsoft.Graph.Beta -ErrorAction Ignore
Write-Host "Graph module imported successfully." -ForegroundColor Yellow

Connect-MgGraph -Scopes "DeviceManagementManagedDevices.Read.All" -NoWelcome

$devices = Get-MgBetaDeviceManagementManagedDevice -All | Where-Object { $_.ComplianceState -eq "noncompliant" } ` |
    Select-Object ComplianceState, DeviceName, SerialNumber, UserDisplayName, UserPrincipalName | Sort-Object ComplianceState -Descending

$question = Read-Host "Export to CSV?"
if ($question -match "^(y|yes)$") {
    try {
        $devices | Export-Csv -Path "$env:USERPROFILE\Downloads\NonCompliant_Devices.csv" -NoTypeInformation -ErrorAction Stop
        Write-Host "CSV exported to $env:USERPROFILE\Downloads"
    }
    catch {
        Write-Host "Export failed: $($_.Exception.Message)"
    }
} else {
    $devices | Format-Table
    Exit
}