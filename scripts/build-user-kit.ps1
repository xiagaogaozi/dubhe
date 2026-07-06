param(
    [string]$CoreUrl = "http://127.0.0.1:8000",
    [string]$OutputRoot = "",
    [switch]$NoZip,
    [switch]$OpenFolder
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Resolve-NewestFile {
    param(
        [string]$Directory,
        [string]$Pattern
    )

    if (-not (Test-Path $Directory)) {
        return $null
    }
    $files = @(
        Get-ChildItem -Path $Directory -Filter $Pattern -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending
    )
    if ($files.Count -eq 0) {
        return $null
    }
    return $files[0].FullName
}

function Get-LanCoreUrls {
    param([int]$Port)

    $preferredAddresses = @(
        Get-NetIPConfiguration -ErrorAction SilentlyContinue |
            Where-Object { $_.IPv4DefaultGateway -and $_.IPv4Address } |
            ForEach-Object { $_.IPv4Address.IPAddress } |
            Where-Object { $_ -and $_ -ne "127.0.0.1" -and $_ -notlike "169.254.*" } |
            Select-Object -Unique
    )
    $privatePreferredAddresses = @(
        $preferredAddresses |
            Where-Object { $_ -match '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)' }
    )
    if ($privatePreferredAddresses.Count -gt 0) {
        return @($privatePreferredAddresses | ForEach-Object { "http://$($_):$Port" })
    }
    if ($preferredAddresses.Count -gt 0) {
        return @($preferredAddresses | ForEach-Object { "http://$($_):$Port" })
    }

    $addresses = @(
        Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object {
                $_.IPAddress -and
                $_.IPAddress -ne "127.0.0.1" -and
                $_.IPAddress -notlike "169.254.*" -and
                $_.AddressState -eq "Preferred"
            } |
            Select-Object -ExpandProperty IPAddress -Unique
    )
    return @($addresses | ForEach-Object { "http://$($_):$Port" })
}

function Format-DetectedPath {
    param([string]$Path)

    if ($Path -and (Test-Path $Path)) {
        return $Path
    }
    return "(not built)"
}

function Copy-Artifact {
    param(
        [string]$Path,
        [string]$DestinationDirectory,
        [string]$Label
    )

    if (-not $Path -or -not (Test-Path $Path)) {
        return [pscustomobject]@{
            label = $Label
            available = $false
            source = $Path
            copied_to = $null
            size_bytes = 0
            sha256 = $null
        }
    }

    New-Item -ItemType Directory -Force -Path $DestinationDirectory | Out-Null
    $destination = Join-Path $DestinationDirectory (Split-Path -Leaf $Path)
    Copy-Item -LiteralPath $Path -Destination $destination -Force
    $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $destination
    return [pscustomobject]@{
        label = $Label
        available = $true
        source = $Path
        copied_to = $destination
        size_bytes = (Get-Item -LiteralPath $destination).Length
        sha256 = $hash.Hash
    }
}

function Copy-DirectoryArtifact {
    param(
        [string]$Path,
        [string]$DestinationDirectory,
        [string]$Label
    )

    if (-not $Path -or -not (Test-Path $Path)) {
        return [pscustomobject]@{
            label = $Label
            available = $false
            source = $Path
            copied_to = $null
            size_bytes = 0
            file_count = 0
            sha256 = $null
        }
    }

    New-Item -ItemType Directory -Force -Path $DestinationDirectory | Out-Null
    $destination = Join-Path $DestinationDirectory (Split-Path -Leaf $Path)
    Copy-Item -LiteralPath $Path -Destination $destination -Recurse -Force
    $files = @(Get-ChildItem -LiteralPath $destination -Recurse -File)
    $sizeBytes = ($files | Measure-Object -Property Length -Sum).Sum
    if ($null -eq $sizeBytes) {
        $sizeBytes = 0
    }
    return [pscustomobject]@{
        label = $Label
        available = $true
        source = $Path
        copied_to = $destination
        size_bytes = [int64]$sizeBytes
        file_count = $files.Count
        sha256 = $null
    }
}

function Write-Launcher {
    param(
        [string]$Path,
        [string]$Title,
        [string]$TargetScript
    )

    $content = @(
        "@echo off",
        "echo $Title",
        "echo.",
        "call `"$TargetScript`"",
        "set `"DUBHE_EXIT=%ERRORLEVEL%`"",
        "echo.",
        "pause",
        "exit /b %DUBHE_EXIT%"
    ) -join "`r`n"
    Set-Content -Path $Path -Encoding ASCII -Value ($content + "`r`n")
}

function Invoke-QuietScript {
    param(
        [string]$ScriptPath,
        [string[]]$Arguments = @(),
        [string]$Path
    )

    try {
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments 2>&1
        $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
        $report = @()
        $report += $output
        $report += ""
        $report += "Exit code: $exitCode"
        $report | Out-File -FilePath $Path -Encoding UTF8
    } catch {
        "Report command failed: $($_.Exception.Message)" | Out-File -FilePath $Path -Encoding UTF8
    }
}

function Replace-Token {
    param(
        [string]$Content,
        [string]$Token,
        [string]$Value
    )

    return $Content.Replace($Token, $Value)
}

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutputRoot) {
    $OutputRoot = Join-Path $repoRoot ".dubhe-run\user-kits"
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$kitRoot = Join-Path $OutputRoot "Dubhe-User-Kit-$timestamp"
$windowsDir = Join-Path $kitRoot "01-Windows"
$androidDir = Join-Path $kitRoot "02-Android"
$guidesDir = Join-Path $kitRoot "03-Guides"
$checksDir = Join-Path $kitRoot "04-Checks"

$theiaDist = Join-Path $repoRoot "apps\theia-desktop\app\dist"
$mobileRoot = Join-Path $repoRoot "apps\mobile"
$windowsSetup = Resolve-NewestFile $theiaDist "Dubhe-*-win-x64-setup.exe"
$windowsPortable = Resolve-NewestFile $theiaDist "Dubhe-*-win-x64-portable.exe"
$windowsUnpackedDir = Join-Path $theiaDist "win-unpacked"
$windowsUnpackedExe = Join-Path $windowsUnpackedDir "Dubhe.exe"
$windowsUnpacked = if (Test-Path $windowsUnpackedExe) { $windowsUnpackedDir } else { $null }
$androidApk = Join-Path $mobileRoot "build\app\outputs\flutter-apk\app-debug.apk"
$androidAab = Join-Path $mobileRoot "build\app\outputs\bundle\release\app-release.aab"
$lanUrls = @(Get-LanCoreUrls -Port ([System.Uri]$CoreUrl).Port)
$lanText = if ($lanUrls.Count -gt 0) { $lanUrls -join " / " } else { "(no LAN IPv4 address detected)" }

New-Item -ItemType Directory -Force -Path $windowsDir, $androidDir, $guidesDir, $checksDir | Out-Null

$artifacts = @(
    Copy-Artifact -Path $windowsSetup -DestinationDirectory $windowsDir -Label "Windows setup"
    Copy-Artifact -Path $windowsPortable -DestinationDirectory $windowsDir -Label "Windows portable"
    Copy-DirectoryArtifact -Path $windowsUnpacked -DestinationDirectory $windowsDir -Label "Windows unpacked desktop"
    Copy-Artifact -Path $androidApk -DestinationDirectory $androidDir -Label "Android debug APK"
    Copy-Artifact -Path $androidAab -DestinationDirectory $androidDir -Label "Android release AAB"
)

Invoke-QuietScript -ScriptPath (Join-Path $repoRoot "scripts\show-install-guide.ps1") -Path (Join-Path $checksDir "render-install-guide.txt")
Invoke-QuietScript -ScriptPath (Join-Path $repoRoot "scripts\show-mobile-guide.ps1") -Path (Join-Path $checksDir "render-mobile-guide.txt")
Invoke-QuietScript -ScriptPath (Join-Path $repoRoot "scripts\show-mobile-connect.ps1") -Path (Join-Path $checksDir "render-mobile-connect.txt")
$renderedInstallGuide = Join-Path $repoRoot ".dubhe-run\install-guide.txt"
$renderedMobileGuide = Join-Path $repoRoot ".dubhe-run\mobile-quick-start.txt"
$renderedMobileConnectFiles = @(
    "mobile-connect.html",
    "mobile-connect.txt",
    "mobile-core-url.txt",
    "mobile-core-url.svg"
)
if (Test-Path $renderedInstallGuide) {
    Copy-Item -LiteralPath $renderedInstallGuide -Destination (Join-Path $guidesDir "install-guide.txt") -Force
}
if (Test-Path $renderedMobileGuide) {
    Copy-Item -LiteralPath $renderedMobileGuide -Destination (Join-Path $guidesDir "mobile-quick-start.txt") -Force
}
foreach ($fileName in $renderedMobileConnectFiles) {
    $sourcePath = Join-Path $repoRoot ".dubhe-run\$fileName"
    if (Test-Path $sourcePath) {
        Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $guidesDir $fileName) -Force
    }
}
Copy-Item -LiteralPath (Join-Path $repoRoot "README.md") -Destination (Join-Path $guidesDir "README-project.md") -Force

