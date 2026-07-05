param(
    [switch]$SkipDesktop,
    [switch]$SkipStartMenu,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function New-DubheShortcut {
    param(
        [string]$ShortcutPath,
        [string]$TargetPath,
        [string]$Description,
        [string]$IconPath,
        [switch]$DryRun
    )

    if ($DryRun) {
        Write-Host "DryRun: would create shortcut $ShortcutPath -> $TargetPath"
        return
    }

    $shortcutDirectory = Split-Path -Parent $ShortcutPath
    New-Item -ItemType Directory -Force -Path $shortcutDirectory | Out-Null

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.WorkingDirectory = Split-Path -Parent $TargetPath
    $shortcut.Description = $Description
    if ($IconPath -and (Test-Path $IconPath)) {
        $shortcut.IconLocation = $IconPath
    }
    $shortcut.Save()
    Write-Host "Created: $ShortcutPath"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$entries = @(
    @{
        name = "Start Dubhe"
        file = Join-Path $repoRoot "Start-Dubhe.cmd"
        description = "Start Dubhe Core and open Dubhe Desktop."
    },
    @{
        name = "Configure Dubhe"
        file = Join-Path $repoRoot "Configure-Dubhe.cmd"
        description = "Open Dubhe local runtime configuration."
    },
    @{
        name = "Check Dubhe"
        file = Join-Path $repoRoot "Check-Dubhe.cmd"
        description = "Check local Dubhe Core, desktop, mobile toolchain, and package readiness."
    },
    @{
        name = "Smoke Dubhe"
        file = Join-Path $repoRoot "Smoke-Dubhe.cmd"
        description = "Run Dubhe Core account, news, AI, backtest, paper trading, and sync smoke test."
    },
    @{
        name = "Stop Dubhe Core"
        file = Join-Path $repoRoot "Stop-Dubhe-Core.cmd"
        description = "Stop local Dubhe Core backend service."
    }
)
$iconPath = Join-Path $repoRoot "apps\theia-desktop\app\resources\icon.ico"

foreach ($entry in $entries) {
    if (-not (Test-Path $entry.file)) {
        throw "Missing entry file: $($entry.file)"
    }
}

Write-Host "Dubhe Windows shortcut installer"
Write-Host "Repository: $repoRoot"

if (-not $SkipDesktop) {
    $desktop = [Environment]::GetFolderPath("DesktopDirectory")
    foreach ($entry in $entries) {
        New-DubheShortcut `
            -ShortcutPath (Join-Path $desktop "$($entry.name).lnk") `
            -TargetPath $entry.file `
            -Description $entry.description `
            -IconPath $iconPath `
            -DryRun:$DryRun
    }
}

if (-not $SkipStartMenu) {
    $programs = [Environment]::GetFolderPath("Programs")
    $startMenuFolder = Join-Path $programs "Dubhe"
    foreach ($entry in $entries) {
        New-DubheShortcut `
            -ShortcutPath (Join-Path $startMenuFolder "$($entry.name).lnk") `
            -TargetPath $entry.file `
            -Description $entry.description `
            -IconPath $iconPath `
            -DryRun:$DryRun
    }
}

Write-Host "Done."
