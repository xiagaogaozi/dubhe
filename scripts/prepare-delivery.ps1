param(
    [string]$CoreUrl = "http://127.0.0.1:8000",
    [string]$OutputRoot = "",
    [switch]$OpenFolder
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

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

function Test-ZipEntry {
    param(
        [string]$ZipPath,
        [string]$EntryName
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        foreach ($entry in $archive.Entries) {
            $normalized = $entry.FullName.Replace("\", "/")
            if ($normalized -eq $EntryName) {
                return $true
            }
        }
        return $false
    } finally {
        $archive.Dispose()
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$runRoot = Join-Path $repoRoot ".dubhe-run"
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $runRoot "delivery"
}

$buildScript = Join-Path $repoRoot "scripts\build-user-kit.ps1"
if (-not (Test-Path $buildScript)) {
    throw "Missing build script: $buildScript"
}

New-Item -ItemType Directory -Force -Path $runRoot, $OutputRoot | Out-Null

$startedAt = Get-Date
$buildLog = Join-Path $runRoot "delivery-build.log"
Write-Host "Building Dubhe delivery pack..."
Write-Host "Output root: $OutputRoot"
Write-Host "Core URL: $CoreUrl"

$output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $buildScript -CoreUrl $CoreUrl -OutputRoot $OutputRoot 2>&1
$exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
$output | Out-File -FilePath $buildLog -Encoding UTF8
if ($exitCode -ne 0) {
    throw "User kit build failed with exit code $exitCode. See $buildLog"
}

$zip = @(
    Get-ChildItem -LiteralPath $OutputRoot -Filter "Dubhe-User-Kit-*.zip" -File |
        Where-Object { $_.Length -gt 0 -and $_.LastWriteTime -ge $startedAt.AddMinutes(-5) } |
        Sort-Object LastWriteTime -Descending
) | Select-Object -First 1
if (-not $zip) {
    $zip = @(
        Get-ChildItem -LiteralPath $OutputRoot -Filter "Dubhe-User-Kit-*.zip" -File |
            Where-Object { $_.Length -gt 0 } |
            Sort-Object LastWriteTime -Descending
    ) | Select-Object -First 1
}
if (-not $zip) {
    throw "No non-empty Dubhe user kit ZIP found in $OutputRoot"
}

$kitDirectory = Join-Path $OutputRoot ([System.IO.Path]::GetFileNameWithoutExtension($zip.Name))
$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $zip.FullName
$hasInstallIndex = Test-ZipEntry -ZipPath $zip.FullName -EntryName "INSTALL-PACK-INDEX.html"
$hasChecksums = Test-ZipEntry -ZipPath $zip.FullName -EntryName "CHECKSUMS-SHA256.txt"
$hasReadme = Test-ZipEntry -ZipPath $zip.FullName -EntryName "README-FIRST.md"

$summary = [pscustomobject]@{
    generated_at = (Get-Date).ToString("s")
    repo_root = $repoRoot
    core_url = $CoreUrl
    delivery_zip = $zip.FullName
    delivery_directory = $kitDirectory
    zip_size_bytes = $zip.Length
    zip_size_zh = Format-ByteSize -Bytes $zip.Length
    sha256 = $hash.Hash
    has_readme_first = $hasReadme
    has_install_pack_index = $hasInstallIndex
    has_checksums = $hasChecksums
    build_log = $buildLog
    production_ready = $false
    production_note_zh = "当前交付包适合内测/本机体验；生产发布仍需通过 Check-Dubhe-Production.cmd。"
}

$summaryJsonPath = Join-Path $runRoot "latest-delivery.json"
$summaryTextPath = Join-Path $runRoot "LATEST-DUBHE-DELIVERY.txt"
$summary | ConvertTo-Json -Depth 5 | Set-Content -Path $summaryJsonPath -Encoding UTF8

$lines = @(
    "Dubhe 最新交付包",
    "",
    "生成时间：$($summary.generated_at)",
    "ZIP 路径：$($summary.delivery_zip)",
    "目录路径：$($summary.delivery_directory)",
    "ZIP 大小：$($summary.zip_size_zh) ($($summary.zip_size_bytes) bytes)",
    "SHA256：$($summary.sha256)",
    "",
    "包内关键文件：",
    "- README-FIRST.md：$($summary.has_readme_first)",
    "- INSTALL-PACK-INDEX.html：$($summary.has_install_pack_index)",
    "- CHECKSUMS-SHA256.txt：$($summary.has_checksums)",
    "",
    "使用顺序：",
    "1. 解压 ZIP。",
    "2. 打开 README-FIRST.md。",
    "3. Windows 用户优先安装 01-Windows 里的 setup 或 portable。",
    "4. Android 用户安装 02-Android 里的 APK；AAB 用于后续商店发布链路。",
    "5. 需要手机连接时，按 03-Guides/mobile-connect.html 的 Core 地址连接。",
    "",
    "重要说明：$($summary.production_note_zh)",
    "构建日志：$buildLog",
    "JSON 摘要：$summaryJsonPath"
)
$lines | Out-File -FilePath $summaryTextPath -Encoding UTF8
Copy-Item -LiteralPath $summaryTextPath -Destination (Join-Path $OutputRoot "LATEST-DUBHE-DELIVERY.txt") -Force
Copy-Item -LiteralPath $summaryJsonPath -Destination (Join-Path $OutputRoot "latest-delivery.json") -Force

Write-Host ""
Write-Host "Dubhe delivery pack ready:"
Write-Host $zip.FullName
Write-Host "SHA256:"
Write-Host $hash.Hash
Write-Host "Summary:"
Write-Host $summaryTextPath

if ($OpenFolder) {
    Start-Process -FilePath "explorer.exe" -ArgumentList @($OutputRoot)
}