Invoke-QuietScript -ScriptPath (Join-Path $repoRoot "scripts\check-local-dubhe.ps1") -Arguments @("-CoreUrl", $CoreUrl) -Path (Join-Path $checksDir "local-check.txt")
Invoke-QuietScript -ScriptPath (Join-Path $repoRoot "scripts\run-local-acceptance.ps1") -Arguments @("-CoreUrl", $CoreUrl, "-SkipExternalLive") -Path (Join-Path $checksDir "local-acceptance.txt")
Invoke-QuietScript -ScriptPath (Join-Path $repoRoot "scripts\verify-audit-chain.ps1") -Arguments @("-CoreUrl", $CoreUrl) -Path (Join-Path $checksDir "audit-chain-verification.txt")
Invoke-QuietScript -ScriptPath (Join-Path $repoRoot "scripts\test-external-services.ps1") -Arguments @("-CoreUrl", $CoreUrl) -Path (Join-Path $checksDir "external-services.txt")
Invoke-QuietScript -ScriptPath (Join-Path $repoRoot "scripts\check-production-readiness.ps1") -Arguments @("-CoreUrl", $CoreUrl) -Path (Join-Path $checksDir "production-readiness.txt")
Invoke-QuietScript -ScriptPath (Join-Path $repoRoot "scripts\export-production-pack.ps1") -Arguments @("-CoreUrl", $CoreUrl) -Path (Join-Path $checksDir "render-production-pack.txt")

