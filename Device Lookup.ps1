<#
.NOTES
    - Requires RSAT: Active Directory tools installed.
    - Requires Microsoft.Graph.Beta module installed (will auto-install if missing).
    - CSV must contain a column named "Asset Tag".

    Author:       Get-LocalUser
    Last Updated: 08/01/2025

.SYNOPSIS
    Device Lookup Script - Searches for computer records across Active Directory, Intune, & Autopilot.

.DESCRIPTION
    This script allows administrators to search for one or more devices by name or asset tag
    across three platforms:
        - Active Directory AD
        - Microsoft Intune via Microsoft Graph Beta API
        - Windows Autopilot via Microsoft Graph Beta API

    You can run the script interactively, pass a single computer name as a parameter, or provide
    a CSV file for bulk searching. Results will display in the console and optionally be exported
    to a CSV file in your Downloads folder.

.FUNCTIONALITY
    - Imports and verifies required modules (ActiveDirectory, Microsoft.Graph.Beta).
    - Connects to Microsoft Graph ('Device.Read.All' scope required).
    - Searches for devices across AD, Intune, & Autopilot.
    - Supports both interactive and automated use.
    - Outputs results with ✓ markers or 'False'.
    - Exports bulk results to CSV in the user's Downloads folder.
    - Asks whether to disconnect from Microsoft Graph after completion.
#>

# ------------------------ Module Initialization ------------------------
function Initialize-Modules {
    if ($Global:DeviceScriptInitialized) {
        Write-Host "Modules already initialized. Skipping module checks." -ForegroundColor Green
        return
    }

    # -------------------- Install & Import Modules ---------------------

    # Active Directory
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        Write-Host "ActiveDirectory module not found. Please install RSAT: Active Directory." -ForegroundColor Red
        return
    }
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Host "ActiveDirectory module imported successfully." -ForegroundColor Yellow

    # Microsoft Graph Beta
    if (-not (Get-InstalledModule -Name Microsoft.Graph.Beta -ErrorAction SilentlyContinue)) {
        Write-Host "Installing Graph module. This will take a few minutes..." -ForegroundColor Yellow
        Install-Module -Name Microsoft.Graph.Beta -Scope CurrentUser -Force -Verbose
    }
    Import-Module Microsoft.Graph.Beta -ErrorAction Ignore
    Write-Host "Graph module imported successfully." -ForegroundColor Yellow

    Connect-MgGraph -Scopes "Device.Read.All" -NoWelcome

    # Mark as initialized for the session
    $Global:DeviceScriptInitialized = $true
    Write-Host "Modules initialized." -ForegroundColor Yellow
}

# ------------------------------ End of Modules ------------------------------

function Search-SingleComputer {
    param([string]$Computer)

    # Define the PSCustomObject for output
    $deviceresult = [PSCustomObject]@{
        InputName = $Computer

        # Active Directory
        AD_ComputerFound        = $false
        AD_ComputerName         = $null

        # Intune
        Intune_ComputerFound    = $false
        Intune_ComputerName     = $null
        Intune_SerialNumber     = $null

        # Autopilot
        Autopilot_ComputerFound = $false
        Autopilot_SerialNumber  = $null
    }
    

    # Enter computer name
    if (-not $Computer) {
        $Computer = Read-Host "Enter the name of the device you want to search for"
    }

    Write-Host "Searching for computer.." -ForegroundColor Yellow

    # Get AD Computer
    $Compresults = Get-ADComputer -Filter "Name -like '*$Computer*'" -ErrorAction SilentlyContinue
    if ($Compresults.Count -gt 1) {
        Write-Host "Multiple computers found in AD. Verify entries before deleting" -ForegroundColor Red
        $compresults | ForEach-Object {"Write-Host Active Directory:$($_.Name)"} 
    } elseif ($Compresults) {
        $deviceresult.AD_ComputerFound       = $true
        $deviceresult.AD_ComputerName        = $Compresults.Name
    }

    # Get Intune computer
    $Compresults = Get-MgBetaDeviceManagementManagedDevice -Filter "deviceName eq '$Computer'"
    if ($Compresults.Count -gt 1) {
        Write-Host "Multiple Intune computers found. Verify entries before deleting" -ForegroundColor Red
        $compresults | ForEach-Object {Write-Host "Intune: $($_.DeviceName)"} 
    } elseif ($Compresults) {
        $deviceresult.Intune_ComputerFound   = $true
        $deviceresult.Intune_ComputerName    = $Compresults.DeviceName
        $deviceresult.Intune_SerialNumber    = $Compresults.SerialNumber
    }

    # Get Autopilot enrollment
    if ($deviceresult.Intune_SerialNumber) {
        $Compresults = Get-MgBetaDeviceManagementWindowsAutopilotDeviceIdentity -ErrorAction SilentlyContinue | Where-Object { $_.SerialNumber -eq $deviceresult.Intune_SerialNumber }
    }
    
    if ($Compresults.Count -gt 1) {
        Write-Host "Multiple Autopilot devices found. Verify entries before deleting" -ForegroundColor Red
        $compresults | ForEach-Object {Write-Host "Autopilot: $($_.DisplayName)"} 
    } elseif ($Compresults) {
        $deviceresult.Autopilot_ComputerFound = $true
        $deviceresult.Autopilot_SerialNumber  = $Compresults.SerialNumber
    }


    # Display results of previous checks
    if ($deviceresult.AD_ComputerFound -or $deviceresult.Intune_ComputerFound -or $deviceresult.Autopilot_ComputerFound) {
        Write-Host "Device found in one or more systems." -ForegroundColor Yellow
    } else { 
        Write-Host "No devices found in any system." -ForegroundColor Red
    }

    $Check = "✓"
    $output = [PSCustomObject]@{
        ComputerName    = $deviceresult.InputName
        ActiveDirectory = if ($deviceresult.AD_ComputerFound)       { $Check } else { "False" }
        Intune          = if ($deviceresult.Intune_ComputerFound)   { $Check } else { "False" }
        Autopilot       = if ($deviceresult.Autopilot_ComputerFound){ $Check } else { "False" }
    }

    $output | Format-Table -AutoSize

    return $deviceresult
}


