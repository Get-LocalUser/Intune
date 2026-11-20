<#
.SYNOPSIS
    Looks up and removes device records across Active Directory, Intune, Entra, Autopilot.

.DESCRIPTION
    Device365 is a tool for finding and deleting device records
    in one pass. It works for a single device or in bulk from a CSV.

    Search functions (read-only):
      - Look up a single device by name.
      - Look up multiple devices from a CSV and export the results.

    Delete functions (permanent):
      - Delete a single device from all four platforms.
      - Bulk delete from all platforms using a CSV.
      - Bulk delete from only one platform: Autopilot, Intune, Entra, or Active Directory.

    How lookups work:
      1. Active Directory is searched by computer name.
      2. Intune is searched by device name. The serial number and AzureADDeviceId are taken from this record.
      3. Entra is searched using the AzureADDeviceId from Intune. If there is no matching
         Intune record, no Entra object is returned. This prevents deleting the wrong object
         when device names are duplicated.
      4. Autopilot is searched by serial number that's taken from Intune first and from the CSV
         "Serial" column as a fallback.

    Safety features:
      - Read-only Graph scopes are requested for searches. Read/write scopes are requested only for deletions.
      - Every delete shows the search results first, then requires typing DELETE (case-sensitive).
      - Bulk deletes ask for one confirmation covering the whole batch.
      - Duplicate Intune or Autopilot matches are flagged so they can be verified.
      - Supports -WhatIf on the delete functions as a dry run.
      - A transcript of every deletion session is saved, and results are exported to CSV.

    On first run, the script checks for the ActiveDirectory module (RSAT) and installs
    Microsoft.Graph.Beta for the current user if it is missing.

.PARAMETER CsvPath
    Applies to the bulk functions (Search-MultipleComputers, Remove-MultipleComputers,
    Remove-AutopilotEntries, Remove-IntuneEntries, Remove-EntraEntries, Remove-ADEntries).
    Path to the input CSV. If omitted, a file picker dialog opens.

.PARAMETER Computer
    Applies to Search-SingleComputer and Remove-SingleComputer. The device name.
    If omitted, you are prompted for it.

.EXAMPLE
    .\Device365.ps1

    Launches the interactive menu. Choose an option [01]-[10].

.EXAMPLE
    Remove-SingleComputer -Computer "PC-12345" -WhatIf

    Shows what would be deleted for PC-12345 without removing anything.

.EXAMPLE
    Search-MultipleComputers -CsvPath "C:\Temp\devices.csv"

    Looks up every device in the CSV and exports a results file to Downloads.

.INPUTS
    CSV file (bulk operations) with these column headers:
      Asset Tag  - the device name (used for AD, Intune, and Entra lookups)
      Serial     - the serial number (used for the Autopilot lookup when Intune has no record)

.OUTPUTS
    Console output plus files in the user's Downloads folder:
      - MM-dd-yyyy_Device_365_Removal_Log.txt          (transcript for delete sessions)
      - Device365_Results.csv                          (search results)
      - Device365_SingleComputerRemoval_Results.csv
      - Device365_MultipleComputersRemoval_Results.csv
      - Device365_AutopilotRemoval_Results.csv
      - Device365_IntuneEntriesRemoval_Results.csv
      - Device365_EntraEntriesRemoval_Results.csv
      - Device365_ADEntriesRemoval_Results.csv
#>



function Initialize-Modules {
    if ($Global:DeviceScriptInitialized) {
        Write-Host "Modules already initialized. Skipping module checks." -ForegroundColor DarkGray
        Write-Host ""
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

    # Mark as initialized for the session
    $Global:DeviceScriptInitialized = $true
    Write-Host "Modules initialized." -ForegroundColor Yellow
}


function Start-SignIn {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Search')]
        [switch]$Search,

        [Parameter(Mandatory, ParameterSetName = 'Delete')]
        [switch]$Delete
    )

    $SearchScopes = @(
        "Device.Read.All"
        "DeviceManagementManagedDevices.Read.All"
        "DeviceManagementServiceConfig.Read.All"
    )

    $DeleteScopes = @(
        "Device.ReadWrite.All"
        "DeviceManagementManagedDevices.ReadWrite.All"
        "DeviceManagementServiceConfig.ReadWrite.All"
    )

    $RequiredScopes = if ($Delete) {
        $DeleteScopes
    }
    else {
        $SearchScopes
    }

    $context = Get-MgContext

    $missingScopes = @(
        $requiredScopes | Where-Object { $_ -notin $context.Scopes }
    )

    if ($null -eq $context -or $missingScopes.Count -gt 0) {

        Connect-MgGraph -Scopes $requiredScopes -NoWelcome
        Write-Host "Connected to Graph" -ForegroundColor Green
        Write-Host ""

    }
    else {
        Write-Host "Already connected with required scopes`n" -ForegroundColor Green
    }
}