$productionPackSource = Join-Path $repoRoot ".dubhe-run\production-pack"
if (Test-Path $productionPackSource) {
    Copy-Item -LiteralPath $productionPackSource -Destination (Join-Path $guidesDir "production-pack") -Recurse -Force
}

Write-Launcher -Path (Join-Path $kitRoot "00-Start-Dubhe-This-PC.cmd") -Title "Start Dubhe on this PC" -TargetScript (Join-Path $repoRoot "Start-Dubhe.cmd")
Write-Launcher -Path (Join-Path $kitRoot "01-Configure-Dubhe-This-PC.cmd") -Title "Configure Dubhe on this PC" -TargetScript (Join-Path $repoRoot "Configure-Dubhe.cmd")
Write-Launcher -Path (Join-Path $kitRoot "02-Setup-Dubhe-MFA-This-PC.cmd") -Title "Setup Dubhe MFA on this PC" -TargetScript (Join-Path $repoRoot "Setup-Dubhe-MFA.cmd")
Write-Launcher -Path (Join-Path $kitRoot "03-Accept-Dubhe-This-PC.cmd") -Title "Accept Dubhe on this PC" -TargetScript (Join-Path $repoRoot "Accept-Dubhe.cmd")
Write-Launcher -Path (Join-Path $kitRoot "04-Connect-Dubhe-Mobile-This-PC.cmd") -Title "Connect Dubhe mobile on this PC" -TargetScript (Join-Path $repoRoot "Connect-Dubhe-Mobile.cmd")
Write-Launcher -Path (Join-Path $kitRoot "05-Check-Dubhe-This-PC.cmd") -Title "Check Dubhe on this PC" -TargetScript (Join-Path $repoRoot "Check-Dubhe.cmd")
Write-Launcher -Path (Join-Path $kitRoot "06-Verify-Dubhe-Audit-This-PC.cmd") -Title "Verify Dubhe audit chain on this PC" -TargetScript (Join-Path $repoRoot "Verify-Dubhe-Audit.cmd")
Write-Launcher -Path (Join-Path $kitRoot "07-Start-Dubhe-LAN-This-PC.cmd") -Title "Start Dubhe LAN on this PC" -TargetScript (Join-Path $repoRoot "Start-Dubhe-LAN.cmd")
Write-Launcher -Path (Join-Path $kitRoot "08-Test-Services-This-PC.cmd") -Title "Test Dubhe services on this PC" -TargetScript (Join-Path $repoRoot "Test-Dubhe-Services.cmd")
Write-Launcher -Path (Join-Path $kitRoot "09-Check-Production-This-PC.cmd") -Title "Check Dubhe production readiness on this PC" -TargetScript (Join-Path $repoRoot "Check-Dubhe-Production.cmd")
Write-Launcher -Path (Join-Path $kitRoot "10-Export-Production-Pack-This-PC.cmd") -Title "Export Dubhe production pack on this PC" -TargetScript (Join-Path $repoRoot "Export-Dubhe-Production-Pack.cmd")
Write-Launcher -Path (Join-Path $kitRoot "11-Smoke-Dubhe-This-PC.cmd") -Title "Smoke Dubhe on this PC" -TargetScript (Join-Path $repoRoot "Smoke-Dubhe.cmd")