function Search-BulkComputers {
    param([string]$CsvPath)

    if (-not (Test-Path $CsvPath)) {
        Write-Host "CSV file not found: $CsvPath" -ForegroundColor Red
        return
    }

    try {
        $computers = Import-Csv $CsvPath
        Write-Host "`nProcessing $($computers.Count) computers from CSV..." -ForegroundColor Yellow

        $results = @()
        $counter = 0

        foreach ($row in $computers) {
            $counter++
            $ComputerName = $row.'Asset Tag'

            if ([string]::IsNullOrWhiteSpace($computerName)) {
                Write-Host "[$counter/$($computers.Count)] Skipping empty computer name" -ForegroundColor Yellow
                continue
        }

        # Show progress
        Write-Host "[$counter/$($computers.Count)] $computerName" -ForegroundColor Cyan

        $deviceInfo = Search-SingleComputer -Computer $computerName

        $Check = "✓"
        $result = [PSCustomObject]@{
            ComputerName     = $computerName
            ActiveDirectory  = if ($deviceInfo.AD_ComputerFound)       { $check } else { "False" }
            Intune           = if ($deviceInfo.Intune_ComputerFound)   { $check } else { "False" }
            Autopilot        = if ($deviceInfo.Autopilot_ComputerFound){ $check } else { "False" }
        }

            $results += $result
        }

    }
    catch {
        Write-Host "Error processing CSV: $($_.Exception.Message)" -ForegroundColor Red
    }

    # Print results and export to a CSV in the user's Downloads folder
    $Pathway = "C:\Users\$env:USERNAME\Downloads\"
    $ExportFile = Join-Path -Path $Pathway -ChildPath "Computersfound.csv"

    if ($results) { 
        $Utf8WithBom = New-Object System.Text.UTF8Encoding $true
        $csvContent = $results | ConvertTo-Csv -NoTypeInformation | Out-String
        [System.IO.File]::WriteAllText($ExportFile, $csvContent, $Utf8WithBom)
        Write-Host "`nResults exported to: $ExportFile" -ForegroundColor Yellow
        Write-Host "`nOpen in Excel for best visual." -ForegroundColor Magenta
    }
    else {
        Write-Host "Not exported" -ForegroundColor Yellow
    }

    return $results
    Write-Host "`nOpen in Excel for best visual." -ForegroundColor Magenta
}


function Find-Computer {
    Write-Host "`nSelect Search Mode:" -ForegroundColor Cyan
    Write-Host "1. Search Single Computer"
    Write-Host "2. Search Bulk from CSV"
    $choice = Read-Host "Enter your choice (1 or 2)"

    switch ($choice) {
        "1" {
            $computer = Read-Host "Enter the name of the device you want to search for"
            if ([string]::IsNullOrWhiteSpace($computer)) {
                Write-Host "No computer name provided. Exiting." -ForegroundColor Red
                exit
            }
            Search-SingleComputer -Computer $computer
        }
        "2" {
            Add-Type -AssemblyName System.Windows.Forms
            $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
            $openFileDialog.Filter = "CSV files (*.csv)|*.csv|All files (*.*)|*.*"
            $openFileDialog.Title = "Select the CSV file"
            $openFileDialog.InitialDirectory = [Environment]::GetFolderPath("Desktop")

            if ($openFileDialog.ShowDialog() -eq "OK") {
                $csvPath = $openFileDialog.FileName
                $allResults = Search-BulkComputers -CsvPath $csvPath
                $allResults | Format-Table -AutoSize
            } else {
                Write-Host "No file selected. Exiting." -ForegroundColor Red
                exit
            }
        }
        default {
            Write-Host "Invalid selection. Please enter 1 or 2." -ForegroundColor Red
        }
    }
}



# ------------------------------ Main Execution ------------------------------

# Step 1: Initialize modules first
Initialize-Modules

# Step 2: Run interactive mode selection
Find-Computer