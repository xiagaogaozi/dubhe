param(
    [string]$CoreUrl = "http://127.0.0.1:8000",
    [string]$OutputDir = "",
    [switch]$StartCore,
    [switch]$OpenFolder,
    [switch]$FailWhenNotReady
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Read-CoreJson {
    param([string]$Url)

    $response = Invoke-WebRequest -Uri $Url -TimeoutSec 30 -UseBasicParsing
    if ($response.RawContentStream) {
        $response.RawContentStream.Position = 0
        $memory = [System.IO.MemoryStream]::new()
        $response.RawContentStream.CopyTo($memory)
        $body = [System.Text.UTF8Encoding]::new($false).GetString($memory.ToArray())
        return $body | ConvertFrom-Json
    }
    return $response.Content | ConvertFrom-Json
}

function Invoke-ChildPowerShell {
    param(
        [string]$ScriptPath,
        [string[]]$Arguments = @()
    )

    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments 2>&1
    $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    return [pscustomobject]@{
        exit_code = $exitCode
        output = @($output | ForEach-Object { "$_" })
    }
}

function ConvertTo-MarkdownText {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }
    return $Value.Replace("|", "\|").Replace("`r", " ").Replace("`n", " ")
}

function Get-OwnerForItem {
    param([string]$ItemId)

    if ($ItemId -match "^licensed_news") { return "数据/法务/后端" }
    switch ($ItemId) {
        "llm_configured" { "AI 平台/运维" }
        "gdelt_available" { "数据/合规" }
        "production_identity" { "后端/安全/运维" }
        "production_storage" { "后端/运维" }
        "immutable_audit" { "后端/安全/合规" }
        "live_broker_adapter" { "交易/后端/风控/法务" }
        "live_trading_guard" { "风控/交易/运营" }
        "package_windows" { "桌面端/发布" }
        "package_android" { "移动端/发布" }
        "package_macos" { "桌面端/Apple 发布" }
        "package_ios" { "移动端/Apple 发布" }
        "local_smoke_chain" { "测试/发布" }
        default { "项目负责人" }
    }
}

function Get-ArtifactForItem {
    param([string]$ItemId)

    if ($ItemId -match "^licensed_news") {
        return "供应商合同、API key、授权范围、缓存/AI 使用许可、adapter 测试记录"
    }
    switch ($ItemId) {
        "llm_configured" { "模型供应商账号、API key、base URL、live 体检报告、数据使用条款" }
        "production_identity" { "DUBHE_AUTH_MODE、OIDC issuer/client/redirect、会话签名密钥、刷新令牌策略、MFA 策略 runbook、身份生命周期 runbook、OIDC auth adapter 切换演练" }
        "production_storage" { "DUBHE_STORAGE_BACKEND、DUBHE_DATABASE_URL、DUBHE_REDIS_URL、S3/MinIO 配置、备份恢复 runbook、迁移 runbook、PostgreSQL store 切换演练" }
        "immutable_audit" { "追加写审计存储、对象锁/WORM 策略、签名摘要、审计查询与留存策略" }
        "live_broker_adapter" { "券商沙盒/实盘账号、adapter、拒单/断线/重复单/撤单 UAT、合规审批" }
        "package_macos" { "Apple Developer、Developer ID、notarization、公证日志、dmg/zip 产物" }
        "package_ios" { "Bundle ID、Team ID、证书、Provisioning Profile、TestFlight/App Store 元数据" }
        "package_windows" { "代码签名证书、签名安装器、更新渠道、杀软/SmartScreen 验证记录" }
        "package_android" { "正式签名 keystore、包名、隐私政策、商店资料、release AAB" }
        "local_smoke_chain" { "Smoke 报告、CI job、发布前验收记录" }
        default { "需求说明、实现证据、测试报告、负责人确认" }
    }
}

