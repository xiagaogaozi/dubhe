param(
    [string]$SummaryJsonPath = "",
    [string]$ZipPath = "",
    [switch]$Json,
    [switch]$RequireAllPlatforms,
    [switch]$OpenReport,
    [switch]$OpenFolder
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function New-Check {
    param(
        [string]$Area,
        [string]$Name,
        [ValidateSet("ok", "warn", "fail")]
        [string]$Status,
        [string]$Message
    )

    [pscustomobject]@{
        area = $Area
        name = $Name
        status = $Status
        message = $Message
    }
}

function Add-Check {
    param([pscustomobject]$Check)
    $script:checks.Add($Check) | Out-Null
}

function Normalize-ZipPath {
    param([string]$Path)
    return $Path.Replace("\", "/").TrimStart("/")
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

function Convert-BytesToHex {
    param([byte[]]$Bytes)
    return (($Bytes | ForEach-Object { $_.ToString("X2") }) -join "")
}

function Get-ZipEntryText {
    param([System.IO.Compression.ZipArchiveEntry]$Entry)

    $stream = $Entry.Open()
    try {
        $reader = [System.IO.StreamReader]::new($stream, [System.Text.UTF8Encoding]::new($false), $true)
        try {
            return $reader.ReadToEnd()
        } finally {
            $reader.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
}

function Get-ZipEntryHash {
    param([System.IO.Compression.ZipArchiveEntry]$Entry)

    $stream = $Entry.Open()
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            return Convert-BytesToHex -Bytes ($sha.ComputeHash($stream))
        } finally {
            $sha.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
}

function Get-EntryByName {
    param(
        [hashtable]$EntryByName,
        [string]$Name
    )

    $normalized = Normalize-ZipPath $Name
    if ($EntryByName.ContainsKey($normalized)) {
        return $EntryByName[$normalized]
    }
    return $null
}

function Test-EntryPattern {
    param(
        [string[]]$EntryNames,
        [string]$Pattern
    )

    $normalized = Normalize-ZipPath $Pattern
    foreach ($name in $EntryNames) {
        if ($name -like $normalized) {
            return $true
        }
    }
    return $false
}

function Test-EntryAnyPattern {
    param(
        [string[]]$EntryNames,
        [string[]]$Patterns
    )

    foreach ($pattern in $Patterns) {
        if (Test-EntryPattern -EntryNames $EntryNames -Pattern $pattern) {
            return $true
        }
    }
    return $false
}

function Write-CheckLine {
    param([pscustomobject]$Check)

    $label = switch ($Check.status) {
        "ok" { "[OK]" }
        "warn" { "[提示]" }
        "fail" { "[失败]" }
    }
    Write-Host "$label $($Check.area) / $($Check.name)：$($Check.message)"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$runRoot = Join-Path $repoRoot ".dubhe-run"
if ([string]::IsNullOrWhiteSpace($SummaryJsonPath)) {
    $SummaryJsonPath = Join-Path $runRoot "latest-delivery.json"
}
$reportTextPath = Join-Path $runRoot "delivery-verification.txt"
$reportJsonPath = Join-Path $runRoot "delivery-verification.json"

New-Item -ItemType Directory -Force -Path $runRoot | Out-Null

$checks = [System.Collections.Generic.List[object]]::new()
$summary = $null
$deliveryZipPath = $null
$actualSha256 = $null
$zipSizeBytes = 0
$verifiedChecksumEntries = 0

try {
    if (-not (Test-Path -LiteralPath $SummaryJsonPath)) {
        Add-Check (New-Check "交付摘要" "latest-delivery.json" "fail" "未找到 $SummaryJsonPath；请先双击 Prepare-Dubhe-Delivery.cmd 生成最新交付包。")
    } else {
        Add-Check (New-Check "交付摘要" "latest-delivery.json" "ok" $SummaryJsonPath)
        $summary = Get-Content -Raw -Encoding UTF8 -LiteralPath $SummaryJsonPath | ConvertFrom-Json
        if ([string]::IsNullOrWhiteSpace($ZipPath)) {
            $ZipPath = "$($summary.delivery_zip)"
        }
    }

    if ($summary -and [string]::IsNullOrWhiteSpace($ZipPath)) {
        Add-Check (New-Check "交付摘要" "ZIP 路径" "fail" "latest-delivery.json 中没有 delivery_zip 字段。")
    } elseif (-not [string]::IsNullOrWhiteSpace($ZipPath)) {
        $deliveryZipPath = $ZipPath
        if (Test-Path -LiteralPath $deliveryZipPath) {
            $zipItem = Get-Item -LiteralPath $deliveryZipPath
            $zipSizeBytes = [int64]$zipItem.Length
            Add-Check (New-Check "交付 ZIP" "文件存在" "ok" "$deliveryZipPath ($((Format-ByteSize -Bytes $zipSizeBytes)))")

            $actualSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $deliveryZipPath).Hash
            if ($summary -and $summary.sha256) {
                if ($actualSha256 -eq "$($summary.sha256)") {
                    Add-Check (New-Check "交付 ZIP" "SHA256" "ok" $actualSha256)
                } else {
                    Add-Check (New-Check "交付 ZIP" "SHA256" "fail" "摘要记录为 $($summary.sha256)，实际为 $actualSha256。")
                }
            } else {
                Add-Check (New-Check "交付 ZIP" "SHA256" "warn" "未在摘要中找到 SHA256；实际为 $actualSha256。")
            }

            if ($summary -and $summary.zip_size_bytes) {
                if ([int64]$summary.zip_size_bytes -eq $zipSizeBytes) {
                    Add-Check (New-Check "交付 ZIP" "文件大小" "ok" "$zipSizeBytes bytes")
                } else {
                    Add-Check (New-Check "交付 ZIP" "文件大小" "fail" "摘要记录为 $($summary.zip_size_bytes) bytes，实际为 $zipSizeBytes bytes。")
                }
            }

            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $archive = [System.IO.Compression.ZipFile]::OpenRead($deliveryZipPath)
            try {
                $entryByName = @{}
                $entryNames = @()
                foreach ($entry in $archive.Entries) {
                    $normalized = Normalize-ZipPath $entry.FullName
                    $entryByName[$normalized] = $entry
                    $entryNames += $normalized
                }

                $requiredEntries = @(
                    @{ label = "首次阅读说明"; pattern = "README-FIRST.md" },
                    @{ label = "安装包索引"; pattern = "INSTALL-PACK-INDEX.html" },
                    @{ label = "SHA256 校验清单"; pattern = "CHECKSUMS-SHA256.txt" },
                    @{ label = "用户包 manifest"; pattern = "manifest.json" },
                    @{ label = "交付验证入口"; pattern = "12-Verify-Dubhe-Delivery-This-PC.cmd" },
                    @{ label = "CI 产物导入入口"; pattern = "13-Import-Dubhe-CI-Artifacts-This-PC.cmd" },
                    @{ label = "发行证据包入口"; pattern = "14-Export-Dubhe-Release-Evidence-This-PC.cmd" },
                    @{ label = "Windows setup"; pattern = "01-Windows/Dubhe-*-win-x64-setup.exe" },
                    @{ label = "Windows portable"; pattern = "01-Windows/Dubhe-*-win-x64-portable.exe" },
                    @{ label = "Android debug APK"; pattern = "02-Android/app-debug.apk" },
                    @{ label = "Android release AAB"; pattern = "02-Android/app-release.aab" },
                    @{ label = "安装向导"; pattern = "03-Guides/install-guide.txt" },
                    @{ label = "手机连接卡"; pattern = "03-Guides/mobile-connect.html" },
                    @{ label = "本机体检报告"; pattern = "04-Checks/local-check.txt" },
                    @{ label = "本机验收报告"; pattern = "04-Checks/local-acceptance.txt" },
                    @{ label = "生产门禁报告"; pattern = "04-Checks/production-readiness.txt" }
                )

                foreach ($required in $requiredEntries) {
                    if (Test-EntryPattern -EntryNames $entryNames -Pattern $required.pattern) {
                        Add-Check (New-Check "包内文件" $required.label "ok" $required.pattern)
                    } else {
                        Add-Check (New-Check "包内文件" $required.label "fail" "缺少 $($required.pattern)。")
                    }
                }

                $appleEntries = @(
                    @{
                        label = "macOS DMG 或 ZIP"
                        patterns = @("05-macOS/*.dmg", "05-macOS/*.zip")
                    },
                    @{
                        label = "iOS Runner.app 或 IPA"
                        patterns = @("06-iOS/Runner.app/*", "06-iOS/*.ipa")
                    }
                )
                foreach ($apple in $appleEntries) {
                    $patternText = $apple.patterns -join " 或 "
                    if (Test-EntryAnyPattern -EntryNames $entryNames -Patterns $apple.patterns) {
                        Add-Check (New-Check "四端安装包" $apple.label "ok" $patternText)
                    } elseif ($RequireAllPlatforms) {
                        Add-Check (New-Check "四端安装包" $apple.label "fail" "严格四端验证要求存在 $patternText。")
                    } else {
                        Add-Check (New-Check "四端安装包" $apple.label "warn" "当前 ZIP 未包含 $patternText；内测可继续，四端正式交付请使用 -RequireAllPlatforms。")
                    }
                }

                if (Test-EntryPattern -EntryNames $entryNames -Pattern "01-Windows/win-unpacked/*") {
                    Add-Check (New-Check "包体大小" "排除 win-unpacked" "fail" "ZIP 内包含 01-Windows/win-unpacked；标准交付 ZIP 应只包含 setup/portable。")
                } else {
                    Add-Check (New-Check "包体大小" "排除 win-unpacked" "ok" "未发现 01-Windows/win-unpacked，交付 ZIP 保持轻量。")
                }

                $checksumEntry = Get-EntryByName -EntryByName $entryByName -Name "CHECKSUMS-SHA256.txt"
                if ($checksumEntry) {
                    $checksumText = Get-ZipEntryText -Entry $checksumEntry
                    $checksumLines = @($checksumText -split "(`r`n|`n|`r)")
                    foreach ($line in $checksumLines) {
                        $trimmed = $line.Trim()
                        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#")) {
                            continue
                        }
                        if ($trimmed -notmatch "^([A-Fa-f0-9]{64})\s+(.+)$") {
                            Add-Check (New-Check "校验清单" "格式" "fail" "无法解析：$trimmed")
                            continue
                        }

                        $expectedHash = $Matches[1].ToUpperInvariant()
                        $relativePath = Normalize-ZipPath $Matches[2]
                        $listedEntry = Get-EntryByName -EntryByName $entryByName -Name $relativePath
                        if (-not $listedEntry) {
                            Add-Check (New-Check "校验清单" $relativePath "fail" "清单中列出，但 ZIP 内不存在。")
                            continue
                        }

                        $actualEntryHash = Get-ZipEntryHash -Entry $listedEntry
                        if ($actualEntryHash -ne $expectedHash) {
                            Add-Check (New-Check "校验清单" $relativePath "fail" "期望 $expectedHash，实际 $actualEntryHash。")
                            continue
                        }

                        $verifiedChecksumEntries += 1
                    }

                    if ($verifiedChecksumEntries -gt 0) {
                        Add-Check (New-Check "校验清单" "逐文件 SHA256" "ok" "已验证 $verifiedChecksumEntries 个清单条目。")
                    } else {
                        Add-Check (New-Check "校验清单" "逐文件 SHA256" "fail" "CHECKSUMS-SHA256.txt 没有可验证条目。")
                    }
                } else {
                    Add-Check (New-Check "校验清单" "CHECKSUMS-SHA256.txt" "fail" "ZIP 内缺少 CHECKSUMS-SHA256.txt。")
                }
            } finally {
                $archive.Dispose()
            }
        } else {
            Add-Check (New-Check "交付 ZIP" "文件存在" "fail" "未找到 $deliveryZipPath；请重新运行 Prepare-Dubhe-Delivery.cmd。")
        }
    }
} catch {
    Add-Check (New-Check "验证脚本" "异常" "fail" $_.Exception.Message)
}

$failureCount = @($checks | Where-Object { $_.status -eq "fail" }).Count
$warningCount = @($checks | Where-Object { $_.status -eq "warn" }).Count
$ok = $failureCount -eq 0

$report = [pscustomobject]@{
    generated_at = (Get-Date).ToString("s")
    ok = $ok
    summary_json_path = $SummaryJsonPath
    delivery_zip = $deliveryZipPath
    zip_size_bytes = $zipSizeBytes
    sha256 = $actualSha256
    require_all_platforms = [bool]$RequireAllPlatforms
    verified_checksum_entries = $verifiedChecksumEntries
    failure_count = $failureCount
    warning_count = $warningCount
    checks = $checks
}

$report | ConvertTo-Json -Depth 8 | Set-Content -Path $reportJsonPath -Encoding UTF8

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("Dubhe 交付 ZIP 验证报告") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("生成时间：$($report.generated_at)") | Out-Null
$lines.Add("摘要文件：$SummaryJsonPath") | Out-Null
$lines.Add("ZIP 路径：$deliveryZipPath") | Out-Null
$lines.Add("ZIP 大小：$(Format-ByteSize -Bytes $zipSizeBytes) ($zipSizeBytes bytes)") | Out-Null
$lines.Add("SHA256：$actualSha256") | Out-Null
$lines.Add("严格四端验证：$([bool]$RequireAllPlatforms)") | Out-Null
$lines.Add("逐文件校验条目：$verifiedChecksumEntries") | Out-Null
$lines.Add("") | Out-Null
foreach ($check in $checks) {
    $label = switch ($check.status) {
        "ok" { "[OK]" }
        "warn" { "[提示]" }
        "fail" { "[失败]" }
    }
    $lines.Add("$label $($check.area) / $($check.name)：$($check.message)") | Out-Null
}
$lines.Add("") | Out-Null
if ($ok) {
    $lines.Add("结论：最新交付 ZIP 通过完整性验证，可作为内测/本机体验交付包使用。生产发布仍需通过 Check-Dubhe-Production.cmd。") | Out-Null
} else {
    $lines.Add("结论：最新交付 ZIP 未通过验证，请重新运行 Prepare-Dubhe-Delivery.cmd，或按失败项补齐安装包后再验证。") | Out-Null
}
$lines.Add("JSON 报告：$reportJsonPath") | Out-Null
$lines | Out-File -FilePath $reportTextPath -Encoding UTF8

if ($Json) {
    $report | ConvertTo-Json -Depth 8
} else {
    Write-Host "Dubhe 交付 ZIP 验证"
    Write-Host "摘要文件：$SummaryJsonPath"
    Write-Host ""
    foreach ($check in $checks) {
        Write-CheckLine $check
    }
    Write-Host ""
    if ($ok) {
        Write-Host "结论：最新交付 ZIP 通过完整性验证。"
    } else {
        Write-Host "结论：最新交付 ZIP 未通过验证，请查看 $reportTextPath。"
    }
}

if ($OpenReport) {
    Start-Process -FilePath "notepad.exe" -ArgumentList @($reportTextPath)
}

if ($OpenFolder -and $deliveryZipPath -and (Test-Path -LiteralPath $deliveryZipPath)) {
    Start-Process -FilePath "explorer.exe" -ArgumentList @((Split-Path -Parent $deliveryZipPath))
}

if (-not $ok) {
    exit 1
}
