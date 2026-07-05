param(
    [string]$CoreUrl = "http://127.0.0.1:8000",
    [switch]$SkipExternalLive,
    [switch]$RequireExternalServices,
    [switch]$OpenReport
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Invoke-ChildPowerShell {
    param(
        [string]$ScriptPath,
        [string[]]$Arguments = @()
    )

    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments 2>&1
    $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    $outputLines = @($output | ForEach-Object { "$_" })
    return [pscustomobject]@{
        exit_code = $exitCode
        output = ($outputLines -join [Environment]::NewLine)
        output_lines = $outputLines
    }
}

function ConvertFrom-JsonOutput {
    param(
        [pscustomobject]$Result,
        [string]$Label
    )

    $text = $Result.output.Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw "$Label 未返回 JSON。"
    }
    try {
        return $text | ConvertFrom-Json
    } catch {
        throw "$Label JSON 解析失败：$($_.Exception.Message)"
    }
}

function Write-AcceptanceLine {
    param([string]$Message = "")

    Write-Host $Message
    $script:reportLines.Add($Message) | Out-Null
}

function Add-AcceptanceStep {
    param(
        [string]$Name,
        [ValidateSet("passed", "attention", "failed")]
        [string]$Status,
        [bool]$Required,
        [string]$Message,
        [object]$Data = $null
    )

    $script:steps.Add([pscustomobject]@{
        name = $Name
        status = $Status
        required = $Required
        message = $Message
        data = $Data
    }) | Out-Null
}

