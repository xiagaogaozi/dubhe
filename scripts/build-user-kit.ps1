param(
    [string]$CoreUrl = "http://127.0.0.1:8000",
    [string]$OutputRoot = "",
    [switch]$NoZip,
    [switch]$IncludeUnpackedInZip,
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

function ConvertTo-HtmlText {
    param([string]$Value)
    return [System.Net.WebUtility]::HtmlEncode($Value)
}

function Format-ByteSize {
    param([int64]$Bytes)

    if ($Bytes -ge 1GB) {
        return "{0:N2} GB" -f ($Bytes / 1GB)
    }
    if ($Bytes -ge 1MB) {
        return "{0:N2} MB" -f ($Bytes / 1MB)
    }
    if ($Bytes -ge 1KB) {
        return "{0:N2} KB" -f ($Bytes / 1KB)
    }
    return "$Bytes B"
}

function Resolve-KitRelativePath {
    param(
        [string]$Root,
        [string]$Path
    )

    if (-not $Path) {
        return ""
    }
    $rootFull = (Resolve-Path -LiteralPath $Root).Path.TrimEnd("\")
    $pathFull = (Resolve-Path -LiteralPath $Path).Path
    if ($pathFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $pathFull.Substring($rootFull.Length).TrimStart("\")
    }
    return $pathFull
}

function Write-ChecksumFile {
    param(
        [string]$Root,
        [string]$Path
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("# Dubhe user kit SHA256 checksums") | Out-Null
    $lines.Add("# Generated: $((Get-Date).ToString("s"))") | Out-Null
    $lines.Add("# Format: SHA256  relative-path") | Out-Null
    $lines.Add("# The Windows unpacked directory is intentionally not expanded here; use the setup or portable EXE for distribution checks.") | Out-Null
    $lines.Add("") | Out-Null

    $checksumLeaf = Split-Path -Leaf $Path
    $files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    foreach ($file in @(Get-ChildItem -LiteralPath $Root -File -ErrorAction SilentlyContinue)) {
        if ($file.Name -ne $checksumLeaf) {
            $files.Add($file) | Out-Null
        }
    }

    $windowsDir = Join-Path $Root "01-Windows"
    if (Test-Path $windowsDir) {
        foreach ($file in @(Get-ChildItem -LiteralPath $windowsDir -File -ErrorAction SilentlyContinue)) {
            $files.Add($file) | Out-Null
        }
    }

    foreach ($directoryName in @("02-Android", "03-Guides", "04-Checks", "05-macOS", "06-iOS")) {
        $directory = Join-Path $Root $directoryName
        if (-not (Test-Path $directory)) {
            continue
        }
        foreach ($file in @(Get-ChildItem -LiteralPath $directory -Recurse -File -ErrorAction SilentlyContinue)) {
            $files.Add($file) | Out-Null
        }
    }

    foreach ($file in $files) {
        $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName
        $relative = Resolve-KitRelativePath -Root $Root -Path $file.FullName
        $lines.Add("$($hash.Hash)  $relative") | Out-Null
    }

    Set-Content -Path $Path -Encoding UTF8 -Value $lines
}

function Write-MissingArtifactNote {
    param(
        [string]$Path,
        [string]$Title,
        [string[]]$Lines
    )

    $content = [System.Collections.Generic.List[string]]::new()
    $content.Add($Title) | Out-Null
    $content.Add("") | Out-Null
    foreach ($line in $Lines) {
        $content.Add($line) | Out-Null
    }
    Set-Content -Path $Path -Encoding UTF8 -Value $content
}

function Write-InstallPackIndex {
    param(
        [string]$Path,
        [string]$KitRoot,
        [object[]]$Artifacts,
        [string]$CoreUrl,
        [string]$LanText
    )

    $rows = foreach ($artifact in $Artifacts) {
        $status = if ($artifact.available) { "可用" } else { "未生成" }
        $statusClass = if ($artifact.available) { "ok" } else { "warn" }
        $copiedTo = if ($artifact.copied_to) {
            Resolve-KitRelativePath -Root $KitRoot -Path $artifact.copied_to
        } else {
            "未复制"
        }
        $hash = if ($artifact.sha256) { $artifact.sha256 } elseif ($artifact.available) { "见 CHECKSUMS-SHA256.txt" } else { "" }
        $size = if ($artifact.available) { Format-ByteSize -Bytes $artifact.size_bytes } else { "" }
        $fileCount = if ($artifact.PSObject.Properties.Name -contains "file_count") {
            "$($artifact.file_count)"
        } else {
            ""
        }
        @"
      <tr>
        <td>$(ConvertTo-HtmlText $artifact.label)</td>
        <td class="$statusClass">$(ConvertTo-HtmlText $status)</td>
        <td><code>$(ConvertTo-HtmlText $copiedTo)</code></td>
        <td>$(ConvertTo-HtmlText $size)</td>
        <td>$(ConvertTo-HtmlText $fileCount)</td>
        <td><code>$(ConvertTo-HtmlText $hash)</code></td>
      </tr>
"@
    }

    $html = @"
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <title>Dubhe 安装包索引</title>
  <style>
    body { font-family: "Microsoft YaHei", "Segoe UI", sans-serif; margin: 28px; color: #1f2937; background: #f8fafc; }
    main { max-width: 1100px; margin: 0 auto; background: #fff; border: 1px solid #dbe3ef; border-radius: 8px; padding: 24px; }
    h1 { margin: 0 0 8px; font-size: 28px; }
    h2 { margin-top: 28px; font-size: 20px; }
    table { width: 100%; border-collapse: collapse; margin-top: 12px; }
    th, td { border: 1px solid #e5e7eb; padding: 10px; text-align: left; vertical-align: top; }
    th { background: #eef2f7; }
    code { word-break: break-all; }
    .ok { color: #047857; font-weight: 700; }
    .warn { color: #b45309; font-weight: 700; }
    .note { border-left: 4px solid #2563eb; padding-left: 12px; }
    .danger { border-left: 4px solid #b45309; padding-left: 12px; color: #92400e; }
  </style>
</head>
<body>
  <main>
    <h1>Dubhe 安装包索引</h1>
    <p>生成时间：$(ConvertTo-HtmlText ((Get-Date).ToString("s")))</p>
    <p class="note">先打开 <code>README-FIRST.md</code>。本页用于快速确认 Windows / macOS / iOS / Android 安装产物、校验哈希和仍缺失的发布条件。</p>

    <h2>安装产物</h2>
    <table>
      <thead>
        <tr>
          <th>项目</th>
          <th>状态</th>
          <th>包内路径</th>
          <th>大小</th>
          <th>文件数</th>
          <th>SHA256</th>
        </tr>
      </thead>
      <tbody>
$($rows -join "`n")
      </tbody>
    </table>

    <h2>推荐顺序</h2>
    <ol>
      <li>Windows 用户优先使用 <code>01-Windows</code> 里的 setup 安装包；portable 适合免安装测试。</li>
      <li>Android 用户使用 <code>02-Android</code> 里的 debug APK 内测；AAB 用于后续商店发布链路。</li>
      <li>手机连接前打开 <code>03-Guides/mobile-connect.html</code>，或双击包根目录里的连接脚本。</li>
      <li>需要确认安装文件或说明文件没有损坏时，打开 <code>CHECKSUMS-SHA256.txt</code> 对照校验；最终四端交付前运行 <code>verify-delivery-pack.ps1 -RequireAllPlatforms</code>。</li>
    </ol>

    <h2>Core 地址</h2>
    <p>本机 Core：<code>$(ConvertTo-HtmlText $CoreUrl)</code></p>
    <p>局域网候选：<code>$(ConvertTo-HtmlText $LanText)</code></p>

    <p class="danger">当前包仍是内测/本机体验交付物。生产发布前还需要签名、macOS/iOS 构建、云同步、授权数据源、生产身份、不可篡改审计和真实券商 UAT。</p>
  </main>
</body>
</html>
"@

    Set-Content -Path $Path -Encoding UTF8 -Value $html
}

function Remove-SafeDirectory {
    param(
        [string]$Path,
        [string]$AllowedRoot
    )

    if (-not (Test-Path $Path)) {
        return
    }

    $allowedFull = [System.IO.Path]::GetFullPath($AllowedRoot).TrimEnd("\")
    $targetFull = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).Path).TrimEnd("\")
    if (-not $targetFull.StartsWith($allowedFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove directory outside output root: $targetFull"
    }
    Remove-Item -LiteralPath $targetFull -Recurse -Force
}

function Copy-ZipPayload {
    param(
        [string]$SourceRoot,
        [string]$StageRoot,
        [switch]$IncludeUnpacked
    )

    New-Item -ItemType Directory -Force -Path $StageRoot | Out-Null

    foreach ($item in @(Get-ChildItem -LiteralPath $SourceRoot -Force)) {
        if ($item.Name -eq "01-Windows" -and $item.PSIsContainer) {
            $stageWindows = Join-Path $StageRoot "01-Windows"
            New-Item -ItemType Directory -Force -Path $stageWindows | Out-Null
            foreach ($windowsItem in @(Get-ChildItem -LiteralPath $item.FullName -Force)) {
                if (-not $IncludeUnpacked -and $windowsItem.Name -eq "win-unpacked") {
                    continue
                }
                Copy-Item -LiteralPath $windowsItem.FullName -Destination $stageWindows -Recurse -Force
            }
            continue
        }

        Copy-Item -LiteralPath $item.FullName -Destination $StageRoot -Recurse -Force
    }
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
$macosDir = Join-Path $kitRoot "05-macOS"
$iosDir = Join-Path $kitRoot "06-iOS"

$theiaDist = Join-Path $repoRoot "apps\theia-desktop\app\dist"
$mobileRoot = Join-Path $repoRoot "apps\mobile"
$windowsSetup = Resolve-NewestFile $theiaDist "Dubhe-*-win-x64-setup.exe"
$windowsPortable = Resolve-NewestFile $theiaDist "Dubhe-*-win-x64-portable.exe"
$windowsUnpackedDir = Join-Path $theiaDist "win-unpacked"
$windowsUnpackedExe = Join-Path $windowsUnpackedDir "Dubhe.exe"
$windowsUnpacked = if (Test-Path $windowsUnpackedExe) { $windowsUnpackedDir } else { $null }
$macosDmg = Resolve-NewestFile $theiaDist "Dubhe-*-mac-*.dmg"
$macosZip = Resolve-NewestFile $theiaDist "Dubhe-*-mac-*.zip"
$androidApk = Join-Path $mobileRoot "build\app\outputs\flutter-apk\app-debug.apk"
$androidAab = Join-Path $mobileRoot "build\app\outputs\bundle\release\app-release.aab"
$iosApp = Join-Path $mobileRoot "build\ios\iphoneos\Runner.app"
$iosIpa = Resolve-NewestFile (Join-Path $mobileRoot "build\ios\ipa") "*.ipa"
$lanUrls = @(Get-LanCoreUrls -Port ([System.Uri]$CoreUrl).Port)
$lanText = if ($lanUrls.Count -gt 0) { $lanUrls -join " / " } else { "(no LAN IPv4 address detected)" }

New-Item -ItemType Directory -Force -Path $windowsDir, $androidDir, $guidesDir, $checksDir, $macosDir, $iosDir | Out-Null

$artifacts = @(
    Copy-Artifact -Path $windowsSetup -DestinationDirectory $windowsDir -Label "Windows setup"
    Copy-Artifact -Path $windowsPortable -DestinationDirectory $windowsDir -Label "Windows portable"
    Copy-DirectoryArtifact -Path $windowsUnpacked -DestinationDirectory $windowsDir -Label "Windows unpacked desktop"
    Copy-Artifact -Path $androidApk -DestinationDirectory $androidDir -Label "Android debug APK"
    Copy-Artifact -Path $androidAab -DestinationDirectory $androidDir -Label "Android release AAB"
    Copy-Artifact -Path $macosDmg -DestinationDirectory $macosDir -Label "macOS DMG"
    Copy-Artifact -Path $macosZip -DestinationDirectory $macosDir -Label "macOS ZIP"
    Copy-DirectoryArtifact -Path $iosApp -DestinationDirectory $iosDir -Label "iOS no-codesign app bundle"
    Copy-Artifact -Path $iosIpa -DestinationDirectory $iosDir -Label "iOS IPA"
)

if (-not $macosDmg -and -not $macosZip) {
    Write-MissingArtifactNote `
        -Path (Join-Path $macosDir "README-missing-macos.txt") `
        -Title "macOS 安装包尚未放入本交付包" `
        -Lines @(
            "当前 Windows 本机不能生成 macOS dmg/zip。",
            "请在 macOS runner 或真实 Mac 上运行 docs/ci/theia-desktop.yml 对应流程。",
            "下载 GitHub Actions 产物后，把 .dmg 或 .zip 放入 apps/theia-desktop/app/dist，再重新运行 Prepare-Dubhe-Delivery.cmd。",
            "最终四端交付前必须运行 scripts\verify-delivery-pack.ps1 -RequireAllPlatforms。"
        )
}

if (-not (Test-Path $iosApp) -and -not $iosIpa) {
    Write-MissingArtifactNote `
        -Path (Join-Path $iosDir "README-missing-ios.txt") `
        -Title "iOS 安装包尚未放入本交付包" `
        -Lines @(
            "当前 Windows 本机不能生成 iOS Runner.app 或 IPA。",
            "请在 macOS + Xcode 环境运行 docs/ci/mobile.yml 对应流程。",
            "下载 GitHub Actions 产物后，把 Runner.app 放入 apps/mobile/build/ios/iphoneos，或把 .ipa 放入 apps/mobile/build/ios/ipa，再重新运行 Prepare-Dubhe-Delivery.cmd。",
            "最终四端交付前必须运行 scripts\verify-delivery-pack.ps1 -RequireAllPlatforms。"
        )
}

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
Write-Launcher -Path (Join-Path $kitRoot "12-Verify-Dubhe-Delivery-This-PC.cmd") -Title "Verify latest Dubhe delivery ZIP on this PC" -TargetScript (Join-Path $repoRoot "Verify-Dubhe-Delivery.cmd")
Write-Launcher -Path (Join-Path $kitRoot "13-Import-Dubhe-CI-Artifacts-This-PC.cmd") -Title "Import Dubhe CI artifacts on this PC" -TargetScript (Join-Path $repoRoot "Import-Dubhe-CI-Artifacts.cmd")
Write-Launcher -Path (Join-Path $kitRoot "14-Export-Dubhe-Release-Evidence-This-PC.cmd") -Title "Export Dubhe release evidence on this PC" -TargetScript (Join-Path $repoRoot "Export-Dubhe-Release-Evidence.cmd")

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
$readme = Replace-Token $readme "{{MACOS_DMG}}" (Format-DetectedPath $macosDmg)
$readme = Replace-Token $readme "{{MACOS_ZIP}}" (Format-DetectedPath $macosZip)
$readme = Replace-Token $readme "{{IOS_APP}}" (Format-DetectedPath $iosApp)
$readme = Replace-Token $readme "{{IOS_IPA}}" (Format-DetectedPath $iosIpa)
Set-Content -Path (Join-Path $kitRoot "README-FIRST.md") -Encoding UTF8 -Value $readme

$installIndexPath = Join-Path $kitRoot "INSTALL-PACK-INDEX.html"
Write-InstallPackIndex `
    -Path $installIndexPath `
    -KitRoot $kitRoot `
    -Artifacts $artifacts `
    -CoreUrl $CoreUrl `
    -LanText $lanText

$manifest = [pscustomobject]@{
    generated_at = (Get-Date).ToString("s")
    repo_root = $repoRoot
    core_url = $CoreUrl
    kit_root = $kitRoot
    lan_core_urls = $lanUrls
    install_index = $installIndexPath
    checksums = Join-Path $kitRoot "CHECKSUMS-SHA256.txt"
    zip_excludes_windows_unpacked = -not [bool]$IncludeUnpackedInZip
    artifacts = $artifacts
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $kitRoot "manifest.json") -Encoding UTF8

Write-ChecksumFile -Root $kitRoot -Path (Join-Path $kitRoot "CHECKSUMS-SHA256.txt")

$zipPath = $null
if (-not $NoZip) {
    $zipPath = "$kitRoot.zip"
    if (Test-Path $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }
    $zipStage = Join-Path $OutputRoot "Dubhe-User-Kit-$timestamp-zip-payload"
    Remove-SafeDirectory -Path $zipStage -AllowedRoot $OutputRoot
    Copy-ZipPayload -SourceRoot $kitRoot -StageRoot $zipStage -IncludeUnpacked:$IncludeUnpackedInZip
    try {
        Compress-Archive -Path (Join-Path $zipStage "*") -DestinationPath $zipPath -Force
    } finally {
        Remove-SafeDirectory -Path $zipStage -AllowedRoot $OutputRoot
    }
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