function Start-Log {
    Write-Host ""
    Write-Host "Starting transcript. Device removals will be recorded and placed in your Downloads folder" -ForegroundColor Yellow

    $date = (Get-Date -Format "MM-dd-yyyy") + "_Device_365_Removal_Log"
    $downloadPath = "$env:USERPROFILE\Downloads"
    $filePath = Join-Path $downloadPath "$date.txt"

    $counter = 1

    while (Test-Path $filePath) {
        $filePath = Join-Path $downloadPath "$($date)_$counter.txt"
        $counter++
    }

    Write-Host "Transcript filename: $(Split-Path $filePath -Leaf)" -ForegroundColor Yellow

    Start-Transcript -Path $filePath -NoClobber | Out-Null
    Write-Host ""
}


function Stop-Log {
    Stop-Transcript | Out-Null
    Write-Host "`nTranscript stopped." -ForegroundColor Yellow
}


function Show-Table {
    param(
        $DeviceResult, 
        [string]$Computer
    )

    $checks = [ordered]@{
        "Active Directory" = $DeviceResult.AD_ComputerFound
        "Intune"           = $DeviceResult.Intune_ComputerFound
        "Entra ID"         = $DeviceResult.EntraID_ComputerFound
        "Autopilot"        = $DeviceResult.Autopilot_ComputerFound
    }

    Write-Host ""
    Write-Host "  Results for: $Computer" -ForegroundColor Cyan
    Write-Host "  ------------------------------" -ForegroundColor DarkGray

    foreach ($item in $checks.GetEnumerator()) {
        Write-Host ("  {0,-18}" -f $item.Key) -NoNewline

        if ($item.Value) {
            Write-Host "✓ Found" -ForegroundColor Green
        }
        else {
            Write-Host "X Not found" -ForegroundColor Red
        }
    }

    Write-Host ""
}


# ======================================================================
#                           SEARCH FUNCTIONS                           #
# ======================================================================


