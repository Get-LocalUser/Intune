# Author is Get-Rubix 
# Just here for me

# Define the shortcut path
Write-Host "Setting Chrome shortcut on Public Desktop"
$publicDesktop = [System.Environment]::GetFolderPath('CommonDesktopDirectory')
$shortcutPath = Join-Path -Path $publicDesktop -ChildPath "Google Chrome.lnk"

# Set the target for Chrome
$chromePath = "$($env:ProgramFiles)\Google\Chrome\Application\chrome.exe"

# Check if shortcut exists
if (Test-Path $shortcutPath) {
    Write-Host "Chrome shortcut already exists"
    Exit
} else {
    # Create and set shortcut
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)

    # Set the shortcut properties
    $shortcut.TargetPath = $chromePath
    $shortcut.WorkingDirectory = Split-Path -Path $chromePath
    $shortcut.Description = "Shortcut to Google Chrome"
    $shortcut.IconLocation = "$chromePath, 0"

    # Save shortcut
    $shortcut.Save()
    Write-Host "Shortcut created successfully at $shortcutPath"
}

New-Item -Path "C:\ProgramData\Microsoft" -Name "Chromeshortcutinstalled.tag"
