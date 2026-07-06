param(
    [string]$CoreUrl = "http://127.0.0.1:8000",
    [string]$OutputDir = "",
    [switch]$StartCore,
    [switch]$OpenFolder
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Invoke-ChildPowerShell {
    param(
        [string]$ScriptPath,
        [string[]]$Arguments = @()
    )

    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        return [pscustomobject]@{
            exit_code = 1
            output = @("Missing script: $ScriptPath")
        }
    }

    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments 2>&1
    $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    return [pscustomobject]@{
        exit_code = $exitCode
        output = @($output | ForEach-Object { "$_" })
    }
}

function ConvertFrom-OutputJson {
    param([object[]]$Output)

    $text = (@($Output) | ForEach-Object { "$_" }) -join "`n"
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    try {
        return $text.Trim() | ConvertFrom-Json
    } catch {
        return $null
    }
}

function ConvertTo-MarkdownText {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }
    return $Value.Replace("|", "\|").Replace("`r", " ").Replace("`n", " ")
}

function ConvertTo-HtmlText {
    param([string]$Value)

    if ($null -eq $Value) {
        return ""
    }

    return "$Value".
        Replace("&", "&amp;").
        Replace("<", "&lt;").
        Replace(">", "&gt;").
        Replace('"', "&quot;").
        Replace("`r`n", "<br>").
        Replace("`n", "<br>").
        Replace("`r", "<br>")
}

function Format-ByteSize {
    param([int64]$Bytes)

    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Format-CheckStatusZh {
    param([string]$Status)

    switch ($Status) {
        "ok" { "通过" }
        "warn" { "提示" }
        "fail" { "失败" }
        default { if ($Status) { $Status } else { "未知" } }
    }
}

function Format-ProductionStatusZh {
    param([string]$Status)

    switch ($Status) {
        "pass" { "通过" }
        "warn" { "需确认" }
        "fail" { "未完成" }
        default { if ($Status) { $Status } else { "未知" } }
    }
}

function Select-DeliveryChecks {
    param(
        [pscustomobject]$Report,
        [string[]]$Statuses
    )

    if (-not $Report -or -not ($Report.PSObject.Properties.Name -contains "checks")) {
        return @()
    }
    return @($Report.checks | Where-Object { $Statuses -contains $_.status })
}

function Select-ProductionItems {
    param(
        [pscustomobject]$Report,
        [string[]]$Statuses
    )

    if (-not $Report -or -not ($Report.PSObject.Properties.Name -contains "items")) {
        return @()
    }
    return @($Report.items | Where-Object { $Statuses -contains $_.status })
}

function Add-MarkdownDeliveryChecks {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$Title,
        [object[]]$Checks
    )

    $Lines.Add("### $Title") | Out-Null
    $Lines.Add("") | Out-Null
    if ($Checks.Count -eq 0) {
        $Lines.Add("- 无。") | Out-Null
        $Lines.Add("") | Out-Null
        return
    }
    foreach ($check in $Checks) {
        $Lines.Add("- $(Format-CheckStatusZh $check.status) / $($check.area) / $($check.name)：$($check.message)") | Out-Null
    }
    $Lines.Add("") | Out-Null
}

function Add-HtmlDeliveryRows {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [object[]]$Checks
    )

    if ($Checks.Count -eq 0) {
        $Lines.Add("<tr><td colspan=""4"">无</td></tr>") | Out-Null
        return
    }
    foreach ($check in $Checks) {
        $statusClass = if ($check.status -eq "fail") { "fail" } elseif ($check.status -eq "warn") { "warn" } else { "ok" }
        $Lines.Add("<tr><td><span class=""badge $statusClass"">$(ConvertTo-HtmlText (Format-CheckStatusZh $check.status))</span></td><td>$(ConvertTo-HtmlText $check.area)</td><td>$(ConvertTo-HtmlText $check.name)</td><td>$(ConvertTo-HtmlText $check.message)</td></tr>") | Out-Null
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$runRoot = Join-Path $repoRoot ".dubhe-run"
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $runRoot "release-evidence"
}

