$ErrorActionPreference = "Stop"

$serviceRoot = Split-Path -Parent $PSScriptRoot
Set-Location $serviceRoot

if (-not (Test-Path ".venv")) {
    & "$PSScriptRoot\setup.ps1"
}

.\.venv\Scripts\python.exe -m ruff check .
.\.venv\Scripts\python.exe -m pytest

