<#
.NOTES
    - Requires RSAT: Active Directory tools installed.
    - Requires Microsoft.Graph.Beta module installed (will auto-install if missing).
    - CSV must contain a column named "Asset Tag".
    - Might add the ability to remove the device object from EntraID in the future but might just use the DeviceOffboardingManager instead from ugurkocde

    Author:       get-LocalUser
    Last Updated: 08/22/2025

.SYNOPSIS
    Device Deletion Script - Searches for computer records across Active Directory, Intune, & Autopilot and deletes them.

.DESCRIPTION
    This script allows administrators to search and delete for one or more devices by name or asset tag
    across three platforms:
        - Active Directory AD
        - Microsoft Intune via Microsoft Graph Beta API
        - Windows Autopilot via Microsoft Graph Beta API

    You can run the script interactively, pass a single computer name as a parameter, or provide
    a CSV file for bulk searching. Results will display in the console and optionally be exported
    to a CSV file in your Downloads folder.

.FUNCTIONALITY
    - Imports and verifies required modules (ActiveDirectory, Microsoft.Graph.Beta).
    - Connects to Microsoft Graph ("DeviceManagementServiceConfig.Read.All", "DeviceManagementServiceConfig.ReadWrite.All" scopes required).
    - Searches for and deletes devices across AD, Intune, & Autopilot.
    - Supports both interactive and automated use.
    - Outputs results with ✓ markers or 'False'.
    - Exports bulk results to CSV in the user's Downloads folder.
    - Asks whether to disconnect from Microsoft Graph after completion.
#>





# ------------------------ Logging ------------------------

$logpath = "$($env:USERPROFILE)\Downloads"
if (-not (Test-Path -Path $logpath)) {
    New-Item -Path $logpath -ItemType Directory -Force
}
$logname = (Get-Date -Format "yyyy-MM-dd_HH-mm") + "_script.log"
Start-Transcript -Path "$logpath\$logname" -Verbose

# ------------------------ Module Initialization ------------------------
function Initialize-Modules {
    if ($Global:DeviceScriptInitialized) {
        Write-Host "Modules already initialized. Skipping module checks." -ForegroundColor Green
        return
    }

    # -------------------- Install & Import Modules ---------------------
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        Write-Host "ActiveDirectory module not found. Please install RSAT: Active Directory." -ForegroundColor Red
        return
    }
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Host "ActiveDirectory module imported successfully." -ForegroundColor Yellow

    if (-not (Get-InstalledModule -Name Microsoft.Graph.Beta -ErrorAction SilentlyContinue)) {
        Write-Host "Installing Graph module. This will take a few minutes..." -ForegroundColor Yellow
        Install-Module -Name Microsoft.Graph.Beta -Scope CurrentUser -Force -Verbose
    }
    Import-Module Microsoft.Graph.Beta -ErrorAction Ignore
    Write-Host "Graph module imported successfully." -ForegroundColor Yellow

    Connect-MgGraph -Scopes "DeviceManagementServiceConfig.Read.All", "DeviceManagementServiceConfig.ReadWrite.All" -NoWelcome

    $Global:DeviceScriptInitialized = $true
    Write-Host "Modules initialized." -ForegroundColor Yellow
}

# ------------------------------ End of Modules ------------------------------



