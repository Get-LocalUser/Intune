# Create a log
$timestamp = Get-Date -Format "MM-dd-yyyy_HH-mm-ss"
$logPath = Join-Path -Path $PSScriptRoot -ChildPath "Autopilot_Device_Removal_$timestamp.log"
Start-Transcript -Path $logPath -Append

# Check of Graph Beta module is installed
if (-not (Get-InstalledModule -Name Microsoft.Graph.Beta)) {
    Install-Module -Name Microsoft.Graph.Beta
}
Import-Module Microsoft.Graph.Beta

# Connect to Graph
Connect-MgGraph -Scopes "DeviceManagementServiceConfig.Read.All, DeviceManagementServiceConfig.ReadWrite.All,"

# Define CSV file
$CsvFile = Read-Host "Please enter the path to your CSV file"

$ImportedCsv = Import-Csv -Path $CsvFile

# Create a hashtable to store lookup results
$deviceLookup = @{}

# Iterate over the serial numbers in the CSV file
foreach ($row in $ImportedCSV) {
    $serial = $row.Serial


    if ([string]::IsNullOrWhiteSpace($serial)) {
        Write-Host "Empty serial number - skipping..."
        continue
    }

    # Get the devices in the Autopilot service
    $autopilotdevices = Get-MgBetaDeviceManagementWindowsAutopilotDeviceIdentity | Where-Object {$_.SerialNumber -eq $serial}
    $deviceLookup[$serial] = $autopilotdevices

    if ($autopilotdevices) {
        Write-Host "Serial number '$serial' FOUND in Autopilot." -ForegroundColor Green
    } else {
    Write-Host "Serial number(s) '$serial' NOT FOUND in Autopilot." -ForegroundColor Red
    }
} 

$question = Read-Host "Would you like to remove these serial numbers from Autopilot? (Y/N)"
if ($question -eq "Y") {
    foreach ($serial in $deviceLookup.Keys) {
        $autopilotdevices = $deviceLookup[$serial]
        
        # Then remove each matching device by its ID
        if ($autopilotdevices) {
            foreach ($autopilotdevice in $autopilotdevices) {
                Write-Host "Removing device with serial number '$serial'..." -ForegroundColor Yellow
                Remove-MgBetaDeviceManagementWindowsAutopilotDeviceIdentity -WindowsAutopilotDeviceIdentityId $autopilotdevice.Id
                Write-Host "Device with serial number '$serial' removed successfully." -ForegroundColor Green
            }
        } else {
            Write-Host "No serial numbers found with '$serial'. Skipping." -ForegroundColor Yellow
        }
    }
}

Write-Host "Don't forget to sign out of the graph! using 'Disconnect-MgGraph'" -ForegroundColor Cyan

Stop-Transcript
