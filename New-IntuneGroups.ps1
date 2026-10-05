# ============================================================
# PARAMS
# ============================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z]+$')]
    [string]$Initials,

    [Parameter(Mandatory)]
    [ValidateSet("Windows", "iOS")]
    [string]$Platform,

    [Parameter(Mandatory)]
    [string]$ProfileName,

    [Parameter(Mandatory)]
    [string]$Description,

    [Parameter(Mandatory)]
    [bool]$TestGroup,

    [Parameter(Mandatory)]
    [bool]$ConfigurationProfile
)


# ============================================================
# CONFIGURATION
# ============================================================


if ($TestGroup) {
    $TestGroupPrefix = "$($Initials.ToUpper())-TEST-"
}
else {
    $TestGroupPrefix = ""
}

switch ($Platform.ToLower()) {
    {$_ -in @("windows", "win")} {$GroupNamePrefix = "Win"}
    {$_ -in @("ios")} {$GroupNamePrefix = "iOS"}
}

# ============================================================
# CONNECT TO GRAPH
# ============================================================

Connect-MgGraph -Scopes "Group.ReadWrite.All" -NoWelcome

# ============================================================
# CREATE GROUP NAMES
# ============================================================


$AssignmentGroupName = "$TestGroupPrefix$GroupNamePrefix-$ProfileName"
$ExclusionGroupName = "$TestGroupPrefix$GroupNamePrefix-$ProfileName-EXCLUSION"


$AssignmentGroupMailNickname = (
    "$GroupNamePrefix-$ProfileName-Assignment"
) -replace '[^a-zA-Z0-9]', ''

$ExclusionGroupMailNickname = (
    "$GroupNamePrefix-$ProfileName-Exclusion"
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
    -Description $Description `
    -MailEnabled:$false `
    -MailNickname $ExclusionGroupMailNickname `
    -SecurityEnabled:$true

Write-Host "Created:" $ExclusionGroup.DisplayName `
    "[$($ExclusionGroup.Id)]" `
    -ForegroundColor Green



# ============================================================
# CREATE CONFIGURATION PROFILE
# ============================================================

if ($ConfigurationProfile) {

    $Profile = New-MgBetaDeviceManagementConfigurationPolicy `
    -Name $ProfileName `
    -Description "" `
    -Platforms "windows10" `
    -Technologies "mdm"

}


# ============================================================
# OUTPUT
# ============================================================

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Groups Created" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

[PSCustomObject]@{
    ProfileName       = $ProfileName
    AssignmentGroup   = $AssignmentGroup.DisplayName
    AssignmentGroupId = $AssignmentGroup.Id
    ExclusionGroup    = $ExclusionGroup.DisplayName
    ExclusionGroupId  = $ExclusionGroup.Id
}