function Delete-SingleComputer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Type in the P number/hostname of the computer")]
        [string]$assetTag
    )
    
    # --- Active Directory ---
    Write-Host "Checking Active Directory for $assetTag..." -ForegroundColor Yellow
    try {
        $adComputer = Get-ADComputer -Identity $assetTag -ErrorAction Stop
    } catch {
        $adComputer = $null
    }
    
    if (-not $adComputer) {
        Write-Host "$assetTag NOT found in Active Directory" -ForegroundColor Red
    } else {
        Write-Host "$assetTag found in Active Directory" -ForegroundColor Yellow
        try {
            Remove-ADObject -Identity $adComputer.DistinguishedName -Recursive -Confirm:$true -ErrorAction Stop
            Write-Host "$assetTag Deleted from AD" -ForegroundColor Green
        } catch {
            Write-Host "Failed to delete $assetTag from AD" -ForegroundColor Red
        }
    }
    
    # --- Intune ---
    Write-Host "Checking Intune for $assetTag..." -ForegroundColor Yellow
    try {
        $matchedDevice = Get-MgBetaDeviceManagementManagedDevice -Filter "deviceName eq '$assetTag'" -ErrorAction Stop
    } catch {
        $matchedDevice = $null
    }
    
    if (-not $matchedDevice) {
        Write-Host "$assetTag NOT found in Intune" -ForegroundColor Red
        return  # Early exit since no device found
    }
    
    # Device found in Intune
    Write-Host "$assetTag found in Intune" -ForegroundColor Yellow
    try {
        Remove-MgBetaDeviceManagementManagedDevice -ManagedDeviceId $matchedDevice.Id -ErrorAction Stop
        Write-Host "$assetTag removed from Intune." -ForegroundColor Green
    } catch {
        Write-Host "Failed to remove $assetTag from Intune: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    # --- Autopilot ---
    if (-not $matchedDevice.SerialNumber) {
        Write-Host "No serial number found for device in Intune." -ForegroundColor Yellow
        return
    }
    
    Write-Host "Checking Autopilot for serial number $($matchedDevice.SerialNumber)..." -ForegroundColor Yellow
    try {
        $autopilotDevice = Get-MgBetaDeviceManagementWindowsAutopilotDeviceIdentity -Filter "serialNumber eq '$($matchedDevice.SerialNumber)'" -ErrorAction Stop
    } catch {
        $autopilotDevice = $null
    }
    
    if (-not $autopilotDevice) {
        Write-Host "No Autopilot record found for serial $($matchedDevice.SerialNumber)" -ForegroundColor Red
        return
    }
    
    # Autopilot device found - try to delete
    try {
        Remove-MgBetaDeviceManagementWindowsAutopilotDeviceIdentity -WindowsAutopilotDeviceIdentityId $autopilotDevice.Id -ErrorAction Stop
        Write-Host "Autopilot record for $($matchedDevice.SerialNumber) deleted." -ForegroundColor Green
    } catch {
        Write-Host "Failed to delete from Autopilot: $($_.Exception.Message)" -ForegroundColor Red
    }
}


# ------------------------------ Bulk Option ------------------------------


