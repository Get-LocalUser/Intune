<#
.DESCRIPTION
Creates an assignment group and a corresponding exclusion group based on the
specified portal, platform, target, and group name. Connects to Microsoft Graph, assigns the
signed-in user as group owner, and outputs the created group details and IDs.
#>


# ============================================================
# PARAMS
# ============================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet("Intune", "Exchange", "Entra", "SharePoint", "Defender", "Purview")]
    [string]$Portal,

    [Parameter(Mandatory)]
    [ValidateSet("Windows", "Win", "iOS", "macOS")]
    [string]$Platform,

    [Parameter(Mandatory)]
    [ValidateSet("User", "Device")]
    [string]$Target,

    [Parameter(Mandatory)]
    [string]$GroupName,

    [Parameter(Mandatory)]
    [string]$Description,

    [Parameter(Mandatory)]
    [ValidateSet("True", "False", "Yes", "No")]
    [string]$TestGroup,

    [Parameter()]
    [ValidatePattern('^[A-Za-z]+$')]
    [string]$Initials
)


# ============================================================
# CONFIGURATION
# ============================================================


if ($TestGroup -in @("True", "Yes")) {
    $Initials = Read-Host "Enter initials"
    $TestGroupPrefix = "$($Initials.ToUpper())-TEST-"
}
else {
    $TestGroupPrefix = $null
}

switch ($Platform.ToLower()) {
    {$_ -in @("windows", "win")} {$GroupNamePrefix = "Win"}
    {$_ -in @("ios")} {$GroupNamePrefix = "iOS"}
    {$_ -in @("macos")} {$GroupNamePrefix = "macOS"}
}

# ============================================================
# CONNECT TO GRAPH
# ============================================================

Connect-MgGraph -Scopes "Group.ReadWrite.All" -NoWelcome

# ============================================================
# CREATE GROUP NAMES
# ============================================================

$GroupName = $GroupName.Trim()

# Format: [INITIALS-TEST-]Portal-Platform-Target-GroupName
# Example: HRK-TEST-Intune-Win-Device-The New Test Group Again
$AssignmentGroupName = "$TestGroupPrefix$Portal-$GroupNamePrefix-$Target-$GroupName"
$ExclusionGroupName = "$TestGroupPrefix$Portal-$GroupNamePrefix-$Target-$GroupName-EXCLUSION"


$AssignmentGroupMailNickname = (
    "$Portal-$GroupNamePrefix-$Target-$GroupName-Assignment"
) -replace '[^a-zA-Z0-9]', ''

$ExclusionGroupMailNickname = (
    "$Portal-$GroupNamePrefix-$Target-$GroupName-Exclusion"
) -replace '[^a-zA-Z0-9]', ''


# ============================================================
# CREATE ASSIGNMENT GROUP
# ============================================================

Write-Host "Creating assignment group..." -ForegroundColor Cyan

$AssignmentGroup = New-MgBetaGroup `
    -DisplayName $AssignmentGroupName `
    -Description $Description `
    -MailEnabled:$false `
    -MailNickname $AssignmentGroupMailNickname `
    -SecurityEnabled:$true

    Write-Host "Created:" $AssignmentGroup.DisplayName `
    "[$($AssignmentGroup.Id)]" `
    -ForegroundColor Green


# ============================================================
# CREATE EXCLUSION GROUP
# ============================================================

Write-Host "Creating exclusion group..." -ForegroundColor Cyan

$ExclusionGroup = New-MgBetaGroup `
    -DisplayName $ExclusionGroupName `
    -MailEnabled:$false `
    -MailNickname $ExclusionGroupMailNickname `
    -SecurityEnabled:$true

Write-Host "Created:" $ExclusionGroup.DisplayName `
    "[$($ExclusionGroup.Id)]" `
    -ForegroundColor Green


# ============================================================
# Add Owner to Groups
# ============================================================   

$CloudUser = Get-MgBetaUser -UserId (Get-MgContext).Account

Write-Host "`nAssigning '$($CloudUser.UserPrincipalName)' as owner of newly created groups" -ForegroundColor Yellow

$OwnerReference = @{
    "@odata.id" = "https://graph.microsoft.com/beta/users/$($CloudUser.Id)"
}

New-MgBetaGroupOwnerByRef `
    -GroupId $AssignmentGroup.Id `
    -BodyParameter $OwnerReference

New-MgBetaGroupOwnerByRef `
    -GroupId $ExclusionGroup.Id `
    -BodyParameter $OwnerReference


$AssignmentOwners = Get-MgBetaGroupOwner -GroupId $AssignmentGroup.Id
$ExclusionOwners = Get-MgBetaGroupOwner -GroupId $ExclusionGroup.Id


# ============================================================
# OUTPUT
# ============================================================

Write-Host ""
Write-Host "GROUPS CREATED"
Write-Host "──────────────────────────────────────────────────────────" -ForegroundColor DarkGray
[PSCustomObject]@{
    Portal               = $Portal
    Target               = $Target
    GroupName            = $GroupName
    AssignmentGroup      = $AssignmentGroup.DisplayName
    AssignmentGroupId    = $AssignmentGroup.Id
    AssignmentGroupOwner = ($AssignmentOwners | ForEach-Object { $_.AdditionalProperties.userPrincipalName }) -join ", "
    ExclusionGroup       = $ExclusionGroup.DisplayName
    ExclusionGroupId     = $ExclusionGroup.Id
    ExclusionGroupOwner  = ($ExclusionOwners | ForEach-Object { $_.AdditionalProperties.userPrincipalName }) -join ", "
}