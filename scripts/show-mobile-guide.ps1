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

function Replace-Token {
    param(
        [string]$Content,
        [string]$Token,
        [string]$Value
    )

    return $Content.Replace($Token, $Value)
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$guideTemplate = Join-Path $repoRoot "docs\MOBILE_QUICK_START.md"
$runRoot = Join-Path $repoRoot ".dubhe-run"
$renderedGuide = Join-Path $runRoot "mobile-quick-start.txt"
$startLanCmd = Join-Path $repoRoot "Start-Dubhe-LAN.cmd"
$connectMobileCmd = Join-Path $repoRoot "Connect-Dubhe-Mobile.cmd"
$checkCmd = Join-Path $repoRoot "Check-Dubhe.cmd"
$apkPath = Join-Path $repoRoot "apps\mobile\build\app\outputs\flutter-apk\app-debug.apk"
$mobileReadme = Join-Path $repoRoot "apps\mobile\README.md"
$mobileConnectHtml = Join-Path $runRoot "mobile-connect.html"
$mobileConnectText = Join-Path $runRoot "mobile-connect.txt"
$mobileConnectQr = Join-Path $runRoot "mobile-core-url.svg"
$lanCoreUrls = @(Get-LanCoreUrls -Port 8000)

if (-not (Test-Path $guideTemplate)) {
    throw "Missing guide template: $guideTemplate"
}

$lanText = if ($lanCoreUrls.Count -gt 0) {
    $lanCoreUrls -join " / "
} else {
    "(no LAN IPv4 address detected)"
}
$apkText = if (Test-Path $apkPath) {
    $apkPath
} else {
    "$apkPath (not built yet)"
}

$content = Get-Content -Raw -Encoding UTF8 $guideTemplate
$content = Replace-Token $content "{{LAN_CORE_URLS}}" $lanText
$content = Replace-Token $content "{{ANDROID_APK_PATH}}" $apkText
$content = Replace-Token $content "{{START_LAN_CMD}}" $startLanCmd
$content = Replace-Token $content "{{CONNECT_MOBILE_CMD}}" $connectMobileCmd
$content = Replace-Token $content "{{CHECK_CMD}}" $checkCmd
$content = Replace-Token $content "{{MOBILE_README}}" $mobileReadme
$content = Replace-Token $content "{{MOBILE_CONNECT_HTML}}" $mobileConnectHtml
$content = Replace-Token $content "{{MOBILE_CONNECT_TEXT}}" $mobileConnectText
$content = Replace-Token $content "{{MOBILE_CONNECT_QR}}" $mobileConnectQr

New-Item -ItemType Directory -Force -Path $runRoot | Out-Null
Set-Content -Path $renderedGuide -Encoding UTF8 -Value $content

Write-Host $content
Write-Host ""
Write-Host "Rendered guide: $renderedGuide"

if ($OpenNotepad) {
    Start-Process -FilePath "notepad.exe" -ArgumentList @($renderedGuide)
}