function Format-StatusLabel {
    param([string]$Status)

    switch ($Status) {
        "pass" { "通过" }
        "warn" { "需确认" }
        "fail" { "未完成" }
        default { $Status }
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutputDir) {
    $OutputDir = Join-Path $repoRoot ".dubhe-run\production-pack"
}
$startScript = Join-Path $repoRoot "scripts\start-local-dubhe.ps1"

if ($StartCore) {
    if (-not (Test-Path $startScript)) {
        throw "缺少启动脚本：$startScript"
    }
    $startResult = Invoke-ChildPowerShell -ScriptPath $startScript -Arguments @("-SkipDesktop")
    if ($startResult.exit_code -ne 0) {
        throw "Dubhe Core 启动失败，退出码 $($startResult.exit_code)。$($startResult.output -join ' ')"
    }
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

try {
    $report = Read-CoreJson -Url "$CoreUrl/v1/system/production-readiness"
} catch {
    Write-Host "无法读取 Dubhe Core 生产门禁。"
    Write-Host "Core URL: $CoreUrl"
    Write-Host "可先双击 Start-Dubhe.cmd，再重新运行本脚本。"
    throw
}

$generatedAt = Get-Date
$jsonPath = Join-Path $OutputDir "production-readiness.json"
$csvPath = Join-Path $OutputDir "production-blockers.csv"
$allItemsCsvPath = Join-Path $OutputDir "production-readiness-items.csv"
$actionPlanPath = Join-Path $OutputDir "production-action-plan.md"
$vendorPath = Join-Path $OutputDir "vendor-and-account-checklist.md"
$handoffPath = Join-Path $OutputDir "README-FIRST.md"

$report | ConvertTo-Json -Depth 12 | Set-Content -Path $jsonPath -Encoding UTF8

$rows = @(
    foreach ($item in $report.items) {
        [pscustomobject]@{
            id = $item.id
            category = $item.category_zh
            status = $item.status
            blocking = [bool]$item.blocking
            owner = Get-OwnerForItem $item.id
            required_artifact = Get-ArtifactForItem $item.id
            requirement = $item.requirement_zh
            evidence = $item.evidence_zh
            next_step = $item.next_step_zh
        }
    }
)

$blockingRows = @($rows | Where-Object { $_.blocking -and $_.status -eq "fail" })
$warningRows = @($rows | Where-Object { $_.status -eq "warn" })
$passRows = @($rows | Where-Object { $_.status -eq "pass" })
$rows | Export-Csv -Path $allItemsCsvPath -Encoding UTF8 -NoTypeInformation
$blockingRows | Export-Csv -Path $csvPath -Encoding UTF8 -NoTypeInformation

$actionLines = [System.Collections.Generic.List[string]]::new()
$actionLines.Add("# Dubhe 生产上线补齐包") | Out-Null
$actionLines.Add("") | Out-Null
$actionLines.Add("- 生成时间：$($generatedAt.ToString('s'))") | Out-Null
$actionLines.Add("- Core 地址：$CoreUrl") | Out-Null
$actionLines.Add("- 当前结论：$($report.message_zh)") | Out-Null
$actionLines.Add("- 通过：$($report.pass_count)，需确认：$($report.warning_count)，阻断：$($report.blocking_count)，总项：$($report.total_count)") | Out-Null
$actionLines.Add("") | Out-Null
$actionLines.Add("## 先做什么") | Out-Null
$actionLines.Add("") | Out-Null
if ($blockingRows.Count -gt 0) {
    $actionLines.Add("1. 先处理所有未完成且阻断的项目，不要打开实盘交易。") | Out-Null
    $actionLines.Add("2. 每补齐一项，都保存合同/账号/配置/测试报告证据，并重新运行 `Export-Dubhe-Production-Pack.cmd`。") | Out-Null
    $actionLines.Add("3. 当 `Check-Dubhe-Production.cmd` 通过后，再进入签名发布和小范围灰度。") | Out-Null
} else {
    $actionLines.Add("1. 当前没有阻断项；仍需复核 warn 项并执行签名发布流程。") | Out-Null
    $actionLines.Add("2. 执行 `Check-Dubhe-Production.cmd` 和 `Accept-Dubhe.cmd` 保存最终验收证据。") | Out-Null
}
$actionLines.Add("") | Out-Null
$actionLines.Add("## 阻断项") | Out-Null
$actionLines.Add("") | Out-Null
$actionLines.Add("| 状态 | 分类 | ID | 负责人 | 需要交付的证据 | 下一步 |") | Out-Null
$actionLines.Add("| --- | --- | --- | --- | --- | --- |") | Out-Null
foreach ($row in $blockingRows) {
    $actionLines.Add("| $(Format-StatusLabel $row.status) | $(ConvertTo-MarkdownText $row.category) | ``$($row.id)`` | $(ConvertTo-MarkdownText $row.owner) | $(ConvertTo-MarkdownText $row.required_artifact) | $(ConvertTo-MarkdownText $row.next_step) |") | Out-Null
}
if ($blockingRows.Count -eq 0) {
    $actionLines.Add("| 无 | - | - | - | - | - |") | Out-Null
}
$actionLines.Add("") | Out-Null
$actionLines.Add("## 需确认项") | Out-Null
$actionLines.Add("") | Out-Null
$actionLines.Add("| 状态 | 分类 | ID | 负责人 | 当前证据 | 下一步 |") | Out-Null
$actionLines.Add("| --- | --- | --- | --- | --- | --- |") | Out-Null
foreach ($row in $warningRows) {
    $actionLines.Add("| $(Format-StatusLabel $row.status) | $(ConvertTo-MarkdownText $row.category) | ``$($row.id)`` | $(ConvertTo-MarkdownText $row.owner) | $(ConvertTo-MarkdownText $row.evidence) | $(ConvertTo-MarkdownText $row.next_step) |") | Out-Null
}
if ($warningRows.Count -eq 0) {
    $actionLines.Add("| 无 | - | - | - | - | - |") | Out-Null
}
$actionLines.Add("") | Out-Null
$actionLines.Add("## 已通过项") | Out-Null
$actionLines.Add("") | Out-Null
foreach ($row in $passRows) {
    $actionLines.Add("- ``$($row.id)``：$($row.evidence)") | Out-Null
}
Set-Content -Path $actionPlanPath -Encoding UTF8 -Value $actionLines

$vendorLines = [System.Collections.Generic.List[string]]::new()
$vendorLines.Add("# 供应商、账号与发布材料清单") | Out-Null
$vendorLines.Add("") | Out-Null
$vendorLines.Add("这份清单用于找数据供应商、AI 模型供应商、券商、Apple/Google/Microsoft 发布账号和运维资源。") | Out-Null
$vendorLines.Add("") | Out-Null
$vendorLines.Add("| 领域 | 需要准备 | 对应门禁 |") | Out-Null
$vendorLines.Add("| --- | --- | --- |") | Out-Null
$vendorGroups = @(
    @{ label = "AI 模型"; ids = @("llm_configured") },
    @{ label = "A/HK/US/全球金融新闻与数据"; ids = @("licensed_news_a_share", "licensed_news_hk", "licensed_news_us", "licensed_news_global") },
    @{ label = "身份与权限"; ids = @("production_identity") },
    @{ label = "云同步与存储"; ids = @("production_storage") },
    @{ label = "审计与合规"; ids = @("immutable_audit") },
    @{ label = "券商与实盘交易"; ids = @("live_broker_adapter", "live_trading_guard") },
    @{ label = "四端签名与发布"; ids = @("package_windows", "package_android", "package_macos", "package_ios") }
)
foreach ($group in $vendorGroups) {
    $related = @($rows | Where-Object { $group.ids -contains $_.id })
    $materials = ($related | ForEach-Object { Get-ArtifactForItem $_.id } | Select-Object -Unique) -join "；"
    $ids = ($related | ForEach-Object { "``$($_.id)``" }) -join "、"
    $vendorLines.Add("| $($group.label) | $(ConvertTo-MarkdownText $materials) | $ids |") | Out-Null
}
Set-Content -Path $vendorPath -Encoding UTF8 -Value $vendorLines

$handoffLines = @(
    "# README FIRST",
    "",
    "Dubhe 当前还没有生产就绪。这个目录把生产上线还缺什么整理成可执行文件。",
    "",
    "- production-action-plan.md：给项目负责人看的阻断项、负责人和下一步。",
    "- vendor-and-account-checklist.md：给商务/运维准备供应商、账号、证书和发布材料。",
    "- production-blockers.csv：只包含阻断项，可导入表格或 issue tracker。",
    "- production-readiness-items.csv：全量生产门禁表格。",
    "- production-readiness.json：来自 Core 的原始生产门禁 JSON。",
    "",
    "当前结论：$($report.message_zh)",
    "",
    "下一步：先处理阻断项，再重新运行 `Export-Dubhe-Production-Pack.cmd` 和 `Check-Dubhe-Production.cmd`。"
)
Set-Content -Path $handoffPath -Encoding UTF8 -Value $handoffLines

Write-Host "Dubhe 生产上线补齐包已生成："
Write-Host $OutputDir
Write-Host "阻断项：$($blockingRows.Count)，需确认项：$($warningRows.Count)，已通过项：$($passRows.Count)"
Write-Host "行动计划：$actionPlanPath"
Write-Host "供应商清单：$vendorPath"
Write-Host "阻断项表格：$csvPath"
Write-Host "全量表格：$allItemsCsvPath"

if ($OpenFolder) {
    Start-Process -FilePath "explorer.exe" -ArgumentList @($OutputDir)
}

if ($FailWhenNotReady -and -not $report.production_ready) {
    exit 1
}