function Get-DeviceResult {
    param(
        [string]$Computer,
        [string]$SerialNumber
    )

    # Enter computer name
    if (-not $Computer) {
        $Computer = Read-Host "Enter the name of the device you want to search for"
    }

    $deviceresult = [PSCustomObject]@{
        InputName = $Computer

        # Active Directory
        AD_ComputerFound        = $false
        AD_ComputerName         = $null
        AD_DistinguishedName    = $null

        # Entra ID
        EntraID_ComputerFound   = $false
        EntraID_ComputerName    = $null
        EntraID_ObjectId        = $null

        # Intune
        Intune_ComputerFound    = $false
        Intune_Multiple         = $false
        Intune_ComputerName     = $null
        Intune_SerialNumber     = $null
        Intune_AzureADDeviceId  = $null
        Intune_Id               = $null

        # Autopilot
        Autopilot_ComputerFound = $false
        Autopilot_Multiple      = $false
        Autopilot_SerialNumber  = $null
        Autopilot_Id            = $null
    }

    Write-Host "Searching for computer: $Computer..." -ForegroundColor Yellow

    # ======================================================================
    #                          START AD COMPUTER                           #
    # ======================================================================

    try {
        $Compresults = Get-ADComputer -Filter "Name -eq '$Computer'" -ErrorAction Stop

        if ($Compresults) {
            $deviceresult.AD_ComputerFound     = $true
            $deviceresult.AD_ComputerName      = $Compresults.Name
            $deviceresult.AD_DistinguishedName = $Compresults.DistinguishedName
        }
        else {
            $deviceresult.AD_ComputerFound = $false
            $Compresults = $null
        }
    }
    catch {
        Write-Host "AD lookup failed: $($_.Exception.Message)" -ForegroundColor Red
    }

    # ======================================================================
    #                          END AD COMPUTER                             #
    # ======================================================================


    # ======================================================================
    #                       START INTUNE COMPUTER                          #
    # ======================================================================

    $Compresults = @(Get-MgBetaDeviceManagementManagedDevice -Filter "deviceName eq '$Computer'")
    if ($Compresults.Count -gt 1) {
        Write-Host "`nMultiple Intune computers found. Verify entries before deleting`n" -ForegroundColor Yellow
        $Compresults | ForEach-Object { Write-Host "Intune: $($_.DeviceName)" }
        $deviceresult.Intune_Multiple = $true
    } elseif ($Compresults.Count -eq 1) {
        $deviceresult.Intune_ComputerFound   = $true
        $deviceresult.Intune_ComputerName    = $Compresults[0].DeviceName
        $deviceresult.Intune_SerialNumber    = $Compresults[0].SerialNumber
        $deviceresult.Intune_AzureADDeviceId = $Compresults[0].AzureADDeviceId
        $deviceresult.Intune_Id              = $Compresults[0].Id
    }

    # ======================================================================
    #                        END INTUNE COMPUTER                          #
    # ======================================================================


    # ======================================================================
    #                        START ENTRA COMPUTER                          #
    # ======================================================================

    if ($deviceresult.Intune_AzureADDeviceId) {
        try {
            $EntraResults = Get-MgBetaDevice -Filter "deviceId eq '$($deviceresult.Intune_AzureADDeviceId)'" -ErrorAction Stop
        }
        catch {
            $EntraResults = $null
        }

        if ($EntraResults) {
            $deviceresult.EntraID_ComputerFound = $true
            $deviceresult.EntraID_ComputerName  = $EntraResults.DisplayName
            $deviceresult.EntraID_ObjectId      = $EntraResults.Id   # object ID, required for deletion
        }
    }

    # ======================================================================
    #                         END ENTRA COMPUTER                           #
    # ======================================================================


    # ======================================================================
    #                       START AUTOPLOT COMPUTER                        #
    # ======================================================================

    # Prefer serial number retrieved from Intune.
    # If unavailable, use serial number supplied directly (e.g. from CSV).

    $AutopilotSerial = $deviceresult.Intune_SerialNumber

    if (-not $AutopilotSerial -and $SerialNumber) {
        $AutopilotSerial = $SerialNumber.Trim()
    }

    if ($AutopilotSerial) {

        #Write-Host "Searching Autopilot using serial: $AutopilotSerial..." -ForegroundColor Yellow

        $Compresults = @(
            Get-MgBetaDeviceManagementWindowsAutopilotDeviceIdentity `
                -Filter "contains(serialNumber,'$AutopilotSerial')" `
                -ErrorAction Stop
        )

        if ($Compresults.Count -gt 1) {
            Write-Host "`nMultiple Autopilot devices found. Verify entries before deleting`n" -ForegroundColor Red

            $Compresults | ForEach-Object {
                Write-Host "Autopilot: $($_.DisplayName) | Serial: $($_.SerialNumber)"
            }

            $deviceresult.Autopilot_Multiple = $true
        }
        elseif ($Compresults.Count -eq 1) {
            $deviceresult.Autopilot_ComputerFound = $true
            $deviceresult.Autopilot_SerialNumber  = $Compresults[0].SerialNumber
            $deviceresult.Autopilot_Id            = $Compresults[0].Id
        }
    } else {
        Write-Host "No serial number available. Skipping Autopilot lookup." -ForegroundColor Yellow
    }

    # ======================================================================
    #                        END AUTOPLOT COMPUTER                         #
    # ======================================================================

    return $deviceresult
}


function Search-SingleComputer {
    param(
        [string]$Computer,
        [string]$SerialNumber,
        [switch]$Quiet
    )
 
    $deviceresult = Get-DeviceResult -Computer $Computer -SerialNumber $SerialNumber
 
    if (-not $Quiet) {
        Show-Table -DeviceResult $deviceresult -Computer $deviceresult.InputName
    } else {
        return $deviceresult
    }
}


function Select-CsvFile {
    Add-Type -AssemblyName System.Windows.Forms

    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title            = "Select a CSV file"
    $dialog.Filter           = "CSV files (*.csv)|*.csv|All files (*.*)|*.*"
    $dialog.InitialDirectory = Join-Path $env:USERPROFILE "Downloads"
    $dialog.Multiselect      = $false

    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.FileName
    }
    return $null
}


