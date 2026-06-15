<#
.NOTES
    - Requires RSAT: Active Directory tools installed.
    - Requires Microsoft.Graph.Beta module installed (will auto-install if missing).
    - CSV must contain a column named "Asset Tag".

    Author:       Get-LocalUser
    Last Updated: 04/21/2026

.DESCRIPTION
    This script allows administrators to search and delete one or more devices by name or asset tag
    across three platforms:
        - Active Directory
        - Intune
        - Entra ID

.FUNCTIONALITY
    - Imports and verifies required modules (ActiveDirectory, Microsoft.Graph.Beta).
    - Connects to Microsoft Graph ("DeviceManagementServiceConfig.Read.All", "DeviceManagementServiceConfig.ReadWrite.All", "Device.Read.All", "Device.ReadWrite.All" scopes required).
    - Supports both interactive and automated use.
    - Outputs results with ✓ markers or 'False'.
    - Exports bulk results to CSV in the user's Downloads folder.
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

    Connect-MgGraph -Scopes "DeviceManagementServiceConfig.Read.All", "DeviceManagementServiceConfig.ReadWrite.All", "Device.Read.All", "Device.ReadWrite.All" -NoWelcome

    $Global:DeviceScriptInitialized = $true
    Write-Host "Modules initialized." -ForegroundColor Yellow
}

# ------------------------------ End of Modules ------------------------------



function Delete-SingleComputer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
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

    # --- Entra ID ---
    Write-Host "Checking Entra ID for $assetTag..." -ForegroundColor Yellow
    if ($matchedDevice.AzureADDeviceId) {
        try {
            $EntraIDDevice = Get-MgBetaDevice -Filter "deviceId eq '$($matchedDevice.AzureADDeviceId)'" -ErrorAction Stop
        } catch {
            $EntraIDDevice = $null
        }

        if ($EntraIDDevice) {
            Write-Host "$assetTag found in Entra ID" -ForegroundColor Yellow
            try {
                Remove-MgBetaDevice -DeviceId $EntraIDDevice.Id -ErrorAction Stop
                Write-Host "$assetTag removed from Entra ID." -ForegroundColor Green
            } catch {
                Write-Host "Failed to remove $assetTag from Entra ID: $($_.Exception.Message)" -ForegroundColor Red
            }
        } else {
            Write-Host "$assetTag NOT found in Entra ID" -ForegroundColor Red
        }
    } else {
        Write-Host "No AzureADDeviceId found for $assetTag in Intune. Cannot search Entra ID." -ForegroundColor Yellow
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

        # Create hidden topmost form so dialog appears in foreground
        $form = New-Object System.Windows.Forms.Form
        $form.TopMost = $true
        $form.WindowState = 'Minimized'
        $form.ShowInTaskbar = $false

        $fileDialog = New-Object System.Windows.Forms.OpenFileDialog
        $fileDialog.Filter = "CSV files (*.csv)|*.csv|All files (*.*)|*.*"
        $fileDialog.Title = "Select the CSV file with computers to delete"
        $fileDialog.InitialDirectory = [Environment]::GetFolderPath("Desktop")

        if ($fileDialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
            $CsvPath = $fileDialog.FileName
        } else {
            Write-Host "No file selected. Exiting bulk delete." -ForegroundColor Red
            $form.Dispose()
            return
        }

        $form.Dispose()
    }

    # --- Import CSV and initialize ---
    $ImportedCSV = Import-Csv $CsvPath
    $counter = 0
    $results = @()

    foreach ($row in $ImportedCSV) {
        $counter++
        $ComputerName = $row.'Asset Tag'
        $result = [PSCustomObject]@{
            ComputerName  = $ComputerName
            ADStatus      = "Not Attempted"
            IntuneStatus  = "Not Attempted"
            EntraIDStatus = "Not Attempted"
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

        # --- Entra ID ---
        Write-Host "[$counter] Checking Entra ID for $ComputerName..." -ForegroundColor Yellow
        if ($matchedDevice.AzureADDeviceId) {
            try {
                $EntraIDDevice = Get-MgBetaDevice -Filter "deviceId eq '$($matchedDevice.AzureADDeviceId)'" -ErrorAction SilentlyContinue
            } catch {
                $EntraIDDevice = $null
            }

            if ($EntraIDDevice) {
                Write-Host "[$counter] $ComputerName found in Entra ID" -ForegroundColor Yellow
                try {
                    Remove-MgBetaDevice -DeviceId $EntraIDDevice.Id -ErrorAction SilentlyContinue
                    Write-Host "[$counter] $ComputerName removed from Entra ID." -ForegroundColor Green
                    $result.EntraIDStatus = "Deleted"
                } catch {
                    Write-Host "[$counter] Failed to remove $ComputerName from Entra ID: $($_.Exception.Message)" -ForegroundColor Red
                    $result.EntraIDStatus = "Error: $($_.Exception.Message)"
                }
            } else {
                Write-Host "[$counter] $ComputerName NOT found in Entra ID" -ForegroundColor Red
                $result.EntraIDStatus = "Not Found"
            }
        } else {
            Write-Host "[$counter] No AzureADDeviceId found for $ComputerName in Intune. Cannot search Entra ID." -ForegroundColor Yellow
            $result.EntraIDStatus = "No AzureADDeviceId"
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


function Delete-Computer {
    Write-Host "`nSelect Delete Mode:" -ForegroundColor Cyan
    Write-Host "1. Delete Single Computer"
    Write-Host "2. Delete Bulk from CSV"
    $choice = Read-Host "Enter your choice (1 or 2)"

    switch ($choice) {
        "1" {
            $computer = Read-Host "Enter the name of the device you want to delete"
            if ([string]::IsNullOrWhiteSpace($computer)) {
                Write-Host "No computer name provided. Exiting." -ForegroundColor Red
                return
            }
            Delete-SingleComputer -assetTag $computer
        }
        "2" {
            Delete-ComputerBulk
        }
        default {
            Write-Host "Invalid choice. Please run Delete-Computer again and enter 1 or 2." -ForegroundColor Red
        }
    }
}


# ------------------------------ Main Execution ------------------------------

# Step 1: Initialize modules first
Initialize-Modules

Delete-Computer

Stop-Transcript