<#
.NOTES
    - Requires Microsoft.Graph.Beta module installed (will auto-install if missing).
    - CSV must contain a column named "Serial Number".
    - iOS devices are not in Active Directory — AD removal is not performed.
    - iOS devices are not in Autopilot — Autopilot removal is not performed.
    - Device names in Intune follow the pattern: iPhone-{Serial}-NamedUser
    - I recommend installing the Microsoft.Graph.Beta module with -Verbose on its own outside the script for best results.

    Author:       Get-LocalUser
    Last Updated: 04/28/2026

.SYNOPSIS
    iOS Device Removal Script - Searches for and deletes iOS device records across Intune & Entra ID by serial number.

.DESCRIPTION
    This script allows administrators to search and delete one or more iOS devices by serial number.
    It constructs the Intune device name using the pattern "iPhone-{Serial}-NamedUser" and
    removes devices across:
        - Microsoft Intune via Microsoft Graph Beta API
        - Entra ID (Azure AD)

    You can run the script interactively, pass a single serial number as a parameter, or provide
    a CSV file for bulk removal. Results will display in the console and be exported to a CSV
    file in your Downloads folder if using the Bulk option.

.FUNCTIONALITY
    - Imports and verifies required modules (Microsoft.Graph.Beta).
    - Connects to Microsoft Graph (read/write scopes required).
    - Constructs Intune device name from serial as: iPhone-{Serial}-NamedUser
    - Searches for and deletes devices across Intune & Entra ID.
    - Supports both interactive and automated use.
    - Outputs results with ✓ markers or status strings.
    - Exports bulk results to CSV in the user's Downloads folder.

.EXAMPLE
    - Run the script via F5 to load functions
    - Run Remove-iOSDevice to display both options
    - Run Remove-SingleiOSDevice for just one device removal
    - Run Remove-BulkiOSDevices to remove multiple devices from CSV

#>


# ------------------------ Logging ------------------------

$logpath = "$($env:USERPROFILE)\Downloads"
if (-not (Test-Path -Path $logpath)) {
    New-Item -Path $logpath -ItemType Directory -Force
}
$logname = (Get-Date -Format "yyyy-MM-dd_HH-mm") + "_iOS-Remove-script.log"
Start-Transcript -Path "$logpath\$logname" -Verbose