function Search-MultipleComputers {
    param([string]$CsvPath)

    if (-not $CsvPath) {
        Write-Host "Select your CSV file..." -ForegroundColor Yellow
        $CsvPath = Select-CsvFile
    }

    try {
        $computers = Import-Csv $CsvPath
        Write-Host "`nProcessing $($computers.Count) computers from CSV..." -ForegroundColor Yellow

        $results = @()
        $counter = 0

        foreach ($row in $computers) {
            $counter++
            $ComputerName = $row.'Asset Tag'
            $SerialNumber = $row.'Serial'

            if ([string]::IsNullOrWhiteSpace($computerName)) {
                Write-Host "[$counter/$($computers.Count)] Skipping empty computer name" -ForegroundColor Yellow
                continue
        }

        # Show progress
        Write-Host "[$counter/$($computers.Count)] $computerName" -ForegroundColor Cyan
        Write-Host "CSV Serial: [$SerialNumber]" -ForegroundColor Magenta

        #$deviceInfo = Search-SingleComputer -Computer $ComputerName -Quiet
        $deviceInfo = Get-DeviceResult -Computer $ComputerName -SerialNumber $SerialNumber -Quiet

            $result = [PSCustomObject]@{
                ComputerName     = $computerName
                Serial           = $SerialNumber
                ActiveDirectory  = if ($deviceInfo.AD_ComputerFound)       { "✓" } else { "X" }
                Intune           = if ($deviceInfo.Intune_ComputerFound)   { "✓" } else { "X" }
                EntraID          = if ($deviceInfo.EntraID_ComputerFound)  { "✓" } else { "X" }
                Autopilot        = if ($deviceInfo.Autopilot_ComputerFound){ "✓" } else { "X" }
                IntuneObjectID   = $deviceInfo.Intune_Id
                EntraObjectID    = $deviceInfo.EntraID_ObjectId
                AutopilotID      = $deviceInfo.Autopilot_Id
            }

            $results += $result
        }

    }
    catch {
        Write-Host "Error processing CSV: $($_.Exception.Message)" -ForegroundColor Red
    }

    Export-Results -Results $results
}


# ======================================================================
#                            DELETE FUNCTIONS                          #
# ======================================================================


function Remove-DeviceFromPortals {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]$DeviceResult,
        [switch]$Autopilot,
        [switch]$Intune,
        [switch]$EntraID,
        [switch]$AD,
        [switch]$SkipAutopilot
    )

    # If no switches were passed, default to everything
    if (-not ($Autopilot -or $Intune -or $EntraID -or $AD)) {
        $Autopilot = $Intune = $EntraID = $AD = $true
    }

    Write-Host "`nDeleting: $($DeviceResult.InputName)" -ForegroundColor Cyan


    # Autopilot
    if (-not $SkipAutopilot -and $Autopilot -and $DeviceResult.Autopilot_ComputerFound) {
        if ($PSCmdlet.ShouldProcess("$($DeviceResult.InputName) (Autopilot)", "Delete")) {
            try {
                Remove-MgBetaDeviceManagementWindowsAutopilotDeviceIdentity -WindowsAutopilotDeviceIdentityId $DeviceResult.Autopilot_Id -ErrorAction Stop
                Write-Host "  Autopilot : deleted" -ForegroundColor Green
            }
            catch { Write-Host "  Autopilot : FAILED - $($_.Exception.Message)" -ForegroundColor Red }
        }
    }

    # Intune
    if ($Intune -and $DeviceResult.Intune_ComputerFound) {
        if ($PSCmdlet.ShouldProcess("$($DeviceResult.InputName) (Intune)", "Delete")) {
            try {
                Remove-MgBetaDeviceManagementManagedDevice -ManagedDeviceId $DeviceResult.Intune_Id -ErrorAction Stop
                Write-Host "  Intune    : deleted" -ForegroundColor Green
            }
            catch { Write-Host "  Intune    : FAILED - $($_.Exception.Message)" -ForegroundColor Red }
        }
    }

    # Entra ID
    if ($EntraID -and $DeviceResult.EntraID_ComputerFound) {
        if ($PSCmdlet.ShouldProcess("$($DeviceResult.InputName) (Entra ID)", "Delete")) {
            try {
                Remove-MgBetaDevice -DeviceId $DeviceResult.EntraID_ObjectId -ErrorAction Stop
                Write-Host "  Entra ID  : deleted" -ForegroundColor Green
            }
            catch { Write-Host "  Entra ID  : FAILED - $($_.Exception.Message)" -ForegroundColor Red }
        }
    }

    # Active Directory
    if ($AD -and $DeviceResult.AD_ComputerFound) {
        if ($PSCmdlet.ShouldProcess("$($DeviceResult.InputName) (AD)", "Delete")) {
            try {
                Remove-ADObject -Identity $DeviceResult.AD_DistinguishedName -Recursive -Confirm:$false -ErrorAction Stop
                Write-Host "  AD        : deleted" -ForegroundColor Green
            }
            catch { Write-Host "  AD        : FAILED - $($_.Exception.Message)" -ForegroundColor Red }
        }
    }
}


