# Microsoft Graph Beta
if (-not (Get-InstalledModule -Name Microsoft.Graph.Beta)) {
    Write-Host "Installing Graph module. This will take a few minutes..." -ForegroundColor Yellow
    Install-Module -Name Microsoft.Graph.Beta -Scope CurrentUser -Force -Verbose
}
Import-Module Microsoft.Graph.Beta -ErrorAction Ignore
Write-Host "Graph module imported successfully." -ForegroundColor Yellow

Connect-MgGraph -Scopes "User.Read.All", "DeviceManagementManagedDevices.Read.All" -NoWelcome

$deviceName = Read-Host "What is the device's hostname?"
$device = Get-MgBetaDeviceManagementManagedDevice -Filter "contains(deviceName,'$deviceName')"

if ($device) {
    $lastusers = $device.UsersLoggedOn

    $usersList = @()

    foreach ($user in $lastusers) {
        $lastlogon = $user.LastLogOnDateTime
        $userobject = [PSCustomObject]@{
            UserID = $user.userid
            PrimaryUser = $device.UserPrincipalName
            DisplayName = (Get-MgBetaUser -UserId $user.UserId).DisplayName
            LastLoggedOnDateTime = $lastLogon
        }
        $usersList += $userObject
    }
    $usersList | Format-List
} else {
    Write-Output "Device not found."
}