# ------------------------ Module Initialization ------------------------
function Initialize-iOSRemoveModules {
    if ($Global:iOSRemoveScriptInitialized) {
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

    Connect-MgGraph -Scopes "DeviceManagementManagedDevices.ReadWrite.All", "Device.Read.All", "Device.ReadWrite.All" -NoWelcome

    $Global:iOSRemoveScriptInitialized = $true
    Write-Host "Modules initialized." -ForegroundColor Yellow
}

# ------------------------------ End of Modules ------------------------------


function Remove-SingleiOSDevice {
    param([string]$Serial)

    if (-not $Serial) {
        $Serial = Read-Host "Enter the serial number of the iOS device"
    }

    $Serial = $Serial.Trim()
    $DeviceName = "iPhone-$Serial-NamedUser"

    $deviceresult = [PSCustomObject]@{
        InputSerial    = $Serial
        ConstructedName = $DeviceName

        # Intune
        Intune_DeviceFound     = $false
        Intune_DeviceName      = $null
        Intune_DeviceId        = $null
        Intune_AzureADDeviceId = $null
        Intune_Deleted         = $false

        # Entra ID
        EntraID_DeviceFound = $false
        EntraID_DeviceName  = $null
        EntraID_Deleted     = $false
    }

    Write-Host "Processing: $DeviceName" -ForegroundColor Yellow

    # --- Intune ---
    Write-Host "Checking Intune for $DeviceName..." -ForegroundColor Yellow
    $IntuneResults = Get-MgBetaDeviceManagementManagedDevice -Filter "deviceName eq '$DeviceName'" -ErrorAction SilentlyContinue

    if ($IntuneResults.Count -gt 1) {
        Write-Host "`nMultiple Intune devices found for serial '$Serial'. Verify entries before deleting.`n" -ForegroundColor Red
        $IntuneResults | ForEach-Object { Write-Host "Intune: $($_.DeviceName)" }
    }
    elseif ($IntuneResults) {
        $deviceresult.Intune_DeviceFound     = $true
        $deviceresult.Intune_DeviceName      = $IntuneResults.DeviceName
        $deviceresult.Intune_DeviceId        = $IntuneResults.Id
        $deviceresult.Intune_AzureADDeviceId = $IntuneResults.AzureADDeviceId

        Write-Host "$DeviceName found in Intune." -ForegroundColor Yellow
        try {
            Remove-MgBetaDeviceManagementManagedDevice -ManagedDeviceId $IntuneResults.Id -ErrorAction Stop
            Write-Host "$DeviceName removed from Intune." -ForegroundColor Green
            $deviceresult.Intune_Deleted = $true
        } catch {
            Write-Host "Failed to remove $DeviceName from Intune: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    else {
        Write-Host "$DeviceName NOT found in Intune." -ForegroundColor Red
    }

    # --- Entra ID ---
    Write-Host "Checking Entra ID for $DeviceName..." -ForegroundColor Yellow
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

            Write-Host "$DeviceName found in Entra ID." -ForegroundColor Yellow
            try {
                Remove-MgBetaDevice -DeviceId $EntraResults.Id -ErrorAction Stop
                Write-Host "$DeviceName removed from Entra ID." -ForegroundColor Green
                $deviceresult.EntraID_Deleted = $true
            } catch {
                Write-Host "Failed to remove $DeviceName from Entra ID: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        else {
            Write-Host "$DeviceName NOT found in Entra ID." -ForegroundColor Red
        }
    }
    else {
        Write-Host "No AzureADDeviceId found for $DeviceName in Intune. Cannot search Entra ID." -ForegroundColor Yellow
    }

    # Display results
    $Check = "✓"
    $output = [PSCustomObject]@{
        Serial          = $deviceresult.InputSerial
        ConstructedName = $deviceresult.ConstructedName
        Intune          = if ($deviceresult.Intune_Deleted)  { $Check } elseif ($deviceresult.Intune_DeviceFound)  { "Found - Not Deleted" } else { "Not Found" }
        EntraID         = if ($deviceresult.EntraID_Deleted) { $Check } elseif ($deviceresult.EntraID_DeviceFound) { "Found - Not Deleted" } else { "Not Found" }
    }

    $output | Format-Table -AutoSize

    return $deviceresult
}


function Remove-BulkiOSDevices {
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

            $deviceInfo = Remove-SingleiOSDevice -Serial $Serial

            $Check = "✓"
            $result = [PSCustomObject]@{
                Serial          = $Serial
                ConstructedName = $deviceInfo.ConstructedName
                IntuneStatus    = if ($deviceInfo.Intune_Deleted)  { $Check } elseif ($deviceInfo.Intune_DeviceFound)  { "Found - Not Deleted" } else { "Not Found" }
                EntraIDStatus   = if ($deviceInfo.EntraID_Deleted) { $Check } elseif ($deviceInfo.EntraID_DeviceFound) { "Found - Not Deleted" } else { "Not Found" }
            }

            $results += $result
        }
    }
    catch {
        Write-Host "Error processing CSV: $($_.Exception.Message)" -ForegroundColor Red
    }

    # Print results and export to a CSV in the user's Downloads folder
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
    $Pathway = "C:\Users\$env:USERNAME\Downloads\"
    $ExportFile = Join-Path -Path $Pathway -ChildPath "iOSDevicesRemoved_$timestamp.csv"

    if ($results) {
        $Utf8WithBom = New-Object System.Text.UTF8Encoding $true
        $csvContent = $results | ConvertTo-Csv -NoTypeInformation | Out-String
        [System.IO.File]::WriteAllText($ExportFile, $csvContent, $Utf8WithBom)
        Write-Host "`nResults exported to: $ExportFile" -ForegroundColor Yellow
        Write-Host "`nOpen in Excel for best visual." -ForegroundColor Magenta
        Write-Host "`nNote: Entra ID is only removed when a matching Intune object with the same AzureADDeviceId attribute exists." -ForegroundColor Blue
    }
    else {
        Write-Host "Not exported — no results." -ForegroundColor Yellow
    }

    Stop-Transcript

    return $results
}


function Remove-iOSDevice {
    Write-Host "`nSelect Removal Mode:" -ForegroundColor Cyan
    Write-Host "1. Remove Single iOS Device by Serial"
    Write-Host "2. Remove Bulk from CSV (column: 'Serial')"
    $choice = Read-Host "Enter your choice (1 or 2)"

    switch ($choice) {
        "1" {
            $serial = Read-Host "Enter the serial number"
            if ([string]::IsNullOrWhiteSpace($serial)) {
                Write-Host "No serial number provided. Exiting." -ForegroundColor Red
                Stop-Transcript
                exit
            }
            Remove-SingleiOSDevice -Serial $serial
            Stop-Transcript
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
                $allResults = Remove-BulkiOSDevices -CsvPath $csvPath
                $allResults | Format-Table -AutoSize
            }
            else {
                Write-Host "No file selected. Exiting." -ForegroundColor Red
                Stop-Transcript
                exit
            }

            $form.Dispose()
        }
        default {
            Write-Host "Invalid choice. Exiting." -ForegroundColor Red
            Stop-Transcript
            exit
        }
    }
}


# ------------------------------ Main Execution ------------------------------

# Step 1: Initialize modules first
Initialize-iOSRemoveModules

# Step 2: Run interactive mode selection
Remove-iOSDevice