$startScript = Join-Path $repoRoot "scripts\start-local-dubhe.ps1"
$verifyScript = Join-Path $repoRoot "scripts\verify-delivery-pack.ps1"
$productionScript = Join-Path $repoRoot "scripts\check-production-readiness.ps1"
$localCheckScript = Join-Path $repoRoot "scripts\check-local-dubhe.ps1"
$summaryJsonPath = Join-Path $runRoot "latest-delivery.json"

New-Item -ItemType Directory -Force -Path $runRoot, $OutputDir | Out-Null

$startResult = $null
if ($StartCore) {
    $startResult = Invoke-ChildPowerShell -ScriptPath $startScript -Arguments @("-SkipDesktop")
}

$strictVerifyResult = Invoke-ChildPowerShell -ScriptPath $verifyScript -Arguments @("-RequireAllPlatforms", "-Json")
$strictVerifyReport = ConvertFrom-OutputJson -Output $strictVerifyResult.output

$defaultVerifyResult = Invoke-ChildPowerShell -ScriptPath $verifyScript -Arguments @("-Json")
$defaultVerifyReport = ConvertFrom-OutputJson -Output $defaultVerifyResult.output

$productionResult = Invoke-ChildPowerShell -ScriptPath $productionScript -Arguments @("-CoreUrl", $CoreUrl, "-Json")
$productionReport = ConvertFrom-OutputJson -Output $productionResult.output

$localCheckResult = Invoke-ChildPowerShell -ScriptPath $localCheckScript
$localCheckText = ($localCheckResult.output -join "`r`n")

$deliverySummary = $null
if (Test-Path -LiteralPath $summaryJsonPath) {
    $deliverySummary = Get-Content -Raw -Encoding UTF8 -LiteralPath $summaryJsonPath | ConvertFrom-Json
    Copy-Item -LiteralPath $summaryJsonPath -Destination (Join-Path $OutputDir "delivery-summary.json") -Force
}

$defaultEvidence = [pscustomobject]@{
    exit_code = $defaultVerifyResult.exit_code
    report = $defaultVerifyReport
    raw_output = $defaultVerifyResult.output
}
$strictEvidence = [pscustomobject]@{
    exit_code = $strictVerifyResult.exit_code
    report = $strictVerifyReport
    raw_output = $strictVerifyResult.output
}
$productionEvidence = [pscustomobject]@{
    exit_code = $productionResult.exit_code
    report = $productionReport
    raw_output = $productionResult.output
}
$localEvidence = [pscustomobject]@{
    exit_code = $localCheckResult.exit_code
    output_path = "local-check.txt"
}

$defaultEvidence | ConvertTo-Json -Depth 12 | Set-Content -Path (Join-Path $OutputDir "delivery-verification-default.json") -Encoding UTF8
$strictEvidence | ConvertTo-Json -Depth 12 | Set-Content -Path (Join-Path $OutputDir "delivery-verification-strict-four-platform.json") -Encoding UTF8
$productionEvidence | ConvertTo-Json -Depth 12 | Set-Content -Path (Join-Path $OutputDir "production-readiness.json") -Encoding UTF8
$localCheckText | Out-File -FilePath (Join-Path $OutputDir "local-check.txt") -Encoding UTF8

$defaultOk = ($defaultVerifyReport -and [bool]$defaultVerifyReport.ok)
$strictOk = ($strictVerifyReport -and [bool]$strictVerifyReport.ok)
$productionReady = ($productionReport -and [bool]$productionReport.production_ready)
$localOk = ($localCheckResult.exit_code -eq 0)

$deliveryStatus = if ($defaultOk) { "通过" } elseif ($defaultVerifyReport) { "失败" } else { "未知" }
$fourPlatformStatus = if ($strictOk) { "通过" } elseif ($strictVerifyReport) { "未通过" } else { "未知" }
$productionStatus = if ($productionReady) { "通过" } elseif ($productionReport) { "未通过" } else { "未知" }
$localStatus = if ($localOk) { "通过" } else { "失败" }