$template = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot "docs\USER_KIT_README.md")
$readme = $template
$readme = Replace-Token $readme "{{GENERATED_AT}}" (Get-Date).ToString("s")
$readme = Replace-Token $readme "{{REPO_ROOT}}" $repoRoot
$readme = Replace-Token $readme "{{CORE_URL}}" $CoreUrl
$readme = Replace-Token $readme "{{LAN_CORE_URLS}}" $lanText
$readme = Replace-Token $readme "{{WINDOWS_SETUP}}" (Format-DetectedPath $windowsSetup)
$readme = Replace-Token $readme "{{WINDOWS_PORTABLE}}" (Format-DetectedPath $windowsPortable)
$readme = Replace-Token $readme "{{WINDOWS_UNPACKED_EXE}}" (Format-DetectedPath $windowsUnpackedExe)
$readme = Replace-Token $readme "{{ANDROID_APK}}" (Format-DetectedPath $androidApk)
$readme = Replace-Token $readme "{{ANDROID_AAB}}" (Format-DetectedPath $androidAab)
Set-Content -Path (Join-Path $kitRoot "README-FIRST.md") -Encoding UTF8 -Value $readme

$manifest = [pscustomobject]@{
    generated_at = (Get-Date).ToString("s")
    repo_root = $repoRoot
    core_url = $CoreUrl
    kit_root = $kitRoot
    lan_core_urls = $lanUrls
    artifacts = $artifacts
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $kitRoot "manifest.json") -Encoding UTF8

$zipPath = $null
if (-not $NoZip) {
    $zipPath = "$kitRoot.zip"
    if (Test-Path $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }
    Compress-Archive -Path (Join-Path $kitRoot "*") -DestinationPath $zipPath -Force
}

Write-Host "Dubhe user kit created:"
Write-Host $kitRoot
if ($zipPath) {
    Write-Host "Zip:"
    Write-Host $zipPath
}
Write-Host ""
Write-Host "Open README-FIRST.md inside the kit first."

if ($OpenFolder) {
    Start-Process -FilePath "explorer.exe" -ArgumentList @($kitRoot)
}
