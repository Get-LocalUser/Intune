<#
.NOTES
    - Requires Microsoft.Graph.Beta module installed (will auto-install if missing).
    - CSV must contain a column named "Serial Number".
    - iOS devices are not in Active Directory — AD lookup is not performed.
    - Device names in Intune follow the pattern: iPhone-{Serial}-NamedUser
    - I recommend installing the Microsoft.Graph.Beta module with -Verbose on its own outside the script for best results.

    Author:       Get-LocalUser
    Last Updated: 04/2x/2026

.SYNOPSIS
    iOS Device Lookup Script - Searches for iOS device records across Entra ID & Intune by serial number.

.DESCRIPTION
    This script allows administrators to search for one or more iOS devices by serial number.
    It constructs the Intune device name using the pattern "iPhone-{Serial}-NamedUser" and
    searches across:
        - Intune
        - Entra ID

    You can run the script interactively, pass a single serial number as a parameter, or provide
    a CSV file for bulk searching. Results will display in the console and be exported to a CSV
    file in your Downloads folder if using the Bulk option.

.FUNCTIONALITY
    - Imports and verifies required modules (Microsoft.Graph.Beta).
    - Connects to Microsoft Graph ('Device.Read.All' scope required).
    - Constructs Intune device name from serial as: iPhone-{Serial}-NamedUser
    - Searches for devices across Intune & Entra ID.
    - Supports both interactive and automated use.
    - Outputs results with ✓ markers or 'False'.
    - Exports bulk results to CSV in the user's Downloads folder.

.EXAMPLE
    - Run the script via F5 to load functions
    - Run Find-iOSDevice to display both options
    - Run Search-SingleiOSDevice for just one device lookup
    - Run Search-BulkiOSDevices to lookup multiple devices from CSV

#>

# ------------------------ Module Initialization ------------------------
function Initialize-iOSModules {
    if ($Global:iOSDeviceScriptInitialized) {
        Write-Host "Modules already initialized. Skipping module checks." -ForegroundColor Green
        return
    }

    # Microsoft Graph Beta
    if (-not (Get-InstalledModule -Name Microsoft.Graph.Beta -ErrorAction SilentlyContinue)) {
        Write-Host "Installing Graph module. This will take a few minutes..." -ForegroundColor Yellow
        Install-Module -Name Microsoft.Graph.Beta -Scope CurrentUser -Force -Verbose
    }
    Import-Module Microsoft.Graph.Beta -ErrorAction Ignore
    Write-Host "Graph module imported successfully." -ForegroundColor Yellow

    Connect-MgGraph -Scopes "Device.Read.All" -NoWelcome

    $Global:iOSDeviceScriptInitialized = $true
    Write-Host "Modules initialized." -ForegroundColor Yellow
}

# ------------------------------ End of Modules ------------------------------

function Search-SingleiOSDevice {
    param([string]$Serial)

    if (-not $Serial) {
        $Serial = Read-Host "Enter the serial number of the iOS device"
    }

    $Serial = $Serial.Trim()
    $DeviceName = "iPhone-$Serial-NamedUser"

    $deviceresult = [PSCustomObject]@{
        InputSerial = $Serial
        ConstructedName = $DeviceName

        # Intune
        Intune_DeviceFound      = $false
        Intune_DeviceName       = $null
        Intune_SerialNumber     = $null
        Intune_AzureADDeviceId  = $null

        # Entra ID
        EntraID_DeviceFound     = $false
        EntraID_DeviceName      = $null
    }

    Write-Host "Searching for: $DeviceName" -ForegroundColor Yellow

    # Get Intune device by constructed name
    $IntuneResults = Get-MgBetaDeviceManagementManagedDevice -Filter "deviceName eq '$DeviceName'"

    if ($IntuneResults.Count -gt 1) {
        Write-Host "`nMultiple Intune devices found for serial '$Serial'. Verify entries before deleting.`n" -ForegroundColor Red
        $IntuneResults | ForEach-Object { Write-Host "Intune: $($_.DeviceName)" }
    }
    elseif ($IntuneResults) {
        $deviceresult.Intune_DeviceFound     = $true
        $deviceresult.Intune_DeviceName      = $IntuneResults.DeviceName
        $deviceresult.Intune_SerialNumber    = $IntuneResults.SerialNumber
        $deviceresult.Intune_AzureADDeviceId = $IntuneResults.AzureADDeviceId
    }

    # Get Entra ID device matched by AzureADDeviceId from Intune
    if ($deviceresult.Intune_AzureADDeviceId) {
        try {
            $EntraResults = Get-MgBetaDevice -Filter "deviceId eq '$($deviceresult.Intune_AzureADDeviceId)'" -ErrorAction Stop
        }
        catch {
            $EntraResults = $null
        }

        if ($EntraResults) {
            $deviceresult.EntraID_DeviceFound = $true
            $deviceresult.EntraID_DeviceName  = $EntraResults.DisplayName
        }
    }

    # Display results
    if ($deviceresult.Intune_DeviceFound -or $deviceresult.EntraID_DeviceFound) {
        Write-Host "Device found in one or more systems." -ForegroundColor Yellow
    }
    else {
        Write-Host "No devices found for serial: $Serial" -ForegroundColor Red
    }

    $Check = "✓"
    $output = [PSCustomObject]@{
        Serial          = $deviceresult.InputSerial
        ConstructedName = $deviceresult.ConstructedName
        Intune          = if ($deviceresult.Intune_DeviceFound)  { $Check } else { "False" }
        EntraID         = if ($deviceresult.EntraID_DeviceFound) { $Check } else { "False" }
    }

    $output | Format-Table -AutoSize

    return $deviceresult
}


