param(
    [string]$HostName = "127.0.0.1",
    [int]$Port = 8000
)

$ErrorActionPreference = "Stop"

$serviceRoot = Split-Path -Parent $PSScriptRoot
Set-Location $serviceRoot

if (-not (Test-Path ".venv")) {
    & "$PSScriptRoot\setup.ps1"
}

.\.venv\Scripts\python.exe -m uvicorn dubhe_core.main:app --reload --host $HostName --port $Port