function Remove-SingleComputer {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [string]$Computer
    )

    $deviceresult = Get-DeviceResult -Computer $Computer
    Show-Table -DeviceResult $deviceresult -Computer $deviceresult.InputName

    $deletable = $deviceresult.AD_ComputerFound -or
                 $deviceresult.Intune_ComputerFound -or
                 $deviceresult.EntraID_ComputerFound -or
                 $deviceresult.Autopilot_ComputerFound

    if (-not $deletable) {
        Write-Host "Nothing to delete for '$($deviceresult.InputName)'." -ForegroundColor Yellow
        return
    }

    $Question = Read-Host "Is this device being surplused? [Y/N]"

    $SkipAutopilot = $Question -match '^n(o)?$'

    # Confirmation (skipped for -WhatIf dry runs)
    if (-not $WhatIfPreference) {
        $message = if ($SkipAutopilot) {
            "This will permanently delete all entries marked 'Found' above, excluding Autopilot."
        }
        else {
            "This will permanently delete the entries marked 'Found' above."
        }

        Write-Host $message -ForegroundColor Red

        $confirm = Read-Host "Type 'DELETE' to confirm (anything else cancels)"
        if ($confirm -cne "DELETE") {
            Write-Host "Cancelled. Nothing was deleted." -ForegroundColor Yellow
            return
        }
    }

    # Delete
    if ($SkipAutopilot) {
        Remove-DeviceFromPortals -DeviceResult $deviceresult -SkipAutopilot -Confirm:$false
    }
    else {
        Remove-DeviceFromPortals -DeviceResult $deviceresult -Confirm:$false
    }

    # Export
    Export-Results -Results (ConvertTo-ExportRow $deviceresult) -FileName "Device365_SingleComputerRemoval_Results.csv"
}


function Remove-MultipleComputers {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [string]$CsvPath
    )

    if (-not $CsvPath) {
        Write-Host "Select your CSV file..." -ForegroundColor Yellow
        $CsvPath = Select-CsvFile
    }
    if (-not $CsvPath) { return }

    # Search everything first
    $found = @()
    foreach ($row in (Import-Csv $CsvPath)) {
        $name = $row.'Asset Tag'
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $r = Get-DeviceResult -Computer $name
        Show-Table -DeviceResult $r -Computer $r.InputName

        if ($r.AD_ComputerFound -or $r.Intune_ComputerFound -or $r.EntraID_ComputerFound -or $r.Autopilot_ComputerFound) {
            $found += $r
        }
    }

    if ($found.Count -eq 0) {
        Write-Host "Nothing to delete." -ForegroundColor Yellow
        return
    }

    # One confirmation for the whole batch (skipped for -WhatIf dry runs)
    if (-not $WhatIfPreference) {
        Write-Host "`nThis will permanently delete entries for $($found.Count) computer(s):" -ForegroundColor Red
        $found | ForEach-Object { Write-Host "  - $($_.InputName)" }

        $confirm = Read-Host "`nType 'DELETE' to confirm (anything else cancels)"
        if ($confirm -cne "DELETE") {
            Write-Host "Cancelled. Nothing was deleted." -ForegroundColor Yellow
            return
        }
    }

    foreach ($r in $found) {
        Remove-DeviceFromPortals -DeviceResult $r -Confirm:$false
    }

    Export-Results -Results ($found | ForEach-Object { ConvertTo-ExportRow $_ }) -FileName "Device365_MultipleComputersRemoval_Results.csv"
}


