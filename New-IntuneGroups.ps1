# ============================================================
# PARAMS
# ============================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet("Windows", "Win", "iOS")]
    [string]$Platform,

    [Parameter(Mandatory)]
    [string]$ProfileName,

    [Parameter(Mandatory)]
    [string]$Description,

    [Parameter(Mandatory)]
    [ValidateSet("True", "False", "Yes")]
    [string]$TestGroup,

    [Parameter]
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