# Sync iOS devices
Import-Module -Name "Microsoft.Graph.Beta" -ErrorAction Ignore
Connect-MgGraph -Scope "DeviceManagementManagedDevices.PrivilegedOperations.All", "DeviceManagementManagedDevices.ReadWrite.All", "DeviceManagementManagedDevices.Read.All" -NoWelcome
 
$Devices = Get-MgBetaDeviceManagementManagedDevice -Filter "contains(operatingsystem, 'iOS')" -All

Foreach ($Device in $Devices)
{
   Sync-MgBetaDeviceManagementManagedDevice -ManagedDeviceId $Device.Id
   Write-Host "Sending Sync request to Device with Device name $($Device.DeviceName)" -ForegroundColor Yellow
}