function Remove-AutopilotEntries {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [string]$CsvPath
    )

    if (-not $CsvPath) {
        Write-Host "Select your CSV file..." -ForegroundColor Yellow
        $CsvPath = Select-CsvFile
    }
    if (-not $CsvPath) { return }

    # Search everything first
    $found = @()
    foreach ($row in (Import-Csv $CsvPath)) {
        $name = $row.'Asset Tag'
        $serial = $row.'Serial'
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $r = Get-DeviceResult -Computer $name -SerialNumber $serial
        #Show-Table -DeviceResult $r. -Computer $r.InputName

        if ($r.Autopilot_ComputerFound) {
            Write-Host "Autopilot Device ($($row.Serial)): ✓ FOUND`n" -ForegroundColor Green
            $found += $r
        }
    }

    if ($found.Count -eq 0) {
        Write-Host "Nothing to delete." -ForegroundColor Yellow
        return
    }

    # One confirmation for the whole batch (skipped for -WhatIf dry runs)
    if (-not $WhatIfPreference) {
        Write-Host "`nThis will permanently delete Autopilot entrie(s) for $($found.Count) computer(s):" -ForegroundColor Red
        $found | ForEach-Object { Write-Host "  - $($_.Autopilot_SerialNumber)" }

        $confirm = Read-Host "`nType 'DELETE' to confirm (anything else cancels)"
        if ($confirm -cne "DELETE") {
            Write-Host "Cancelled. Nothing was deleted." -ForegroundColor Yellow
            return
        }
    }

    foreach ($r in $found) {
        Remove-DeviceFromPortals -DeviceResult $r -Autopilot -Confirm:$false
    }

    Export-Results -Results ($found | ForEach-Object { ConvertTo-ExportRow $_ }) -FileName "Device365_AutopilotRemoval_Results.csv"
}


function Remove-IntuneEntries {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [string]$CsvPath
    )

    if (-not $CsvPath) {
        Write-Host "Select your CSV file..." -ForegroundColor Yellow
        $CsvPath = Select-CsvFile
    }
    if (-not $CsvPath) { return }

    # Search everything first
    $found = @()
    foreach ($row in (Import-Csv $CsvPath)) {
        $name = $row.'Asset Tag'
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $r = Get-DeviceResult -Computer $name
        #Show-Table -DeviceResult $r -Computer $r.InputName

        if ($r.Intune_ComputerFound) {
            Write-Host "Intune Device ($($r.InputName)): ✓ FOUND`n" -ForegroundColor Green
            $found += $r
        }
    }

    if ($found.Count -eq 0) {
        Write-Host "Nothing to delete." -ForegroundColor Yellow
        return
    }

    # One confirmation for the whole batch (skipped for -WhatIf dry runs)
    if (-not $WhatIfPreference) {
        Write-Host "`nThis will permanently delete Intune entrie(s) for $($found.Count) computer(s):" -ForegroundColor Red
        $found | ForEach-Object { Write-Host "  - $($_.InputName)" }

        $confirm = Read-Host "`nType 'DELETE' to confirm (anything else cancels)"
        if ($confirm -cne "DELETE") {
            Write-Host "Cancelled. Nothing was deleted." -ForegroundColor Yellow
            return
        }
    }

    foreach ($r in $found) {
        Remove-DeviceFromPortals -DeviceResult $r -Intune -Confirm:$false
    } 

    Export-Results -Results ($found | ForEach-Object { ConvertTo-ExportRow $_ }) -FileName "Device365_IntuneEntriesRemoval_Results.csv"    
}


function Remove-EntraEntries {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [string]$CsvPath
    )

    if (-not $CsvPath) {
        Write-Host "Select your CSV file..." -ForegroundColor Yellow
        $CsvPath = Select-CsvFile
    }
    if (-not $CsvPath) { return }

    # Search everything first
    $found = @()
    foreach ($row in (Import-Csv $CsvPath)) {
        $name = $row.'Asset Tag'
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $r = Get-DeviceResult -Computer $name
        #Show-Table -DeviceResult $r -Computer $r.InputName

        if ($r.EntraID_ComputerFound) {
            Write-Host "Entra Device ($($r.InputName)): ✓ FOUND`n" -ForegroundColor Green
            $found += $r
        }
    }

    if ($found.Count -eq 0) {
        Write-Host "Nothing to delete." -ForegroundColor Yellow
        return
    }

    # One confirmation for the whole batch (skipped for -WhatIf dry runs)
    if (-not $WhatIfPreference) {
        Write-Host "`nThis will permanently delete Entra entrie(s) for $($found.Count) computer(s):" -ForegroundColor Red
        $found | ForEach-Object { Write-Host "  - $($_.InputName)" }

        $confirm = Read-Host "`nType 'DELETE' to confirm (anything else cancels)"
        if ($confirm -cne "DELETE") {
            Write-Host "Cancelled. Nothing was deleted." -ForegroundColor Yellow
            return
        }
    }

    foreach ($r in $found) {
        Remove-DeviceFromPortals -DeviceResult $r -EntraID -Confirm:$false
    } 

    Export-Results -Results ($found | ForEach-Object { ConvertTo-ExportRow $_ }) -FileName "Device365_EntraEntriesRemoval_Results.csv"    
}


