# Create a log
$timestamp = Get-Date -Format "MM-dd-yyyy_HH-mm-ss"
$logPath = Join-Path -Path $PSScriptRoot -ChildPath "Intune_Device_Removal_$timestamp.log"
Start-Transcript -Path $logPath -Append

# Ensure the Microsoft.Graph module is installed
if (-not (Get-InstalledModule -Name Microsoft.Graph.Beta)) {
    Install-Module -Name Microsoft.Graph.Beta
}
Import-Module Microsoft.Graph.Beta

# Connect to Microsoft Graph
Connect-MgGraph -Scopes "Device.Read.All", "DeviceManagementManagedDevices.ReadWrite.All"

# Prompt for CSV file path
$CsvFile = Read-Host "Please enter the path to your CSV file"
if (-not (Test-Path -Path $CsvFile)) {
    Write-Host "The file path provided does not exist. Exiting script." -ForegroundColor Red
    Stop-Transcript
    exit
}
$ImportedCsv = Import-Csv -Path $CsvFile

# Retrieve all managed devices
Write-Host "Retrieving all managed devices from Intune..." -ForegroundColor Cyan
$allDevices = Get-MgBetaDeviceManagementManagedDevice -All

# Create a hashtable to store lookup results
$deviceLookup = @{}

# Iterate over the asset tags in the CSV file
foreach ($row in $ImportedCsv) {
    $assetTag = $row.AssetTag

    if ([string]::IsNullOrWhiteSpace($assetTag)) {
        Write-Host "Empty asset tag - skipping..." -ForegroundColor Yellow
        continue
    }

    # Perform case-insensitive comparison
    $matchedDevices = $allDevices | Where-Object { $_.DeviceName -eq $assetTag }

    $deviceLookup[$assetTag] = $matchedDevices

    if ($matchedDevices) {
        Write-Host "Device '$assetTag' FOUND in Intune." -ForegroundColor Green
    } else {
        Write-Host "Device '$assetTag' NOT FOUND in Intune." -ForegroundColor Red
    }
}

$question = Read-Host "Would you like to remove these devices from Intune? (Y/N)"
if ($question -eq "Y") {
    foreach ($assetTag in $deviceLookup.Keys) {
        $devices = $deviceLookup[$assetTag]
        
        if ($devices) {
            foreach ($device in $devices) {
                Write-Host "Removing device with asset tag '$assetTag'..." -ForegroundColor Yellow
                Remove-MgBetaDeviceManagementManagedDevice -ManagedDeviceId $device.Id
                Write-Host "Device with asset tag '$assetTag' removed successfully." -ForegroundColor Green
            }
        } else {
            Write-Host "No devices found with asset tag '$assetTag'. Skipping." -ForegroundColor Yellow
        }
    }
}

Write-Host "Operation completed. Don't forget to sign out of Microsoft Graph using 'Disconnect-MgGraph'." -ForegroundColor Cyan

Stop-Transcript
