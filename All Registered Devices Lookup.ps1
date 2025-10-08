# Microsoft Graph Beta
if (-not (Get-InstalledModule -Name Microsoft.Graph.Beta)) {
    Write-Host "Installing Graph module. This will take a few minutes..." -ForegroundColor Yellow
    Install-Module -Name Microsoft.Graph.Beta -Scope CurrentUser -Force -Verbose
}
Import-Module Microsoft.Graph.Beta -ErrorAction Ignore
Write-Host "Graph module imported successfully." -ForegroundColor Yellow

Connect-MgGraph -Scopes "Directory.Read.All" -NoWelcome

# ___________________________________________________________________________________________________________
Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "   This script retrieves *Entra ID registered devices* for a user." -ForegroundColor Yellow
Write-Host ""
Write-Host "⚠️  IMPORTANT:" -ForegroundColor Red
Write-Host " - These are devices registered or joined to Entra ID (Azure AD)." -ForegroundColor White
Write-Host " - This 'can' include Intune-managed devices by overlap but that is NOT its intended purpose." -ForegroundColor White
Write-Host " - Expect to see BYOD, personal, or Azure AD joined devices that appear" -ForegroundColor White
Write-Host "   under the user's Devices tab in the Entra admin portal." -ForegroundColor White
Write-Host ""
Write-Host " - In short: This shows identity-level registrations (Entra), not" -ForegroundColor White
Write-Host "   management-level devices (Intune)." -ForegroundColor White
Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
Write-Host ""
Start-Sleep -Seconds 2
# ___________________________________________________________________________________________________________

# Enter the user
$username = Read-Host "Enter the name of the user"

$devices = Get-MgBetaUserRegisteredDevice -UserId $username

$devices | ForEach-Object {
    $props = $_.AdditionalProperties
    [PSCustomObject]@{
        DisplayName        = $props.displayName
        DeviceId           = $props.deviceId
        OS                 = $props.operatingSystem
        OSVersion          = $props.operatingSystemVersion
        TrustType          = $props.trustType
        ProfileType        = $props.profileType
        CreatedDate        = $props.createdDateTime
        RegistrationDate   = $props.registrationDateTime
        LastSignIn         = $props.approximateLastSignInDateTime
        AccountEnabled     = $props.accountEnabled
    }
} | Format-Table