function Remove-ADEntries {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [string]$CsvPath
    )

    if (-not $CsvPath) {
        Write-Host "Select your CSV file..." -ForegroundColor Yellow
        $CsvPath = Select-CsvFile
    }
    if (-not $CsvPath) { return }

    # Search everything first
    $found = @()
    foreach ($row in (Import-Csv $CsvPath)) {
        $name = $row.'Asset Tag'
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $r = Get-DeviceResult -Computer $name
        #Show-Table -DeviceResult $r -Computer $r.InputName

        if ($r.AD_ComputerFound) {
            Write-Host "AD Device ($($r.InputName)): ✓ FOUND`n" -ForegroundColor Green
            $found += $r
        }
    }

    if ($found.Count -eq 0) {
        Write-Host "Nothing to delete." -ForegroundColor Yellow
        return
    }

    # One confirmation for the whole batch (skipped for -WhatIf dry runs)
    if (-not $WhatIfPreference) {
        Write-Host "`nThis will permanently delete AD entrie(s) for $($found.Count) computer(s):" -ForegroundColor Red
        $found | ForEach-Object { Write-Host "  - $($_.InputName)" }

        $confirm = Read-Host "`nType 'DELETE' to confirm (anything else cancels)"
        if ($confirm -cne "DELETE") {
            Write-Host "Cancelled. Nothing was deleted." -ForegroundColor Yellow
            return
        }
    }

    foreach ($r in $found) {
        Remove-DeviceFromPortals -DeviceResult $r -AD -Confirm:$false
    }   
    
    Export-Results -Results ($found | ForEach-Object { ConvertTo-ExportRow $_ }) -FileName "Device365_ADEntriesRemoval_Results.csv"    
}


function ConvertTo-ExportRow {
    param($DeviceResult)

    [PSCustomObject]@{
        ComputerName     = $DeviceResult.InputName
        Serial           = if ($DeviceResult.Intune_SerialNumber) { $DeviceResult.Intune_SerialNumber } else { $DeviceResult.Autopilot_SerialNumber }
        ActiveDirectory  = if ($DeviceResult.AD_ComputerFound)        { "✓" } else { "X" }
        Intune           = if ($DeviceResult.Intune_ComputerFound)    { "✓" } else { "X" }
        EntraID          = if ($DeviceResult.EntraID_ComputerFound)   { "✓" } else { "X" }
        Autopilot        = if ($DeviceResult.Autopilot_ComputerFound) { "✓" } else { "X" }
        IntuneObjectID   = $DeviceResult.Intune_Id
        EntraObjectID    = $DeviceResult.EntraID_ObjectId
        AutopilotID      = $DeviceResult.Autopilot_Id
    }
}


function Export-Results {
    param(
        $Results,
        [string]$FileName = "Device365_Results.csv"
    )

    # Print results and export to a CSV in the user's Downloads folder
    $Pathway = "C:\Users\$env:USERNAME\Downloads\"
    $ExportFile = Join-Path -Path $Pathway -ChildPath $FileName

    if ($Results) {
        $Utf8WithBom = New-Object System.Text.UTF8Encoding $true
        $csvContent = $Results | ConvertTo-Csv -NoTypeInformation | Out-String
        [System.IO.File]::WriteAllText($ExportFile, $csvContent, $Utf8WithBom)
        Write-Host "`nResults exported to: $ExportFile" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "`nNote: An Entra ID object is returned only when a matching Intune object with the same AzureADDeviceId attribute exists." -ForegroundColor Blue
        Write-Host "If no matching Intune object exists, the result is null. This avoids conflicts when names are duplicated." -ForegroundColor Blue
    }
    else {
        Write-Host "Not exported" -ForegroundColor Red
    }
}


