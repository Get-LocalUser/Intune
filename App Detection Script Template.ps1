$regPath = ""

if (Test-Path $regPath) {
    $displayName = (Get-ItemProperty -Path $regPath -Name "DisplayName" -ErrorAction SilentlyContinue).DisplayName

    if ($displayName -eq "") {
        Write-Output "Detected"
        exit 0
    }
}

exit 1