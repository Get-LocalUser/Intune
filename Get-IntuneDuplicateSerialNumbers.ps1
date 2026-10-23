Connect-MgGraph -Scopes "DeviceManagementManagedDevices.Read.All" -NoWelcome

$allDevices = Get-MgBetaDeviceManagementManagedDevice -All

$duplicateSerials = $allDevices | Group-Object -Property SerialNumber | Where-Object Count -gt 1

$results = foreach ($group in $duplicateSerials) {
    foreach ($device in $group.Group) {
        [PSCustomObject]@{
            DisplayName = $device.DeviceName
            Serial      = $device.SerialNumber
            OS          = $device.OperatingSystem
            Type        = $device.Model
            LastSync    = $device.LastSyncDateTime
            Compliance  = $device.ComplianceState
        }
    }
} 

$results | Export-Csv -Path "C:\Temp\duplicatedevices.csv" -NoTypeInformation