function Device365 {

    Initialize-Modules

    do {

        # ─────────────────────────────────────────────────────
        # DEVICE LOOKUP
        # ─────────────────────────────────────────────────────

        Write-Host "  ┌─[ 01 ] DEVICE LOOKUP ────────────────────────────────┐" -ForegroundColor Green
        Write-Host "  │                                                      │" -ForegroundColor Green
        Write-Host "  │   [01]  Look up a single device                      │" -ForegroundColor Green
        Write-Host "  │   [02]  Import CSV & look up multiple devices        │" -ForegroundColor Green
        Write-Host "  │                                                      │" -ForegroundColor Green
        Write-Host "  └──────────────────────────────────────────────────────┘" -ForegroundColor Green
        Write-Host ""

        # ─────────────────────────────────────────────────────
        # DEVICE DELETION
        # ─────────────────────────────────────────────────────

        Write-Host "  ┌─[ 02 ] DEVICE DELETION ──────────────────────────────┐" -ForegroundColor Red
        Write-Host "  │                                                      │" -ForegroundColor Red
        Write-Host "  │   [ CAUTION ] Deletion is permanent!                 │" -ForegroundColor Red
        Write-Host "  │                                                      │" -ForegroundColor Red
        Write-Host "  │   [03]  Delete Single Device                         │" -ForegroundColor Red
        Write-Host "  │         AD  |  Intune  |  Entra  |  Autopilot        │" -ForegroundColor DarkGray
        Write-Host "  │                                                      │" -ForegroundColor Red
        Write-Host "  │   [04]  Bulk Delete All Platforms (CSV)              │" -ForegroundColor Red
        Write-Host "  │         AD  |  Intune  |  Entra  |  Autopilot        │" -ForegroundColor DarkGray
        Write-Host "  │                                                      │" -ForegroundColor Red
        Write-Host "  │   [05]  Bulk Delete Autopilot Devices (CSV)          │" -ForegroundColor Red
        Write-Host "  │   [06]  Bulk Delete Intune Devices (CSV)             │" -ForegroundColor Red
        Write-Host "  │   [07]  Bulk Delete Entra Devices (CSV)              │" -ForegroundColor Red
        Write-Host "  │   [08]  Bulk Delete AD Devices (CSV)                 │" -ForegroundColor Red
        Write-Host "  │                                                      │" -ForegroundColor Red
        Write-Host "  └──────────────────────────────────────────────────────┘" -ForegroundColor Red
        Write-Host ""

        # ─────────────────────────────────────────────────────
        # SESSION CONTROL
        # ─────────────────────────────────────────────────────

        Write-Host "  ┌─[ 03 ] SESSION CONTROL ──────────────────────────────┐" -ForegroundColor Yellow
        Write-Host "  │                                                      │" -ForegroundColor Yellow
        Write-Host "  │   [09]  Exit & Disconnect Microsoft Graph            │" -ForegroundColor Yellow
        Write-Host "  │   [10]  Exit                                         │" -ForegroundColor Yellow
        Write-Host "  │                                                      │" -ForegroundColor Yellow
        Write-Host "  └──────────────────────────────────────────────────────┘" -ForegroundColor Yellow
        Write-Host ""



        $choice = Read-Host "Select an option "

        switch ($choice) {
            "1" { 
                Start-SignIn -Search
                Search-SingleComputer
            }
            "2" { 
                Start-SignIn -Search
                Search-MultipleComputers
            }
            "3" { 
                Start-Log 
                Start-SignIn -Delete
                Remove-SingleComputer
                Stop-Log 
            }
            "4" { 
                Start-Log
                Start-SignIn -Delete
                Remove-MultipleComputers
                Stop-Log 
            }
            "5" {
                Start-Log
                Start-SignIn -Delete
                Remove-AutopilotEntries
                Stop-Log 
            }
            "6" {
                Start-Log
                Start-SignIn -Delete
                Remove-IntuneEntries
                Stop-Log
            }
            "7" {
                Start-Log
                Start-SignIn -Delete
                Remove-EntraEntries
                Stop-Log
            }
            "8" {
                Start-Log
                Remove-ADEntries
                Stop-Log
            }
            "9" { 
                Disconnect-MgGraph | Out-Null
                if ($null -eq (Get-MgContext).ContextScope) {
                    Write-Host "`nDisconected from Graph" -ForegroundColor Green
                }
                Exit
            }
            "10" {
                Exit
            }
            default {
                Write-Host "Invalid choice" -ForegroundColor Red
            }
        }

        if ($choice -ne "9") {
            Write-Host ""
            Read-Host "Press ENTER to return to the main menu"
        }

    } while ($choice -ne "9")
}


Device365