# Run these if you havent used MS Graph before
#Install-Module -Name Microsoft.Graph.DeviceManagement.Actions -Force  -AllowClobber
#Install-Module -Name Microsoft.Graph.DeviceManagement -Force -AllowClobber
 
# Run below this line for normal iOS check ins
# Importing the SDK Module
#Import-Module -Name Microsoft.Graph.DeviceManagement.Actions
 
Import-Module -Name "Microsoft.Graph.Beta"
Connect-MgGraph -Scope "DeviceManagementManagedDevices.PrivilegedOperations.All", "DeviceManagementManagedDevices.ReadWrite.All", "DeviceManagementManagedDevices.Read.All" -NoWelcome
 
#### Gets All devices
$Devices = Get-MgBetaDeviceManagementManagedDevice -Filter "contains(operatingsystem, 'iOS')" -All

Foreach ($Device in $Devices)
{
   Sync-MgBetaDeviceManagementManagedDevice -ManagedDeviceId $Device.Id
   Write-Host "Sending Sync request to Device with Device name $($Device.DeviceName)" -ForegroundColor Yellow
}