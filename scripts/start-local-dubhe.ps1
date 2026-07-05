param(
    [switch]$SkipDesktop,
    [switch]$RunCheck,
    [switch]$RestartCore,
    [switch]$StopCoreOnly,
    [int]$CorePort = 8000,
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

function Stop-ProcessTreeById {
    param([int]$RootPid)

    $allProcesses = @(Get-CimInstance Win32_Process)
    $seen = [System.Collections.Generic.HashSet[int]]::new()
    $pending = [System.Collections.Generic.Queue[int]]::new()
    $pending.Enqueue($RootPid)

    while ($pending.Count -gt 0) {
        $currentPid = $pending.Dequeue()
        if (-not $seen.Add($currentPid)) {
            continue
        }

        $children = @(
            $allProcesses |
                Where-Object {
                    $_.ParentProcessId -eq $currentPid -or
                    ($_.CommandLine -and $_.CommandLine -like "*parent_pid=$currentPid*")
                }
        )
        foreach ($child in $children) {
            $pending.Enqueue([int]$child.ProcessId)
        }
    }

    $processIds = @($seen | Sort-Object -Descending)
    foreach ($processId in $processIds) {
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($null -eq $process) {
            continue
        }
        Write-Host "Stopping existing Dubhe Core process PID $processId..."
        Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
    }
}

function Stop-DubheCorePort {
    param([int]$Port)

    $knownCoreProcesses = @(
        Get-CimInstance Win32_Process |
            Where-Object {
                $commandLine = $_.CommandLine
                if ([string]::IsNullOrWhiteSpace($commandLine)) {
                    return $false
                }
                $matchesCoreApp = $commandLine -like "*dubhe_core.main:app*" -and $commandLine -like "*--port $Port*"
                $matchesRunScript = $commandLine -like "*services\core*" -and $commandLine -like "*run.ps1*" -and $commandLine -like "*-Port $Port*"
                return $matchesCoreApp -or $matchesRunScript
            }
    )
    foreach ($coreProcess in $knownCoreProcesses) {
        Stop-ProcessTreeById -RootPid ([int]$coreProcess.ProcessId)
    }

    foreach ($attempt in 1..30) {
        Start-Sleep -Milliseconds 300
        $connections = @(
            Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
                Select-Object -Property OwningProcess -Unique
        )
        if ($connections.Count -eq 0) {
            return
        }

        $handledConnection = $false
        foreach ($connection in $connections) {
            $ownerPid = [int]$connection.OwningProcess
            if ($ownerPid -le 0) {
                continue
            }

            $process = Get-Process -Id $ownerPid -ErrorAction SilentlyContinue
            if ($null -eq $process) {
                $orphans = @(
                    Get-CimInstance Win32_Process |
                        Where-Object { $_.CommandLine -and $_.CommandLine -like "*parent_pid=$ownerPid*" }
                )
                if ($orphans.Count -gt 0) {
                    foreach ($orphan in $orphans) {
                        Stop-ProcessTreeById -RootPid ([int]$orphan.ProcessId)
                    }
                    $handledConnection = $true
                    continue
                }
                if ($attempt -eq 30) {
                    throw "Port $Port is already in use by PID $ownerPid, but Windows did not expose the process details. Close that process manually, or start Dubhe with -CorePort 8001."
                }
                continue
            }

            if ($process.ProcessName -notmatch "python|uvicorn") {
                throw "Port $Port is used by $($process.ProcessName) (PID $($process.Id)); not stopping it automatically."
            }

            Stop-ProcessTreeById -RootPid $process.Id
            $handledConnection = $true
        }

        if (-not $handledConnection -and $attempt -eq 30) {
            throw "Port $Port is still in use after stopping known Dubhe Core processes."
        }
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$coreRoot = Join-Path $repoRoot "services\core"
$theiaRoot = Join-Path $repoRoot "apps\theia-desktop"
$coreRunScript = Join-Path $coreRoot "scripts\run.ps1"
$coreSetupScript = Join-Path $coreRoot "scripts\setup.ps1"
$corePython = Join-Path $coreRoot ".venv\Scripts\python.exe"
$checkScript = Join-Path $repoRoot "scripts\check-local-dubhe.ps1"
$desktopExe = Join-Path $theiaRoot "app\dist\win-unpacked\Dubhe.exe"
$runRoot = Join-Path $repoRoot ".dubhe-run"
$coreLog = Join-Path $runRoot "core.log"
$coreErrorLog = Join-Path $runRoot "core.err.log"
$desktopLog = Join-Path $runRoot "theia.log"
$coreUrl = "http://127.0.0.1:$CorePort"

New-Item -ItemType Directory -Force -Path $runRoot | Out-Null

if (-not (Test-Path $coreRunScript)) {
    throw "Dubhe Core run script was not found: $coreRunScript"
}
if (-not (Test-Path $coreSetupScript)) {
    throw "Dubhe Core setup script was not found: $coreSetupScript"
}

Write-Host "Dubhe local launcher"
Write-Host "Repository: $repoRoot"
Write-Host "Core: $coreUrl"
Write-Host "Logs: $runRoot"

if ($DryRun) {
    Write-Host "DryRun: paths checked, no process will be started."
    if ($RestartCore) {
        Write-Host "RestartCore: would stop Python/uvicorn listener on port $CorePort before starting Core."
    }
    if ($StopCoreOnly) {
        Write-Host "StopCoreOnly: would stop Dubhe Core on port $CorePort and exit."
    }
    if (Test-Path $checkScript) {
        Write-Host "Check script: $checkScript"
    }
    if (Test-Path $desktopExe) {
        Write-Host "Desktop: $desktopExe"
    } else {
        Write-Host "Desktop: packaged app not found; yarn start fallback will be used."
    }
    exit 0
}

if ($StopCoreOnly) {
    Stop-DubheCorePort -Port $CorePort
    Write-Host "Dubhe Core stop requested for port $CorePort."
    exit 0
}

if ($RestartCore) {
    Stop-DubheCorePort -Port $CorePort
}

if (Test-DubheCoreHealth -Url $coreUrl) {
    Write-Host "Dubhe Core is already running."
} else {
    Write-Host "Starting Dubhe Core in the background..."
    if (-not (Test-Path $corePython)) {
        Write-Host "Core Python environment was not found; running setup first..."
        & $coreSetupScript
    }
    if (-not (Test-Path $corePython)) {
        throw "Core Python was not found after setup: $corePython"
    }

    $previousPythonUtf8 = $env:PYTHONUTF8
    $env:PYTHONUTF8 = "1"
    Start-Process `
        -FilePath $corePython `
        -ArgumentList @("-m", "uvicorn", "dubhe_core.main:app", "--reload", "--host", "127.0.0.1", "--port", "$CorePort") `
        -WorkingDirectory $coreRoot `
        -RedirectStandardOutput $coreLog `
        -RedirectStandardError $coreErrorLog `
        -WindowStyle Hidden | Out-Null
    $env:PYTHONUTF8 = $previousPythonUtf8

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

if ($RunCheck) {
    if (-not (Test-Path $checkScript)) {
        throw "Dubhe local check script was not found: $checkScript"
    }
    Write-Host ""
    & $checkScript -CoreUrl $coreUrl
    Write-Host ""
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
