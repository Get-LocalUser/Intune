# ============================================================
# CONFIGURATION
# ============================================================

do {
    $TestGroup = Read-Host "Is this a test group? [Y/N]"
    $TestGroup = $TestGroup.ToUpper()
} while ($TestGroup -notin @("Y", "N")) 
if ($TestGroup.Contains("Y")) {$TestGroup = "HRK-TEST-"} else {
    $TestGroup = $null
}

$PrefixSelection = Read-Host "Windows or iOS Profile?"

switch ($PrefixSelection.ToLower()) {
    "windows" {$GroupNamePrefix = "Win"}
    "ios" {$GroupNamePrefix = "iOS"}

    Default {
        Write-Host "Invalid selection. Please enter Windows or iOS." -ForegroundColor Red
        exit
    }
}


# Change these values for each configuration profile
$ProfileName = Read-Host "Enter Configuration Profile name. PREFIX will be added automatically"

# Optional description
$GroupDescription = Read-Host "Enter group description"


# ============================================================
# CONNECT TO MICROSOFT GRAPH
# ============================================================

Connect-MgGraph -Scopes "Group.ReadWrite.All" -NoWelcome

# ============================================================
# CREATE GROUP NAMES
# ============================================================


$AssignmentGroupName = "$TestGroup$GroupNamePrefix-$ProfileName"
$ExclusionGroupName = "$TestGroup$GroupNamePrefix-$ProfileName-EXCLUSION"

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
    -Description $GroupDescription `
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
    -Description $GroupDescription `
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