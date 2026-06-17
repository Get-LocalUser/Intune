$OutputPath = "C:\Reports\Mobile30DayCheckIn_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"

Connect-MgGraph -Scopes "DeviceManagementManagedDevices.Read.All" -NoWelcome

# Get managed devices
$allDevices = @()
$devices = Get-MgBetaDeviceManagementManagedDevice -Filter "operatingSystem eq 'iOS'"
$allDevices += $devices

while ($devices.NextLink) {
    $devices = Invoke-MgGraphRequest -Method GET -Uri $devices.NextLink
    $allDevices += $devices.value
}

# Determine cutoff
$cutoff = (Get-Date).AddDays(-20)

$staleDevices = $allDevices | Where-Object {
    $_.LastSyncDateTime -and $_.LastSyncDateTime -lt $cutoff
}

$report = foreach ($d in $staleDevices) {
    [PSCustomObject]@{
        DeviceName        = $d.DeviceName
        UserPrincipalName = $d.UserPrincipalName
        UserName          = $d.UserDisplayName
        ComplianceState   = $d.ComplianceState
        OperatingSystem   = $d.OperatingSystem
        OSVersion         = $d.OsVersion
        LastCheckIn       = $d.LastSyncDateTime
        DaysSinceCheckIn  = ((Get-Date) - $d.LastSyncDateTime).Days
        ManagedDeviceId   = $d.Id
    }
}

$folder = Split-Path $OutputPath -Parent
if (-not (Test-Path $folder)) {
    New-Item -Path $folder -ItemType Directory -Force | Out-Null
}

$report | Sort-Object DaysSinceCheckIn -Descending | Export-Csv -NoTypeInformation -Path $OutputPath -Encoding UTF8

Write-Host "Report generated :$Outputpath" -ForegroundColor Yellow