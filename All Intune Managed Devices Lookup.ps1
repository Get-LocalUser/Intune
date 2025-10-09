# Microsoft Graph Beta
if (-not (Get-InstalledModule -Name Microsoft.Graph.Beta)) {
    Write-Host "Installing Graph module. This will take a few minutes..." -ForegroundColor Yellow
    Install-Module -Name Microsoft.Graph.Beta -Scope CurrentUser -Force -Verbose
}
Import-Module Microsoft.Graph.Beta -ErrorAction Ignore
Write-Host "Graph module imported successfully." -ForegroundColor Yellow

Connect-MgGraph -Scopes "Device.Read.All" -NoWelcome

# Enter the user
$username = Read-Host "Enter the name of the user"

$devices = Get-MgBetaDeviceManagementManagedDevice -Filter "userPrincipalName eq '$username'"
if ($null -eq $devices) {
    Write-Host "No devices found"`n -ForegroundColor Yellow
    return
}

$devices | ForEach-Object {
    [PSCustomObject]@{
        ID = $_.Id
        DeviceName = $_.DeviceName
        Type = $_.DeviceType
        Model = $_.Model
        Compliant = $_.ComplianceState
        EnrolledDate = $_.EnrolledDateTime
        EnrolledBy = $_.EnrolledByUserPrincipalName
    }
} | Format-Table