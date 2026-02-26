# Microsoft Graph Beta
if (-not (Get-InstalledModule -Name Microsoft.Graph.Beta)) {
    Write-Host "Installing Graph module. This will take a few minutes..." -ForegroundColor Yellow
    Install-Module -Name Microsoft.Graph.Beta -Scope CurrentUser -Force -Verbose
}
Import-Module Microsoft.Graph.Beta -ErrorAction Ignore
Write-Host "Graph module imported successfully." -ForegroundColor Yellow

Connect-MgGraph -Scopes "DeviceManagementManagedDevices.Read.All" -NoWelcome

$devicename = Read-Host "Enter machine name to get installed apps"

$deviceid = Get-MgBetaDeviceManagementManagedDevice -Filter "DeviceName eq '$devicename'" | Select-Object -ExpandProperty Id

Get-MgBetaDeviceManagementManagedDeviceDetectedApp -ManagedDeviceId $deviceid | Select-Object DisplayName, Publisher, Version