$deliveryZip = if ($deliverySummary) { "$($deliverySummary.delivery_zip)" } elseif ($defaultVerifyReport) { "$($defaultVerifyReport.delivery_zip)" } else { "" }
$zipSizeBytes = if ($deliverySummary) { [int64]$deliverySummary.zip_size_bytes } elseif ($defaultVerifyReport) { [int64]$defaultVerifyReport.zip_size_bytes } else { 0 }
$zipSizeText = if ($zipSizeBytes -gt 0) { Format-ByteSize -Bytes $zipSizeBytes } else { "未知" }
$sha256 = if ($deliverySummary) { "$($deliverySummary.sha256)" } elseif ($defaultVerifyReport) { "$($defaultVerifyReport.sha256)" } else { "" }

$defaultProblems = Select-DeliveryChecks -Report $defaultVerifyReport -Statuses @("fail", "warn")
$strictProblems = Select-DeliveryChecks -Report $strictVerifyReport -Statuses @("fail", "warn")
$blockingItems = @(
    Select-ProductionItems -Report $productionReport -Statuses @("fail") |
        Where-Object { [bool]$_.blocking }
)
$warningItems = Select-ProductionItems -Report $productionReport -Statuses @("warn")

$oneLineConclusion = if ($defaultOk -and -not $strictOk -and -not $productionReady) {
    "当前交付包可用于 Windows/Android 内测和本机体验；四端正式交付与生产上线仍未完成。"
} elseif ($defaultOk -and $strictOk -and -not $productionReady) {
    "当前交付包已通过四端安装包验证，但生产上线门禁仍未通过。"
} elseif ($defaultOk -and $strictOk -and $productionReady) {
    "当前交付包和生产门禁均通过；仍建议执行签名发布、灰度和人工复核。"
} elseif ($defaultOk) {
    "当前交付包通过默认完整性验证，但仍需查看四端和生产门禁状态。"
} else {
    "当前交付包未通过默认完整性验证，请先重新生成并验证交付 ZIP。"
}

$generatedAt = Get-Date