function Search-BulkiOSDevices {
    param([string]$CsvPath)

    if (-not (Test-Path $CsvPath)) {
        Write-Host "CSV file not found: $CsvPath" -ForegroundColor Red
        return
    }

    try {
        $devices = Import-Csv $CsvPath
        Write-Host "`nProcessing $($devices.Count) devices from CSV..." -ForegroundColor Yellow

        $results = @()
        $counter = 0

        foreach ($row in $devices) {
            $counter++
            $Serial = $row.'Serial'

            if ([string]::IsNullOrWhiteSpace($Serial)) {
                Write-Host "[$counter/$($devices.Count)] Skipping empty serial number" -ForegroundColor Yellow
                continue
            }

            Write-Host "[$counter/$($devices.Count)] $Serial" -ForegroundColor Cyan

            $deviceInfo = Search-SingleiOSDevice -Serial $Serial

            $Check = "✓"
            $result = [PSCustomObject]@{
                Serial          = $Serial
                ConstructedName = $deviceInfo.ConstructedName
                Intune          = if ($deviceInfo.Intune_DeviceFound)  { $Check } else { "False" }
                EntraID         = if ($deviceInfo.EntraID_DeviceFound) { $Check } else { "False" }
            }

            $results += $result
        }
    }
    catch {
        Write-Host "Error processing CSV: $($_.Exception.Message)" -ForegroundColor Red
    }

    # Print results and export to a CSV in the user's Downloads folder
    $Pathway = "C:\Users\$env:USERNAME\Downloads\"
    $ExportFile = Join-Path -Path $Pathway -ChildPath "iOSDevicesFound.csv"

    if ($results) {
        $Utf8WithBom = New-Object System.Text.UTF8Encoding $true
        $csvContent = $results | ConvertTo-Csv -NoTypeInformation | Out-String
        [System.IO.File]::WriteAllText($ExportFile, $csvContent, $Utf8WithBom)
        Write-Host "`nResults exported to: $ExportFile" -ForegroundColor Yellow
        Write-Host "`nOpen in Excel for best visual." -ForegroundColor Magenta
        Write-Host "`nNote: Entra ID is only returned when a matching Intune object with the same AzureADDeviceId attribute exists." -ForegroundColor Blue
    }
    else {
        Write-Host "Not exported — no results." -ForegroundColor Yellow
    }

    return $results
}


function Find-iOSDevice {
    Write-Host "`nSelect Search Mode:" -ForegroundColor Cyan
    Write-Host "1. Search Single iOS Device by Serial"
    Write-Host "2. Search Bulk from CSV (column: 'Serial')"
    $choice = Read-Host "Enter your choice (1 or 2)"

    switch ($choice) {
        "1" {
            $serial = Read-Host "Enter the serial number"
            if ([string]::IsNullOrWhiteSpace($serial)) {
                Write-Host "No serial number provided. Exiting." -ForegroundColor Red
                exit
            }
            Search-SingleiOSDevice -Serial $serial
        }
        "2" {
            Add-Type -AssemblyName System.Windows.Forms

            $form = New-Object System.Windows.Forms.Form
            $form.TopMost = $true
            $form.WindowState = 'Minimized'
            $form.ShowInTaskbar = $false

            $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
            $openFileDialog.Filter = "CSV files (*.csv)|*.csv|All files (*.*)|*.*"
            $openFileDialog.Title = "Select the CSV file"
            $openFileDialog.InitialDirectory = [Environment]::GetFolderPath("Desktop")

            if ($openFileDialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
                $csvPath = $openFileDialog.FileName
                $allResults = Search-BulkiOSDevices -CsvPath $csvPath
                $allResults | Format-Table -AutoSize
            }
            else {
                Write-Host "No file selected. Exiting." -ForegroundColor Red
                exit
            }

            $form.Dispose()
        }
    }
}


# ------------------------------ Main Execution ------------------------------

# Step 1: Initialize modules first
Initialize-iOSModules

# Step 2: Run interactive mode selection
Find-iOSDevice