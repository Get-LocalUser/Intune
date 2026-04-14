<#
.NOTES
    - Requires RSAT: Active Directory tools installed.
    - CSV must contain a column named "Asset Tag".

    Author:       Get-LocalUser
    Last Updated: 04/14/2026

.SYNOPSIS
    Device Deletion Script - Searches for computer records in Active Directory and deletes them.

.DESCRIPTION
    This script allows administrators to search and delete one or more devices by name or asset tag
    from Active Directory.

    You can run the script interactively, pass a single computer name as a parameter, or provide
    a CSV file for bulk searching. Results will display in the console and optionally be exported
    to a CSV file in your Downloads folder.

.FUNCTIONALITY
    - Imports and verifies required modules (ActiveDirectory).
    - Searches for and deletes devices from AD.
    - Supports both interactive and automated use.
    - Outputs results with status markers.
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
            ComputerName = $ComputerName
            ADStatus     = "Not Attempted"
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