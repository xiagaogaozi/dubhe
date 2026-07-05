param(
    [switch]$OpenNotepad
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

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

function Format-DetectedPath {
    param(
        [string]$Path,
        [string]$FallbackPath
    )

    if ($Path -and (Test-Path $Path)) {
        return $Path
    }
    if ($FallbackPath) {
        return "$FallbackPath ($script:missingPackageText)"
    }
    return "($script:missingPackageText)"
}

function Replace-Token {
    param(
        [string]$Content,
        [string]$Token,
        [string]$Value
    )

    return $Content.Replace($Token, $Value)
}

function New-TextFromCodePoints {
    param([int[]]$CodePoints)

    return -join ($CodePoints | ForEach-Object { [char]$_ })
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$guideTemplate = Join-Path $repoRoot "docs\INSTALL_GUIDE.md"
$runRoot = Join-Path $repoRoot ".dubhe-run"
$renderedGuide = Join-Path $runRoot "install-guide.txt"
$theiaDist = Join-Path $repoRoot "apps\theia-desktop\app\dist"
$mobileRoot = Join-Path $repoRoot "apps\mobile"

$windowsSetup = Resolve-NewestFile $theiaDist "Dubhe-*-win-x64-setup.exe"
$windowsPortable = Resolve-NewestFile $theiaDist "Dubhe-*-win-x64-portable.exe"
$windowsUnpacked = Join-Path $theiaDist "win-unpacked\Dubhe.exe"
$androidApk = Join-Path $mobileRoot "build\app\outputs\flutter-apk\app-debug.apk"
$androidAab = Join-Path $mobileRoot "build\app\outputs\bundle\release\app-release.aab"
$macosDmg = Resolve-NewestFile $theiaDist "Dubhe-*-mac-*.dmg"
$macosZip = Resolve-NewestFile $theiaDist "Dubhe-*-mac-*.zip"
$iosApp = Join-Path $mobileRoot "build\ios\iphoneos\Runner.app"
$lanCoreUrls = @(Get-LanCoreUrls -Port 8000)
$missingPackageText = New-TextFromCodePoints @(0x5C1A, 0x672A, 0x751F, 0x6210)

if (-not (Test-Path $guideTemplate)) {
    throw "Missing guide template: $guideTemplate"
}

$lanText = if ($lanCoreUrls.Count -gt 0) {
    $lanCoreUrls -join " / "
} else {
    "(no LAN IPv4 address detected)"
}

$macosPackage = if ($macosDmg) { $macosDmg } elseif ($macosZip) { $macosZip } else { $null }

$tokens = @{
    "{{WINDOWS_SETUP_PATH}}" = Format-DetectedPath $windowsSetup (Join-Path $theiaDist "Dubhe-*-win-x64-setup.exe")
    "{{WINDOWS_PORTABLE_PATH}}" = Format-DetectedPath $windowsPortable (Join-Path $theiaDist "Dubhe-*-win-x64-portable.exe")
    "{{WINDOWS_UNPACKED_EXE_PATH}}" = Format-DetectedPath $windowsUnpacked $windowsUnpacked
    "{{ANDROID_APK_PATH}}" = Format-DetectedPath $androidApk $androidApk
    "{{ANDROID_AAB_PATH}}" = Format-DetectedPath $androidAab $androidAab
    "{{MACOS_PACKAGE_PATH}}" = Format-DetectedPath $macosPackage "$theiaDist\Dubhe-*-mac-*.dmg or $theiaDist\Dubhe-*-mac-*.zip"
    "{{IOS_APP_PATH}}" = Format-DetectedPath $iosApp $iosApp
    "{{LAN_CORE_URLS}}" = $lanText
    "{{START_CMD}}" = Join-Path $repoRoot "Start-Dubhe.cmd"
    "{{START_LAN_CMD}}" = Join-Path $repoRoot "Start-Dubhe-LAN.cmd"
    "{{MOBILE_GUIDE_CMD}}" = Join-Path $repoRoot "Open-Dubhe-Mobile-Guide.cmd"
    "{{CHECK_CMD}}" = Join-Path $repoRoot "Check-Dubhe.cmd"
    "{{SMOKE_CMD}}" = Join-Path $repoRoot "Smoke-Dubhe.cmd"
    "{{CONFIGURE_CMD}}" = Join-Path $repoRoot "Configure-Dubhe.cmd"
    "{{CI_THEIA_TEMPLATE}}" = Join-Path $repoRoot "docs\ci\theia-desktop.yml"
    "{{CI_MOBILE_TEMPLATE}}" = Join-Path $repoRoot "docs\ci\mobile.yml"
}

$content = Get-Content -Raw -Encoding UTF8 $guideTemplate
foreach ($token in $tokens.GetEnumerator()) {
    $content = Replace-Token $content $token.Key $token.Value
}

New-Item -ItemType Directory -Force -Path $runRoot | Out-Null
Set-Content -Path $renderedGuide -Encoding UTF8 -Value $content

Write-Host $content
Write-Host ""
Write-Host "Rendered guide: $renderedGuide"

if ($OpenNotepad) {
    Start-Process -FilePath "notepad.exe" -ArgumentList @($renderedGuide)
}