$md = [System.Collections.Generic.List[string]]::new()
$md.Add("# Dubhe 发行证据包") | Out-Null
$md.Add("") | Out-Null
$md.Add("- 生成时间：$($generatedAt.ToString('s'))") | Out-Null
$md.Add("- 仓库：$repoRoot") | Out-Null
$md.Add("- Core 地址：$CoreUrl") | Out-Null
$md.Add("- 一句话结论：$oneLineConclusion") | Out-Null
$md.Add("") | Out-Null
$md.Add("## 状态总览") | Out-Null
$md.Add("") | Out-Null
$md.Add("| 项目 | 状态 | 说明 |") | Out-Null
$md.Add("| --- | --- | --- |") | Out-Null
$md.Add("| 默认交付 ZIP 完整性 | $deliveryStatus | Windows/Android 内测交付校验，包含 SHA256 和逐文件清单。 |") | Out-Null
$md.Add("| 严格四端安装包 | $fourPlatformStatus | 要求 Windows/macOS/iOS/Android 均有安装产物。 |") | Out-Null
$md.Add("| 生产上线门禁 | $productionStatus | AI、授权数据、身份、存储、审计、券商、签名发布等门禁。 |") | Out-Null
$md.Add("| 本机体检 | $localStatus | 双击入口、工具链、Core、安装包和本机配置检查。 |") | Out-Null
$md.Add("") | Out-Null
$md.Add("## 最新交付 ZIP") | Out-Null
$md.Add("") | Out-Null
$md.Add("- 路径：``$deliveryZip``") | Out-Null
$md.Add("- 大小：$zipSizeText ($zipSizeBytes bytes)") | Out-Null
$md.Add("- SHA256：``$sha256``") | Out-Null
$md.Add("- 默认验证 JSON：``delivery-verification-default.json``") | Out-Null
$md.Add("- 严格四端验证 JSON：``delivery-verification-strict-four-platform.json``") | Out-Null
$md.Add("") | Out-Null
Add-MarkdownDeliveryChecks -Lines $md -Title "默认验证提示/失败项" -Checks $defaultProblems
Add-MarkdownDeliveryChecks -Lines $md -Title "严格四端验证提示/失败项" -Checks $strictProblems
$md.Add("## 生产门禁") | Out-Null
$md.Add("") | Out-Null
if ($productionReport) {
    $md.Add("- 结论：$($productionReport.message_zh)") | Out-Null
    $md.Add("- 通过：$($productionReport.pass_count)，需确认：$($productionReport.warning_count)，阻断：$($productionReport.blocking_count)，总项：$($productionReport.total_count)") | Out-Null
} else {
    $md.Add("- 未能读取生产门禁。请先启动 Core，再重新导出证据包。") | Out-Null
}
$md.Add("") | Out-Null
$md.Add("| 状态 | 分类 | ID | 下一步 |") | Out-Null
$md.Add("| --- | --- | --- | --- |") | Out-Null
if ($blockingItems.Count -eq 0 -and $warningItems.Count -eq 0) {
    $md.Add("| 无 | - | - | - |") | Out-Null
} else {
    foreach ($item in @($blockingItems + $warningItems)) {
        $md.Add("| $(Format-ProductionStatusZh $item.status) | $(ConvertTo-MarkdownText $item.category_zh) | ``$($item.id)`` | $(ConvertTo-MarkdownText $item.next_step_zh) |") | Out-Null
    }
}
$md.Add("") | Out-Null
$md.Add("## 证据文件") | Out-Null
$md.Add("") | Out-Null
$md.Add("- ``RELEASE-EVIDENCE.html``：给非技术用户打开看的证据页。") | Out-Null
$md.Add("- ``release-evidence.md``：本文件。") | Out-Null
$md.Add("- ``delivery-summary.json``：最新交付 ZIP 摘要。") | Out-Null
$md.Add("- ``delivery-verification-default.json``：默认交付验证结果。") | Out-Null
$md.Add("- ``delivery-verification-strict-four-platform.json``：严格四端验证结果。") | Out-Null
$md.Add("- ``production-readiness.json``：生产门禁结果。") | Out-Null
$md.Add("- ``local-check.txt``：本机体检输出。") | Out-Null
$md.Add("") | Out-Null
$md.Add("## 下一步") | Out-Null
$md.Add("") | Out-Null
$md.Add("1. 如严格四端验证未通过，先在 macOS runner 生成 macOS/iOS 产物，再双击 ``Import-Dubhe-CI-Artifacts.cmd`` 导入。") | Out-Null
$md.Add("2. 如生产门禁未通过，打开 ``Export-Dubhe-Production-Pack.cmd``，按负责人和证据清单补齐。") | Out-Null
$md.Add("3. 每次补齐安装包或生产配置后，重新运行 ``Prepare-Dubhe-Delivery.cmd``、``Verify-Dubhe-Delivery.cmd`` 和 ``Export-Dubhe-Release-Evidence.cmd``。") | Out-Null
$md | Out-File -FilePath (Join-Path $OutputDir "release-evidence.md") -Encoding UTF8

$readmeLines = @(
    "# README FIRST",
    "",
    "这是一份 Dubhe 发行证据包。先打开 `RELEASE-EVIDENCE.html`。",
    "",
    "一句话结论：$oneLineConclusion",
    "",
    "- 默认交付 ZIP：$deliveryStatus",
    "- 严格四端安装包：$fourPlatformStatus",
    "- 生产上线门禁：$productionStatus",
    "- 本机体检：$localStatus",
    "",
    "注意：这份证据包只说明当前状态，不会把 Dubhe 标记为生产就绪。"
)
$readmeLines | Out-File -FilePath (Join-Path $OutputDir "README-FIRST.md") -Encoding UTF8

