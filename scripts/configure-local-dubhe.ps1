$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$configDir = Join-Path $repoRoot "config"
$examplePath = Join-Path $configDir "dubhe.local.env.example"
$localPath = Join-Path $configDir "dubhe.local.env"

New-Item -ItemType Directory -Force -Path $configDir | Out-Null

if (-not (Test-Path $examplePath)) {
    throw "Template not found: $examplePath"
}

if (-not (Test-Path $localPath)) {
    Copy-Item -Path $examplePath -Destination $localPath
    Write-Host "Created local config: $localPath"
} else {
    Write-Host "Opening existing local config: $localPath"
}

Write-Host ""
Write-Host "Edit values after '=' and remove the leading '# ' to enable an item."
Write-Host "Save the file, then restart Dubhe Core with Start-Dubhe.cmd."
Write-Host ""

Start-Process notepad.exe -ArgumentList @($localPath) | Out-Null

