param(
    [switch]$CheckOnly,
    [switch]$OpenReport
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Invoke-Capture {
    param(
        [string]$FilePath,
        [string[]]$Arguments = @()
    )

    $output = & $FilePath @Arguments 2>&1
    $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    return [pscustomobject]@{
        exit_code = $exitCode
        output = @($output | ForEach-Object { "$_" })
    }
}

function Test-GhWorkflowScope {
    param([object[]]$AuthOutput)

    $text = (@($AuthOutput) | ForEach-Object { "$_" }) -join "`n"
    return $text -match "workflow"
}

function Add-Line {
    param([string]$Text)
    $script:lines.Add($Text) | Out-Null
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$runRoot = Join-Path $repoRoot ".dubhe-run"
$reportTextPath = Join-Path $runRoot "github-workflow-scope-authorization.txt"
$reportJsonPath = Join-Path $runRoot "github-workflow-scope-authorization.json"
New-Item -ItemType Directory -Force -Path $runRoot | Out-Null

$gh = Get-Command gh -ErrorAction SilentlyContinue
$initialAuth = $null
$refreshResult = $null
$finalAuth = $null
$hadWorkflowScope = $false
$hasWorkflowScope = $false
$status = "blocked"
$nextStep = "请先安装 GitHub CLI gh。"

if ($gh) {
    $initialAuth = Invoke-Capture -FilePath "gh" -Arguments @("auth", "status")
    $hadWorkflowScope = ($initialAuth.exit_code -eq 0) -and (Test-GhWorkflowScope -AuthOutput $initialAuth.output)
    if ($hadWorkflowScope) {
        $status = "already_authorized"
        $nextStep = "当前 GitHub CLI 已具备 workflow scope，可运行 Activate-Dubhe-GitHub-Actions.cmd。"
    } elseif ($CheckOnly) {
        $status = "missing_scope"
        $nextStep = "当前 GitHub CLI 缺少 workflow scope；双击 Authorize-Dubhe-GitHub-Actions.cmd 开始授权。"
    } else {
        $refreshResult = Invoke-Capture -FilePath "gh" -Arguments @(
            "auth",
            "refresh",
            "-h",
            "github.com",
            "-s",
            "workflow",
            "-c"
        )
        $finalAuth = Invoke-Capture -FilePath "gh" -Arguments @("auth", "status")
        $hasWorkflowScope = ($finalAuth.exit_code -eq 0) -and (Test-GhWorkflowScope -AuthOutput $finalAuth.output)
        if ($hasWorkflowScope) {
            $status = "authorized"
            $nextStep = "workflow scope 已授权。请双击 Activate-Dubhe-GitHub-Actions.cmd 激活四端构建 workflow。"
        } else {
            $status = "blocked"
            $nextStep = "授权未完成。请按窗口或报告中的 GitHub 设备授权提示完成浏览器确认；如遇网络超时，稍后重新双击本脚本。"
        }
    }
}

$report = [pscustomobject]@{
    generated_at = (Get-Date).ToString("s")
    repo_root = $repoRoot
    check_only = [bool]$CheckOnly
    has_gh = [bool]$gh
    had_workflow_scope = [bool]$hadWorkflowScope
    has_workflow_scope = [bool]($hadWorkflowScope -or $hasWorkflowScope)
    status = $status
    next_step_zh = $nextStep
    initial_auth = $initialAuth
    refresh = $refreshResult
    final_auth = $finalAuth
}
$report | ConvertTo-Json -Depth 8 | Set-Content -Path $reportJsonPath -Encoding UTF8

$lines = [System.Collections.Generic.List[string]]::new()
Add-Line "Dubhe GitHub workflow scope 授权报告"
Add-Line ""
Add-Line "生成时间：$($report.generated_at)"
Add-Line "仓库：$repoRoot"
Add-Line "状态：$status"
Add-Line "下一步：$nextStep"
Add-Line ""
Add-Line "GitHub CLI：$([bool]$gh)"
Add-Line "workflow scope：$($report.has_workflow_scope)"
if ($initialAuth) {
    Add-Line ""
    Add-Line "授权前 gh auth status："
    foreach ($line in $initialAuth.output) {
        Add-Line "  $line"
    }
}
if ($refreshResult) {
    Add-Line ""
    Add-Line "gh auth refresh：exit $($refreshResult.exit_code)"
    foreach ($line in $refreshResult.output) {
        Add-Line "  $line"
    }
}
if ($finalAuth) {
    Add-Line ""
    Add-Line "授权后 gh auth status："
    foreach ($line in $finalAuth.output) {
        Add-Line "  $line"
    }
}
Add-Line ""
Add-Line "JSON 报告：$reportJsonPath"
$lines | Out-File -FilePath $reportTextPath -Encoding UTF8

Write-Host "Dubhe GitHub workflow scope authorization"
Write-Host "Status: $status"
Write-Host "Report: $reportTextPath"
Write-Host "Next: $nextStep"

if ($OpenReport) {
    Start-Process -FilePath "notepad.exe" -ArgumentList @($reportTextPath)
}

if ($status -eq "authorized" -or $status -eq "already_authorized") {
    exit 0
}
exit 1
