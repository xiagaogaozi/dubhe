param(
    [switch]$CommitAndPush,
    [switch]$OpenReport,
    [string]$Remote = "origin",
    [string]$Branch = "main",
    [string]$CommitMessage = "Activate GitHub Actions workflows"
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

function Add-Line {
    param([string]$Text)
    $script:lines.Add($Text) | Out-Null
}

function Test-GhWorkflowScope {
    param([object[]]$AuthOutput)

    $text = (@($AuthOutput) | ForEach-Object { "$_" }) -join "`n"
    return $text -match "workflow"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$runRoot = Join-Path $repoRoot ".dubhe-run"
$workflowRoot = Join-Path $repoRoot ".github\workflows"
$templateRoot = Join-Path $repoRoot "docs\ci"
$reportTextPath = Join-Path $runRoot "github-actions-activation.txt"
$reportJsonPath = Join-Path $runRoot "github-actions-activation.json"

New-Item -ItemType Directory -Force -Path $runRoot, $workflowRoot | Out-Null

$workflowNames = @("core.yml", "theia-desktop.yml", "mobile.yml")
$copied = [System.Collections.Generic.List[object]]::new()
foreach ($name in $workflowNames) {
    $source = Join-Path $templateRoot $name
    $destination = Join-Path $workflowRoot $name
    if (-not (Test-Path -LiteralPath $source)) {
        throw "缺少 CI 模板：$source"
    }
    Copy-Item -LiteralPath $source -Destination $destination -Force
    $sourceHash = Get-FileHash -Algorithm SHA256 -LiteralPath $source
    $destinationHash = Get-FileHash -Algorithm SHA256 -LiteralPath $destination
    $copied.Add([pscustomobject]@{
        name = $name
        source = $source
        destination = $destination
        sha256 = $destinationHash.Hash
        same_as_template = ($sourceHash.Hash -eq $destinationHash.Hash)
    }) | Out-Null
}

$gh = Get-Command gh -ErrorAction SilentlyContinue
$ghAuthResult = $null
$hasWorkflowScope = $false
$commitResult = $null
$pushResult = $null
$statusResult = Invoke-Capture -FilePath "git" -Arguments @("status", "--short")

if ($gh) {
    $ghAuthResult = Invoke-Capture -FilePath "gh" -Arguments @("auth", "status")
    $hasWorkflowScope = ($ghAuthResult.exit_code -eq 0) -and (Test-GhWorkflowScope -AuthOutput $ghAuthResult.output)
}

$activationStatus = "prepared"
$nextStep = "已把 workflow 文件写入 .github\workflows。"

if ($CommitAndPush) {
    if (-not $gh) {
        $activationStatus = "blocked"
        $nextStep = "请先安装 GitHub CLI gh，再重新运行本脚本。"
    } elseif (-not $hasWorkflowScope) {
        $activationStatus = "blocked"
        $nextStep = "当前 GitHub CLI token 缺少 workflow scope。请运行 gh auth refresh -h github.com -s workflow，授权完成后重新双击 Activate-Dubhe-GitHub-Actions.cmd。"
    } else {
        $addResult = Invoke-Capture -FilePath "git" -Arguments @(
            "add",
            ".github/workflows/core.yml",
            ".github/workflows/theia-desktop.yml",
            ".github/workflows/mobile.yml"
        )
        if ($addResult.exit_code -ne 0) {
            throw "git add workflow 文件失败：$($addResult.output -join ' ')"
        }

        $diffResult = Invoke-Capture -FilePath "git" -Arguments @("diff", "--cached", "--quiet", "--", ".github/workflows")
        if ($diffResult.exit_code -eq 0) {
            $activationStatus = "already_active"
            $nextStep = "远端可能已经包含相同 workflow；请到 GitHub Actions 页面确认。"
        } else {
            $commitResult = Invoke-Capture -FilePath "git" -Arguments @("commit", "-m", $CommitMessage)
            if ($commitResult.exit_code -ne 0) {
                $activationStatus = "blocked"
                $nextStep = "workflow 文件已复制，但 git commit 失败。请查看报告并手动处理。"
            } else {
                $pushResult = Invoke-Capture -FilePath "git" -Arguments @("push", $Remote, $Branch)
                if ($pushResult.exit_code -eq 0) {
                    $activationStatus = "pushed"
                    $nextStep = "请在 GitHub Actions 页面等待 Theia Desktop Packages 和 Mobile Companion Packages 完成，然后下载 artifact 并运行 Import-Dubhe-CI-Artifacts.cmd。"
                } else {
                    $activationStatus = "blocked"
                    $nextStep = "workflow commit 已在本地生成，但 push 失败。若提示 workflow scope，请重新授权 gh；若提示网络错误，请稍后重试 git push。"
                }
            }
        }
    }
}

$report = [pscustomobject]@{
    generated_at = (Get-Date).ToString("s")
    repo_root = $repoRoot
    workflow_root = $workflowRoot
    commit_and_push = [bool]$CommitAndPush
    activation_status = $activationStatus
    next_step_zh = $nextStep
    has_gh = [bool]$gh
    gh_has_workflow_scope = [bool]$hasWorkflowScope
    workflows = $copied
    git_status_before = $statusResult.output
    gh_auth = $ghAuthResult
    commit = $commitResult
    push = $pushResult
}
$report | ConvertTo-Json -Depth 8 | Set-Content -Path $reportJsonPath -Encoding UTF8

$lines = [System.Collections.Generic.List[string]]::new()
Add-Line "Dubhe GitHub Actions 激活报告"
Add-Line ""
Add-Line "生成时间：$($report.generated_at)"
Add-Line "仓库：$repoRoot"
Add-Line "workflow 目录：$workflowRoot"
Add-Line "状态：$activationStatus"
Add-Line "下一步：$nextStep"
Add-Line ""
Add-Line "已写入 workflow："
foreach ($item in $copied) {
    Add-Line "- $($item.name)：$($item.destination)；SHA256=$($item.sha256)；与模板一致=$($item.same_as_template)"
}
Add-Line ""
Add-Line "GitHub CLI：$([bool]$gh)"
Add-Line "workflow scope：$([bool]$hasWorkflowScope)"
if ($ghAuthResult) {
    Add-Line ""
    Add-Line "gh auth status："
    foreach ($line in $ghAuthResult.output) {
        Add-Line "  $line"
    }
}
if ($commitResult) {
    Add-Line ""
    Add-Line "git commit：exit $($commitResult.exit_code)"
    foreach ($line in $commitResult.output) {
        Add-Line "  $line"
    }
}
if ($pushResult) {
    Add-Line ""
    Add-Line "git push：exit $($pushResult.exit_code)"
    foreach ($line in $pushResult.output) {
        Add-Line "  $line"
    }
}
Add-Line ""
Add-Line "JSON 报告：$reportJsonPath"
$lines | Out-File -FilePath $reportTextPath -Encoding UTF8

Write-Host "Dubhe GitHub Actions activation"
Write-Host "Status: $activationStatus"
Write-Host "Report: $reportTextPath"
Write-Host "Next: $nextStep"

if ($OpenReport) {
    Start-Process -FilePath "notepad.exe" -ArgumentList @($reportTextPath)
}

if ($activationStatus -eq "blocked") {
    exit 1
}
exit 0
