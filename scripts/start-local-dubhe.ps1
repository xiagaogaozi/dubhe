param(
    [switch]$SkipDesktop,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function ConvertTo-PowerShellLiteral {
    param([string]$Value)
    $escaped = $Value.Replace("'", "''")
    return "'" + $escaped + "'"
}

function Test-DubheCoreHealth {
    param([string]$Url)

    try {
        $response = Invoke-RestMethod -Uri "$Url/health" -TimeoutSec 2
        return $response.status -eq "ok" -and $response.service -eq "dubhe-core"
    } catch {
        return $false
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$coreRoot = Join-Path $repoRoot "services\core"
$theiaRoot = Join-Path $repoRoot "apps\theia-desktop"
$coreRunScript = Join-Path $coreRoot "scripts\run.ps1"
$desktopExe = Join-Path $theiaRoot "app\dist\win-unpacked\Dubhe.exe"
$runRoot = Join-Path $repoRoot ".dubhe-run"
$coreLog = Join-Path $runRoot "core.log"
$desktopLog = Join-Path $runRoot "theia.log"
$coreUrl = "http://127.0.0.1:8000"

New-Item -ItemType Directory -Force -Path $runRoot | Out-Null

if (-not (Test-Path $coreRunScript)) {
    throw "Dubhe Core run script was not found: $coreRunScript"
}

Write-Host "Dubhe local launcher"
Write-Host "Repository: $repoRoot"
Write-Host "Core: $coreUrl"
Write-Host "Logs: $runRoot"

if ($DryRun) {
    Write-Host "DryRun: paths checked, no process will be started."
    if (Test-Path $desktopExe) {
        Write-Host "Desktop: $desktopExe"
    } else {
        Write-Host "Desktop: packaged app not found; yarn start fallback will be used."
    }
    exit 0
}

if (Test-DubheCoreHealth -Url $coreUrl) {
    Write-Host "Dubhe Core is already running."
} else {
    Write-Host "Starting Dubhe Core in the background..."
    $coreCommandParts = @()
    $coreCommandParts += 'Set-Location ' + (ConvertTo-PowerShellLiteral $coreRoot)
    $coreCommandParts += '$env:PYTHONUTF8 = ' + (ConvertTo-PowerShellLiteral "1")
    $coreCommandParts += '& ' + (ConvertTo-PowerShellLiteral $coreRunScript) + ' *> ' + (ConvertTo-PowerShellLiteral $coreLog)
    $coreCommand = $coreCommandParts -join "; "

    Start-Process `
        -FilePath "powershell.exe" `
        -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $coreCommand) `
        -WorkingDirectory $coreRoot `
        -WindowStyle Hidden | Out-Null

    $started = $false
    foreach ($attempt in 1..60) {
        if (Test-DubheCoreHealth -Url $coreUrl) {
            $started = $true
            break
        }
        Start-Sleep -Seconds 1
    }

    if (-not $started) {
        throw "Dubhe Core did not start within 60 seconds. Check log: $coreLog"
    }

    Write-Host "Dubhe Core is ready."
}

if ($SkipDesktop) {
    Write-Host "Desktop startup skipped."
    exit 0
}

if (Test-Path $desktopExe) {
    Write-Host "Opening Dubhe Desktop..."
    Start-Process -FilePath $desktopExe -WorkingDirectory (Split-Path -Parent $desktopExe) | Out-Null
    exit 0
}

Write-Host "Packaged Dubhe.exe was not found; falling back to Theia yarn start."

$nodeRoot = Join-Path $env:LOCALAPPDATA 'DubheToolchains\node-v22.23.1-win-x64'
if (Test-Path $nodeRoot) {
    $pathPrefix = $nodeRoot + ';' + $env:PATH
} else {
    $pathPrefix = $env:PATH
}
$desktopCommandParts = @()
$desktopCommandParts += 'Set-Location ' + (ConvertTo-PowerShellLiteral $theiaRoot)
$desktopCommandParts += '$env:PATH = ' + (ConvertTo-PowerShellLiteral $pathPrefix)
$desktopCommandParts += 'yarn start *> ' + (ConvertTo-PowerShellLiteral $desktopLog)
$desktopCommand = $desktopCommandParts -join "; "

Start-Process `
    -FilePath "powershell.exe" `
    -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $desktopCommand) `
    -WorkingDirectory $theiaRoot `
    -WindowStyle Hidden | Out-Null

Write-Host "Theia dev startup has been requested. Log: $desktopLog"
