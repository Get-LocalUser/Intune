function Delete-AutopilotRecords {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$CsvPath
    )

    # --- File Picker UI if path not provided ---
    if (-not $CsvPath) {
        Add-Type -AssemblyName System.Windows.Forms
        $form = New-Object System.Windows.Forms.Form
        $form.TopMost = $true
        $form.WindowState = 'Minimized'
        $form.ShowInTaskbar = $false
        $fileDialog = New-Object System.Windows.Forms.OpenFileDialog
        $fileDialog.Filter = "CSV files (*.csv)|*.csv|All files (*.*)|*.*"
        $fileDialog.Title = "Select the CSV file with Serial numbers to delete"
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

    # --- Connect once and fetch all Autopilot devices once ---
    Connect-MgGraph -Scopes "DeviceManagementServiceConfig.Read.All", "DeviceManagementServiceConfig.ReadWrite.All", "Device.Read.All", "Device.ReadWrite.All" -NoWelcome
    Write-Host "Fetching all Autopilot devices from Intune..." -ForegroundColor Cyan
    $AllAutopilotDevices = Get-MgBetaDeviceManagementWindowsAutopilotDeviceIdentity -All

    foreach ($row in $ImportedCSV) {
        $counter++
        $SerialNumber = $row.'Serial'.Trim()  # Fix: trim whitespace

        $result = [PSCustomObject]@{
            Serial          = $SerialNumber
            AutopilotStatus = "Not Attempted"
        }

        if ([string]::IsNullOrWhiteSpace($SerialNumber)) {
            Write-Host "[$counter/$($ImportedCSV.Count)] Skipping empty serial number" -ForegroundColor Yellow
            $results += $result
            continue
        }

        Write-Host "[$counter/$($ImportedCSV.Count)] Processing '$SerialNumber'" -ForegroundColor Cyan

        # Fix: filter from cached list, no repeated API calls
        $Autopilotdevice = $AllAutopilotDevices | Where-Object { $_.SerialNumber -eq $SerialNumber }

        if (-not $Autopilotdevice) {
            Write-Host "[$counter] No Autopilot record found for '$SerialNumber'" -ForegroundColor Yellow
            $result.AutopilotStatus = "Not Found"
            $results += $result
            continue
        }

        try {
            Remove-MgBetaDeviceManagementWindowsAutopilotDeviceIdentity -WindowsAutopilotDeviceIdentityId $Autopilotdevice.Id
            Write-Host "[$counter] Autopilot record for '$SerialNumber' deleted." -ForegroundColor Green
            $result.AutopilotStatus = "Deleted"
        }
        catch {
            Write-Host "[$counter] Failed to delete from Autopilot: $($_.Exception.Message)" -ForegroundColor Red
            $result.AutopilotStatus = "Error: $($_.Exception.Message)"
        }

        $results += $result
    }

    # --- Export Results to CSV ---
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
    $exportPath = Join-Path $env:USERPROFILE "Downloads\AutopilotDeletionResults_$timestamp.csv"
    $results | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8
    Write-Host "Results exported to: $exportPath" -ForegroundColor Cyan
}

Delete-AutopilotRecords