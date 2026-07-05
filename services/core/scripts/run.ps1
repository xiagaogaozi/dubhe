param(
    [string]$HostName = "127.0.0.1",
    [int]$Port = 8000
)

$ErrorActionPreference = "Stop"

$serviceRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $serviceRoot)
$configLoader = Join-Path $repoRoot "scripts\dubhe-config.ps1"
if (Test-Path $configLoader) {
    . $configLoader
    Import-DubheLocalConfig -RepoRoot $repoRoot | Out-Null
}

Set-Location $serviceRoot

if (-not (Test-Path ".venv")) {
    & "$PSScriptRoot\setup.ps1"
}

.\.venv\Scripts\python.exe -m uvicorn dubhe_core.main:app --reload --host $HostName --port $Port