$html = [System.Collections.Generic.List[string]]::new()
$html.Add("<!doctype html>") | Out-Null
$html.Add("<html lang=""zh-CN"">") | Out-Null
$html.Add("<head>") | Out-Null
$html.Add("<meta charset=""utf-8"">") | Out-Null
$html.Add("<meta name=""viewport"" content=""width=device-width, initial-scale=1"">") | Out-Null
$html.Add("<title>Dubhe 发行证据包</title>") | Out-Null
$html.Add("<style>body{font-family:Segoe UI,Microsoft YaHei,Arial,sans-serif;margin:0;background:#f6f7f9;color:#1b1f24}.wrap{max-width:1120px;margin:0 auto;padding:32px 20px 48px}h1{font-size:30px;margin:0 0 8px}h2{font-size:20px;margin:28px 0 12px}.lead{font-size:16px;line-height:1.7;color:#3c4654}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px;margin:20px 0}.card{background:#fff;border:1px solid #dde2ea;border-radius:8px;padding:16px}.label{font-size:13px;color:#667085}.value{font-size:22px;font-weight:700;margin-top:6px}.ok{color:#157347}.warn{color:#a15c00}.fail{color:#b42318}.badge{display:inline-block;border-radius:999px;padding:3px 8px;font-size:12px;font-weight:700;background:#eef2f6}.badge.ok{background:#dcfce7;color:#166534}.badge.warn{background:#fef3c7;color:#92400e}.badge.fail{background:#fee2e2;color:#991b1b}table{width:100%;border-collapse:collapse;background:#fff;border:1px solid #dde2ea;border-radius:8px;overflow:hidden}th,td{text-align:left;border-bottom:1px solid #e8edf3;padding:10px 12px;vertical-align:top;font-size:14px}th{background:#eef2f6;color:#344054}code{background:#eef2f6;border-radius:4px;padding:2px 5px}.note{background:#fff;border-left:4px solid #2f6fed;padding:14px 16px;margin:18px 0}.mono{word-break:break-all}</style>") | Out-Null
$html.Add("</head>") | Out-Null
$html.Add("<body><main class=""wrap"">") | Out-Null
$html.Add("<h1>Dubhe 发行证据包</h1>") | Out-Null
$html.Add("<p class=""lead"">$(ConvertTo-HtmlText $oneLineConclusion)</p>") | Out-Null
$html.Add("<div class=""grid"">") | Out-Null
$html.Add("<div class=""card""><div class=""label"">默认交付 ZIP</div><div class=""value"">$(ConvertTo-HtmlText $deliveryStatus)</div></div>") | Out-Null
$html.Add("<div class=""card""><div class=""label"">严格四端安装包</div><div class=""value"">$(ConvertTo-HtmlText $fourPlatformStatus)</div></div>") | Out-Null
$html.Add("<div class=""card""><div class=""label"">生产上线门禁</div><div class=""value"">$(ConvertTo-HtmlText $productionStatus)</div></div>") | Out-Null
$html.Add("<div class=""card""><div class=""label"">本机体检</div><div class=""value"">$(ConvertTo-HtmlText $localStatus)</div></div>") | Out-Null
$html.Add("</div>") | Out-Null
$html.Add("<section class=""card""><h2>最新交付 ZIP</h2><p class=""mono""><b>路径：</b>$(ConvertTo-HtmlText $deliveryZip)</p><p><b>大小：</b>$(ConvertTo-HtmlText "$zipSizeText ($zipSizeBytes bytes)")</p><p class=""mono""><b>SHA256：</b>$(ConvertTo-HtmlText $sha256)</p></section>") | Out-Null
$html.Add("<h2>默认验证提示/失败项</h2><table><thead><tr><th>状态</th><th>区域</th><th>项目</th><th>说明</th></tr></thead><tbody>") | Out-Null
Add-HtmlDeliveryRows -Lines $html -Checks $defaultProblems
$html.Add("</tbody></table>") | Out-Null
$html.Add("<h2>严格四端验证提示/失败项</h2><table><thead><tr><th>状态</th><th>区域</th><th>项目</th><th>说明</th></tr></thead><tbody>") | Out-Null
Add-HtmlDeliveryRows -Lines $html -Checks $strictProblems
$html.Add("</tbody></table>") | Out-Null
$html.Add("<h2>生产门禁</h2>") | Out-Null
if ($productionReport) {
    $html.Add("<p>$(ConvertTo-HtmlText $productionReport.message_zh)</p>") | Out-Null
    $html.Add("<p>通过：$(ConvertTo-HtmlText $productionReport.pass_count)，需确认：$(ConvertTo-HtmlText $productionReport.warning_count)，阻断：$(ConvertTo-HtmlText $productionReport.blocking_count)，总项：$(ConvertTo-HtmlText $productionReport.total_count)</p>") | Out-Null
} else {
    $html.Add("<p>未能读取生产门禁。请先启动 Core，再重新导出证据包。</p>") | Out-Null
}
$html.Add("<table><thead><tr><th>状态</th><th>分类</th><th>ID</th><th>下一步</th></tr></thead><tbody>") | Out-Null
if ($blockingItems.Count -eq 0 -and $warningItems.Count -eq 0) {
    $html.Add("<tr><td colspan=""4"">无</td></tr>") | Out-Null
} else {
    foreach ($item in @($blockingItems + $warningItems)) {
        $statusClass = if ($item.status -eq "fail") { "fail" } elseif ($item.status -eq "warn") { "warn" } else { "ok" }
        $html.Add("<tr><td><span class=""badge $statusClass"">$(ConvertTo-HtmlText (Format-ProductionStatusZh $item.status))</span></td><td>$(ConvertTo-HtmlText $item.category_zh)</td><td><code>$(ConvertTo-HtmlText $item.id)</code></td><td>$(ConvertTo-HtmlText $item.next_step_zh)</td></tr>") | Out-Null
    }
}
$html.Add("</tbody></table>") | Out-Null
$html.Add("<div class=""note"">这份证据包只说明当前发行状态，不会把 Dubhe 标记为生产就绪。正式上线前仍要通过生产门禁、签名发布、灰度和人工复核。</div>") | Out-Null
$html.Add("</main></body></html>") | Out-Null
$html | Out-File -FilePath (Join-Path $OutputDir "RELEASE-EVIDENCE.html") -Encoding UTF8

