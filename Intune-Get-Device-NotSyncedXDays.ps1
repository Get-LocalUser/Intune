# Microsoft Graph Beta
if (-not (Get-InstalledModule -Name Microsoft.Graph.Beta)) {
    Write-Host "Installing Graph module. This will take a few minutes..." -ForegroundColor Yellow
    Install-Module -Name Microsoft.Graph.Beta -Scope CurrentUser -Force -Verbose
}
Import-Module Microsoft.Graph.Beta -ErrorAction Ignore
Write-Host "Graph module imported successfully." -ForegroundColor Yellow

Connect-MgGraph -Scopes "DeviceManagementManagedDevices.Read.All" -NoWelcome

$days = (Get-Date).AddDays(-30) # Change nmumber to check sync time x days back
$devices = Get-MgBetaDeviceManagementManagedDevice -All | Where-Object { $_.LastSyncDateTime -lt $days } | `
    Select-Object OperatingSystem, DeviceName, SerialNumber, UserDisplayName, UserPrincipalName

$question = Read-Host "Export to CSV?"
if ($question -match "^(y|yes)$") {
    try {
        $devices | Export-Csv -Path "$env:USERPROFILE\Downloads\NotSynced_Devices.csv" -NoTypeInformation -ErrorAction Stop
        Write-Host "CSV exported to $env:USERPROFILE\Downloads"
    }
    catch {
        Write-Host "Export failed: $($_.Exception.Message)"
    }
} else {
    $devices | Format-Table
    Exit
}