function Delete-ComputerBulk {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$CsvPath
    )

    # --- File Picker UI if path not provided ---
    if (-not $CsvPath) {
        Add-Type -AssemblyName System.Windows.Forms
        $fileDialog = New-Object System.Windows.Forms.OpenFileDialog
        $fileDialog.Filter = "CSV files (*.csv)|*.csv|All files (*.*)|*.*"
        $fileDialog.Title = "Select the CSV file with computers to delete"
        $fileDialog.InitialDirectory = [Environment]::GetFolderPath("Desktop")

        if ($fileDialog.ShowDialog() -eq "OK") {
            $CsvPath = $fileDialog.FileName
        } else {
            Write-Host "No file selected. Exiting bulk delete." -ForegroundColor Red
            return
        }
    }

    # --- Import CSV and initialize ---
    $ImportedCSV = Import-Csv $CsvPath
    $counter = 0
    $results = @()

    foreach ($row in $ImportedCSV) {
        $counter++
        $ComputerName = $row.'Asset Tag'
        $result = [PSCustomObject]@{
            ComputerName    = $ComputerName
            ADStatus        = "Not Attempted"
            IntuneStatus    = "Not Attempted"
            AutopilotStatus = "Not Attempted"
        }

        if ([string]::IsNullOrWhiteSpace($ComputerName)) {
            Write-Host "[$counter/$($ImportedCSV.Count)] Skipping empty computer name" -ForegroundColor Yellow
            $result.ADStatus = "Skipped - Empty"
            $results += $result
            continue
        }

        Write-Host "[$counter/$($ImportedCSV.Count)] Processing '$ComputerName'" -ForegroundColor Cyan

        # --- Active Directory ---
        Write-Host "[$counter] Checking Active Directory for $ComputerName..." -ForegroundColor Yellow
        try {
            $adComputer = Get-ADComputer -Identity $ComputerName -ErrorAction SilentlyContinue
        } catch {
            $adComputer = $null
        }
        
        if (-not $adComputer) {
            Write-Host "[$counter] $ComputerName NOT found in Active Directory" -ForegroundColor Red
            $result.ADStatus = "Not Found"
        } else {
            try {
                Remove-ADObject -Identity $adComputer.DistinguishedName -Recursive -Confirm:$false -ErrorAction SilentlyContinue
                Write-Host "[$counter] $ComputerName Deleted from AD" -ForegroundColor Green
                $result.ADStatus = "Deleted"
            } catch {
                Write-Host "[$counter] Failed to delete $ComputerName from AD: $($_.Exception.Message)" -ForegroundColor Red
                $result.ADStatus = "Error: $($_.Exception.Message)"
            }
        }

        # --- Intune ---
        Write-Host "[$counter] Checking Intune for $ComputerName..." -ForegroundColor Yellow
        try {
            $matchedDevice = Get-MgBetaDeviceManagementManagedDevice -Filter "deviceName eq '$ComputerName'" -ErrorAction SilentlyContinue
        } catch {
            $matchedDevice = $null
        }
        
        if (-not $matchedDevice) {
            Write-Host "[$counter] $ComputerName NOT found in Intune" -ForegroundColor Red
            $result.IntuneStatus = "Not Found"
            $results += $result
            continue
        }

        try {
            Remove-MgBetaDeviceManagementManagedDevice -ManagedDeviceId $matchedDevice.Id -ErrorAction SilentlyContinue
            Write-Host "[$counter] $ComputerName removed from Intune." -ForegroundColor Green
            $result.IntuneStatus = "Deleted"
        } catch {
            Write-Host "[$counter] Failed to remove $ComputerName from Intune: $($_.Exception.Message)" -ForegroundColor Red
            $result.IntuneStatus = "Error: $($_.Exception.Message)"
            $results += $result
            continue
        }

        # --- Autopilot ---
        if (-not $matchedDevice.SerialNumber) {
            Write-Host "[$counter] No serial number found for device in Intune." -ForegroundColor Yellow
            $result.AutopilotStatus = "No Serial Number"
            $results += $result
            continue
        }

        Write-Host "[$counter] Checking Autopilot for serial number $($matchedDevice.SerialNumber)..." -ForegroundColor Yellow
        try {
            $autopilotDevice = Get-MgBetaDeviceManagementWindowsAutopilotDeviceIdentity -ErrorAction SilentlyContinue |
                Where-Object { $_.SerialNumber -eq $matchedDevice.SerialNumber }
        } catch {
            $autopilotDevice = $null
        }

        if (-not $autopilotDevice) {
            Write-Host "[$counter] No Autopilot record found for serial $($matchedDevice.SerialNumber)" -ForegroundColor Red
            $result.AutopilotStatus = "Not Found"
            $results += $result
            continue
        }

        try {
            Remove-MgBetaDeviceManagementWindowsAutopilotDeviceIdentity -WindowsAutopilotDeviceIdentityId $autopilotDevice.Id -ErrorAction SilentlyContinue
            Write-Host "[$counter] Autopilot record for $($matchedDevice.SerialNumber) deleted." -ForegroundColor Green
            $result.AutopilotStatus = "Deleted"
        } catch {
            Write-Host "[$counter] Failed to delete from Autopilot: $($_.Exception.Message)" -ForegroundColor Red
            $result.AutopilotStatus = "Error: $($_.Exception.Message)"
        }

        $results += $result
    }

    # --- Export Results to CSV ---
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
    $exportPath = Join-Path $env:USERPROFILE "Downloads\BulkDeletionResults_$timestamp.csv"
    $results | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8
    Write-Host "Results exported to: $exportPath" -ForegroundColor Cyan

    Stop-Transcript
}

# ------------------------------ Main Execution ------------------------------

# Step 1: Initialize modules first
Initialize-Modules