$index = [pscustomobject]@{
    generated_at = $generatedAt.ToString("s")
    repo_root = $repoRoot
    core_url = $CoreUrl
    output_dir = $OutputDir
    conclusion_zh = $oneLineConclusion
    delivery_status_zh = $deliveryStatus
    four_platform_status_zh = $fourPlatformStatus
    production_status_zh = $productionStatus
    local_check_status_zh = $localStatus
    delivery_zip = $deliveryZip
    zip_size_bytes = $zipSizeBytes
    sha256 = $sha256
    start_core = [bool]$StartCore
    start_core_exit_code = if ($startResult) { $startResult.exit_code } else { $null }
}
$index | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $OutputDir "release-evidence-index.json") -Encoding UTF8

Write-Host "Dubhe 发行证据包已生成："
Write-Host $OutputDir
Write-Host "结论：$oneLineConclusion"
Write-Host "默认交付 ZIP：$deliveryStatus"
Write-Host "严格四端安装包：$fourPlatformStatus"
Write-Host "生产上线门禁：$productionStatus"
Write-Host "本机体检：$localStatus"
Write-Host "HTML：$(Join-Path $OutputDir 'RELEASE-EVIDENCE.html')"

if ($OpenFolder) {
    Start-Process -FilePath "explorer.exe" -ArgumentList @($OutputDir)
}

exit 0