function Invoke-RequiredAcceptanceStep {
    param(
        [string]$Name,
        [scriptblock]$Action,
        [scriptblock]$Describe
    )

    Write-AcceptanceLine ""
    Write-AcceptanceLine "[$($script:stepNumber)/$script:totalSteps] $Name"
    $script:stepNumber += 1

    try {
        $data = & $Action
        $message = if ($Describe) { & $Describe $data } else { "通过。" }
        Add-AcceptanceStep -Name $Name -Status "passed" -Required $true -Message $message -Data $data
        Write-AcceptanceLine "[OK] $message"
        return $data
    } catch {
        $message = $_.Exception.Message
        Add-AcceptanceStep -Name $Name -Status "failed" -Required $true -Message $message
        $script:blockingFailure = $true
        Write-AcceptanceLine "[失败] $message"
        return $null
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$runRoot = Join-Path $repoRoot ".dubhe-run"
$textReportPath = Join-Path $runRoot "local-acceptance.txt"
$jsonReportPath = Join-Path $runRoot "local-acceptance.json"
$startScript = Join-Path $repoRoot "scripts\start-local-dubhe.ps1"
$localCheckScript = Join-Path $repoRoot "scripts\check-local-dubhe.ps1"
$smokeScript = Join-Path $repoRoot "scripts\smoke-core-workflow.ps1"
$externalScript = Join-Path $repoRoot "scripts\test-external-services.ps1"
$corePort = ([System.Uri]$CoreUrl).Port

New-Item -ItemType Directory -Force -Path $runRoot | Out-Null

$reportLines = [System.Collections.Generic.List[string]]::new()
$steps = [System.Collections.Generic.List[object]]::new()
$blockingFailure = $false
$stepNumber = 1
$totalSteps = 4
$externalLive = -not $SkipExternalLive

Write-AcceptanceLine "Dubhe 本机完整验收"
Write-AcceptanceLine "仓库：$repoRoot"
Write-AcceptanceLine "Core 地址：$CoreUrl"
Write-AcceptanceLine "外部服务 live 检查：$externalLive"
Write-AcceptanceLine "强制外部服务全部通过：$([bool]$RequireExternalServices)"

Invoke-RequiredAcceptanceStep `
    -Name "确保 Core 已启动" `
    -Action {
        if (-not (Test-Path $startScript)) {
            throw "缺少启动脚本：$startScript"
        }
        $result = Invoke-ChildPowerShell -ScriptPath $startScript -Arguments @("-SkipDesktop", "-CorePort", "$corePort")
        if ($result.exit_code -ne 0) {
            throw "Core 启动失败，退出码 $($result.exit_code)。"
        }
        return [pscustomobject]@{
            exit_code = $result.exit_code
            core_url = $CoreUrl
        }
    } `
    -Describe {
        param($Data)
        "Core 已可用：$($Data.core_url)。"
    } | Out-Null

Invoke-RequiredAcceptanceStep `
    -Name "本机环境体检" `
    -Action {
        if (-not (Test-Path $localCheckScript)) {
            throw "缺少体检脚本：$localCheckScript"
        }
        $result = Invoke-ChildPowerShell -ScriptPath $localCheckScript -Arguments @("-CoreUrl", $CoreUrl, "-Json")
        $report = ConvertFrom-JsonOutput -Result $result -Label "本机体检"
        if ($result.exit_code -ne 0 -or $report.blocking_count -gt 0) {
            throw "本机体检发现 $($report.blocking_count) 个阻断项。"
        }
        return $report
    } `
    -Describe {
        param($Data)
        "本机体检通过；提示 $($Data.warning_count) 项，非阻断缺失 $($Data.failure_count) 项。"
    } | Out-Null

Invoke-RequiredAcceptanceStep `
    -Name "主链路 smoke" `
    -Action {
        if (-not (Test-Path $smokeScript)) {
            throw "缺少 smoke 脚本：$smokeScript"
        }
        $result = Invoke-ChildPowerShell -ScriptPath $smokeScript -Arguments @("-CoreUrl", $CoreUrl, "-Json")
        $report = ConvertFrom-JsonOutput -Result $result -Label "主链路 smoke"
        if ($result.exit_code -ne 0 -or $report.status -ne "passed") {
            $failure = if ($report.failure) { $report.failure } else { "未知失败。" }
            throw "主链路 smoke 失败：$failure"
        }
        return $report
    } `
    -Describe {
        param($Data)
        "主链路 smoke 通过；报告：$($Data.report_path)。"
    } | Out-Null

Write-AcceptanceLine ""
Write-AcceptanceLine "[$stepNumber/$totalSteps] 外部 AI/新闻源状态"
$stepNumber += 1
try {
    if (-not (Test-Path $externalScript)) {
        throw "缺少外部服务体检脚本：$externalScript"
    }
    $arguments = @("-CoreUrl", $CoreUrl, "-Json")
    if ($externalLive) {
        $arguments += "-Live"
    }
    $result = Invoke-ChildPowerShell -ScriptPath $externalScript -Arguments $arguments
    $externalReport = ConvertFrom-JsonOutput -Result $result -Label "外部服务体检"
    $externalMessage = "$($externalReport.message_zh) Ready: $($externalReport.ready_count)/$($externalReport.total_count)，状态：$($externalReport.overall_status)。"

    $externalReady = $externalReport.overall_status -eq "ready"
    if (-not $externalReady) {
        if ($RequireExternalServices) {
            throw $externalMessage
        }
        Add-AcceptanceStep -Name "外部 AI/新闻源状态" -Status "attention" -Required $false -Message $externalMessage -Data $externalReport
        Write-AcceptanceLine "[需配置] $externalMessage"
    } else {
        Add-AcceptanceStep -Name "外部 AI/新闻源状态" -Status "passed" -Required ([bool]$RequireExternalServices) -Message $externalMessage -Data $externalReport
        Write-AcceptanceLine "[OK] $externalMessage"
    }
} catch {
    $message = $_.Exception.Message
    $status = if ($RequireExternalServices) { "failed" } else { "attention" }
    Add-AcceptanceStep -Name "外部 AI/新闻源状态" -Status $status -Required ([bool]$RequireExternalServices) -Message $message
    if ($RequireExternalServices) {
        $blockingFailure = $true
        Write-AcceptanceLine "[失败] $message"
    } else {
        Write-AcceptanceLine "[需处理] $message"
    }
}

$failedCount = @($steps | Where-Object { $_.status -eq "failed" }).Count
$attentionCount = @($steps | Where-Object { $_.status -eq "attention" }).Count
$overallStatus = if ($failedCount -gt 0 -or $blockingFailure) {
    "failed"
} elseif ($attentionCount -gt 0) {
    "passed_with_attention"
} else {
    "passed"
}

Write-AcceptanceLine ""
if ($overallStatus -eq "failed") {
    Write-AcceptanceLine "结论：本机验收未通过。先处理上面的失败项，再重新双击 Accept-Dubhe.cmd。"
} elseif ($overallStatus -eq "passed_with_attention") {
    Write-AcceptanceLine "结论：本机演示链路通过，但仍有外部服务或生产配置需要补齐。"
} else {
    Write-AcceptanceLine "结论：本机验收通过。"
}
Write-AcceptanceLine "文本报告：$textReportPath"
Write-AcceptanceLine "JSON 报告：$jsonReportPath"
Write-AcceptanceLine "生产发布前仍需单独通过 Check-Dubhe-Production.cmd。"

$jsonReport = [pscustomobject]@{
    generated_at = (Get-Date).ToString("s")
    status = $overallStatus
    core_url = $CoreUrl
    external_live = $externalLive
    require_external_services = [bool]$RequireExternalServices
    text_report_path = $textReportPath
    json_report_path = $jsonReportPath
    steps = $steps
}

Set-Content -Path $textReportPath -Encoding UTF8 -Value $reportLines
$jsonReport | ConvertTo-Json -Depth 20 | Set-Content -Path $jsonReportPath -Encoding UTF8

if ($OpenReport) {
    Start-Process -FilePath "notepad.exe" -ArgumentList @($textReportPath)
}

if ($overallStatus -eq "failed") {
    exit 1
}
exit 0
