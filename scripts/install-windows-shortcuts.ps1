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
        name = "Start Dubhe LAN"
        file = Join-Path $repoRoot "Start-Dubhe-LAN.cmd"
        description = "Start Dubhe Core for phones on the same Wi-Fi and open Dubhe Desktop."
    },
    @{
        name = "Connect Dubhe Mobile"
        file = Join-Path $repoRoot "Connect-Dubhe-Mobile.cmd"
        description = "Start LAN Core and open a phone connection card with URL and QR code."
    },
    @{
        name = "Build Dubhe User Kit"
        file = Join-Path $repoRoot "Build-Dubhe-User-Kit.cmd"
        description = "Gather installers, APKs, guides, checks, and this-PC launchers for internal users."
    },
    @{
        name = "Prepare Dubhe Delivery"
        file = Join-Path $repoRoot "Prepare-Dubhe-Delivery.cmd"
        description = "Build the latest Dubhe delivery ZIP and write its SHA256 summary."
    },
    @{
        name = "Verify Dubhe Delivery"
        file = Join-Path $repoRoot "Verify-Dubhe-Delivery.cmd"
        description = "Verify the latest Dubhe delivery ZIP hash, required installers, and checksums."
    },
    @{
        name = "Dubhe Mobile Guide"
        file = Join-Path $repoRoot "Open-Dubhe-Mobile-Guide.cmd"
        description = "Open the Chinese phone/tablet install and connection guide."
    },
    @{
        name = "Dubhe Install Guide"
        file = Join-Path $repoRoot "Open-Dubhe-Install-Guide.cmd"
        description = "Open the Chinese Windows, macOS, iOS, and Android package guide."
    },
    @{
        name = "Configure Dubhe"
        file = Join-Path $repoRoot "Configure-Dubhe.cmd"
        description = "Open Dubhe local runtime configuration."
    },
    @{
        name = "Setup Dubhe MFA"
        file = Join-Path $repoRoot "Setup-Dubhe-MFA.cmd"
        description = "Create a local TOTP MFA setup card for Dubhe account login."
    },
    @{
        name = "Accept Dubhe"
        file = Join-Path $repoRoot "Accept-Dubhe.cmd"
        description = "Run local acceptance: readiness check, smoke workflow, and external service status."
    },
    @{
        name = "Verify Dubhe Audit"
        file = Join-Path $repoRoot "Verify-Dubhe-Audit.cmd"
        description = "Verify the local audit log hash chain."
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
        name = "Test Dubhe Services"
        file = Join-Path $repoRoot "Test-Dubhe-Services.cmd"
        description = "Live-check configured AI and financial news services through Dubhe Core."
    },
    @{
        name = "Check Dubhe Production"
        file = Join-Path $repoRoot "Check-Dubhe-Production.cmd"
        description = "Check whether Dubhe is ready for real commercial production use."
    },
    @{
        name = "Export Dubhe Production Pack"
        file = Join-Path $repoRoot "Export-Dubhe-Production-Pack.cmd"
        description = "Export Chinese production blockers, owners, evidence, and vendor/account checklist."
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
