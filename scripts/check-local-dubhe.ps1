param(
    [string]$CoreUrl = "http://127.0.0.1:8000",
    [switch]$Json
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function New-Check {
    param(
        [string]$Area,
        [string]$Name,
        [ValidateSet("ok", "warn", "fail")]
        [string]$Status,
        [string]$Message,
        [bool]$Blocking = $false
    )

    [pscustomobject]@{
        area = $Area
        name = $Name
        status = $Status
        blocking = $Blocking
        message = $Message
    }
}

function Add-Check {
    param([pscustomobject]$Check)
    $script:checks.Add($Check) | Out-Null
}

function Test-CommandAvailable {
    param([string]$Command)
    return $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Resolve-ToolCommand {
    param(
        [string]$Command,
        [string]$BundledPath
    )

    if ($BundledPath -and (Test-Path $BundledPath)) {
        return $BundledPath
    }
    if (Test-CommandAvailable $Command) {
        return $Command
    }
    return $null
}

function Test-CoreHealth {
    param([string]$Url)

    try {
        $response = Invoke-RestMethod -Uri "$Url/health" -TimeoutSec 2
        return $response.status -eq "ok" -and $response.service -eq "dubhe-core"
    } catch {
        return $false
    }
}

function Read-SystemStatus {
    param([string]$Url)

    try {
        $response = Invoke-WebRequest -Uri "$Url/v1/system/status" -TimeoutSec 3 -UseBasicParsing
        if ($response.RawContentStream) {
            $response.RawContentStream.Position = 0
            $memory = [System.IO.MemoryStream]::new()
            $response.RawContentStream.CopyTo($memory)
            $json = [System.Text.UTF8Encoding]::new($false).GetString($memory.ToArray())
            return $json | ConvertFrom-Json
        }
        return $response.Content | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Write-CheckLine {
    param([pscustomobject]$Check)

    $label = switch ($Check.status) {
        "ok" { "[OK]" }
        "warn" { "[提示]" }
        "fail" { "[缺失]" }
    }
    Write-Host "$label $($Check.area) / $($Check.name)：$($Check.message)"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$configLoader = Join-Path $repoRoot "scripts\dubhe-config.ps1"
if (Test-Path $configLoader) {
    . $configLoader
    $loadedLocalConfigKeys = @(Import-DubheLocalConfig -RepoRoot $repoRoot -Quiet)
} else {
    $loadedLocalConfigKeys = @()
}
$coreRoot = Join-Path $repoRoot "services\core"
$theiaRoot = Join-Path $repoRoot "apps\theia-desktop"
$mobileRoot = Join-Path $repoRoot "apps\mobile"
$runRoot = Join-Path $repoRoot ".dubhe-run"
$startCmd = Join-Path $repoRoot "Start-Dubhe.cmd"
$checkCmd = Join-Path $repoRoot "Check-Dubhe.cmd"
$smokeCmd = Join-Path $repoRoot "Smoke-Dubhe.cmd"
$stopCmd = Join-Path $repoRoot "Stop-Dubhe-Core.cmd"
$configureCmd = Join-Path $repoRoot "Configure-Dubhe.cmd"
$localConfigPath = Join-Path $repoRoot "config\dubhe.local.env"
$localConfigExamplePath = Join-Path $repoRoot "config\dubhe.local.env.example"
$shortcutInstaller = Join-Path $repoRoot "scripts\install-windows-shortcuts.ps1"
$coreRunScript = Join-Path $coreRoot "scripts\run.ps1"
$coreTestScript = Join-Path $coreRoot "scripts\test.ps1"
$coreSmokeScript = Join-Path $repoRoot "scripts\smoke-core-workflow.ps1"
$desktopExe = Join-Path $theiaRoot "app\dist\win-unpacked\Dubhe.exe"
$mobileDebugApk = Join-Path $mobileRoot "build\app\outputs\flutter-apk\app-debug.apk"
$nodeExe = Resolve-ToolCommand "node" (Join-Path $env:LOCALAPPDATA "DubheToolchains\node-v22.23.1-win-x64\node.exe")
$yarnCmd = Resolve-ToolCommand "yarn" (Join-Path $env:LOCALAPPDATA "DubheToolchains\node-v22.23.1-win-x64\yarn.cmd")
$flutterExe = Resolve-ToolCommand "flutter" (Join-Path $env:LOCALAPPDATA "DubheToolchains\flutter\bin\flutter.bat")
$jdkHome = Join-Path $env:LOCALAPPDATA "DubheToolchains\jdk-17"
$androidSdk = Join-Path $env:LOCALAPPDATA "DubheToolchains\android-sdk"

$checks = [System.Collections.Generic.List[object]]::new()

Add-Check (New-Check "仓库" "根目录" "ok" $repoRoot)
Add-Check (New-Check "Windows 入口" "双击启动" ($(if (Test-Path $startCmd) { "ok" } else { "warn" })) ($(if (Test-Path $startCmd) { $startCmd } else { "缺少 Start-Dubhe.cmd。" })))
Add-Check (New-Check "Windows 入口" "双击体检" ($(if (Test-Path $checkCmd) { "ok" } else { "warn" })) ($(if (Test-Path $checkCmd) { $checkCmd } else { "缺少 Check-Dubhe.cmd。" })))
Add-Check (New-Check "Windows 入口" "双击烟测" ($(if (Test-Path $smokeCmd) { "ok" } else { "warn" })) ($(if (Test-Path $smokeCmd) { $smokeCmd } else { "缺少 Smoke-Dubhe.cmd。" })))
Add-Check (New-Check "Windows 入口" "双击停止 Core" ($(if (Test-Path $stopCmd) { "ok" } else { "warn" })) ($(if (Test-Path $stopCmd) { $stopCmd } else { "缺少 Stop-Dubhe-Core.cmd。" })))
Add-Check (New-Check "Windows 入口" "双击配置" ($(if (Test-Path $configureCmd) { "ok" } else { "warn" })) ($(if (Test-Path $configureCmd) { $configureCmd } else { "缺少 Configure-Dubhe.cmd。" })))
Add-Check (New-Check "Windows 入口" "快捷方式安装器" ($(if (Test-Path $shortcutInstaller) { "ok" } else { "warn" })) ($(if (Test-Path $shortcutInstaller) { $shortcutInstaller } else { "缺少 scripts/install-windows-shortcuts.ps1。" })))
Add-Check (New-Check "本地配置" "配置模板" ($(if (Test-Path $localConfigExamplePath) { "ok" } else { "warn" })) ($(if (Test-Path $localConfigExamplePath) { $localConfigExamplePath } else { "缺少 config/dubhe.local.env.example。" })))
Add-Check (New-Check "本地配置" "配置文件" ($(if (Test-Path $localConfigPath) { "ok" } else { "warn" })) ($(if (Test-Path $localConfigPath) { "已加载 $($loadedLocalConfigKeys.Count) 项：$localConfigPath" } else { "尚未创建；可双击 Configure-Dubhe.cmd 创建并填写模型/新闻源 Key。" })))
Add-Check (New-Check "Core" "运行脚本" ($(if (Test-Path $coreRunScript) { "ok" } else { "fail" })) ($(if (Test-Path $coreRunScript) { $coreRunScript } else { "缺少 services/core/scripts/run.ps1。" })) (-not (Test-Path $coreRunScript)))
Add-Check (New-Check "Core" "测试脚本" ($(if (Test-Path $coreTestScript) { "ok" } else { "warn" })) ($(if (Test-Path $coreTestScript) { $coreTestScript } else { "缺少测试脚本，后续无法一键验证 Core。" })))
Add-Check (New-Check "Core" "主链路烟测" ($(if (Test-Path $coreSmokeScript) { "ok" } else { "warn" })) ($(if (Test-Path $coreSmokeScript) { $coreSmokeScript } else { "缺少 scripts/smoke-core-workflow.ps1。" })))

$venvPython = Join-Path $coreRoot ".venv\Scripts\python.exe"
if (Test-Path $venvPython) {
    Add-Check (New-Check "Core" "Python 虚拟环境" "ok" $venvPython)
} elseif (Test-CommandAvailable "python") {
    Add-Check (New-Check "Core" "Python 虚拟环境" "warn" "尚未创建 .venv；首次启动会自动创建并安装依赖。")
} else {
    Add-Check (New-Check "Core" "Python" "fail" "未找到 python，Core 无法启动。" $true)
}

$coreReady = Test-CoreHealth -Url $CoreUrl
Add-Check (New-Check "Core" "服务状态" ($(if ($coreReady) { "ok" } else { "warn" })) ($(if ($coreReady) { "Core 已在 $CoreUrl 运行。" } else { "Core 当前未运行；执行 scripts/start-local-dubhe.ps1 会自动启动。" })))

$systemStatus = $null
if ($coreReady) {
    $systemStatus = Read-SystemStatus -Url $CoreUrl
    if ($systemStatus) {
        Add-Check (New-Check "Core" "系统体检接口" "ok" "已读取 /v1/system/status，版本 $($systemStatus.version)。")
        Add-Check (New-Check "交易" "实盘开关" ($(if ($systemStatus.trading.live_trading_enabled) { "fail" } else { "ok" })) ($(if ($systemStatus.trading.live_trading_enabled) { "实盘交易已开启，请确认风控和审批已完成。" } else { "实盘交易关闭，纸面交易可用。" })) ([bool]$systemStatus.trading.live_trading_enabled))
        foreach ($item in $systemStatus.config_items) {
            Add-Check (New-Check "数据源配置" $item.label_zh ($(if ($item.configured) { "ok" } else { "warn" })) $item.message_zh)
        }
    } else {
        Add-Check (New-Check "Core" "系统体检接口" "warn" "Core 可用，但 /v1/system/status 暂未返回；如果刚更新代码，请重启 Core。")
    }
} else {
    $envItems = @(
        @{ key = "FINNHUB_API_KEY"; label = "Finnhub 授权新闻源 Key" },
        @{ key = "ALPHA_VANTAGE_API_KEY"; label = "Alpha Vantage 新闻情绪 Key" },
        @{ key = "DUBHE_SEC_USER_AGENT"; label = "SEC EDGAR User-Agent" }
    )
    foreach ($item in $envItems) {
        $configured = -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($item.key))
        Add-Check (New-Check "数据源配置" $item.label ($(if ($configured) { "ok" } else { "warn" })) ($(if ($configured) { "当前 PowerShell 会话已配置 $($item.key)。" } else { "当前 PowerShell 会话未配置 $($item.key)；实时授权源会跳过或使用默认值。" })))
    }
}

$packagedDesktopReady = Test-Path $desktopExe

if ($nodeExe) {
    Add-Check (New-Check "桌面端" "Node.js" "ok" $nodeExe)
} else {
    Add-Check (New-Check "桌面端" "Node.js" "fail" "未找到 Node.js；Theia 开发启动和打包不可用。" (-not $packagedDesktopReady))
}

if ($yarnCmd) {
    Add-Check (New-Check "桌面端" "Yarn" "ok" $yarnCmd)
} else {
    Add-Check (New-Check "桌面端" "Yarn" "fail" "未找到 Yarn 1；Theia 开发启动和打包不可用。" (-not $packagedDesktopReady))
}

if ($packagedDesktopReady) {
    Add-Check (New-Check "桌面端" "Windows 桌面产物" "ok" $desktopExe)
} else {
    Add-Check (New-Check "桌面端" "Windows 桌面产物" "warn" "未找到已打包 Dubhe.exe；启动脚本会回退到 Theia 开发启动。")
}

if (Test-Path (Join-Path $theiaRoot "node_modules")) {
    Add-Check (New-Check "桌面端" "依赖目录" "ok" "apps/theia-desktop/node_modules 已存在。")
} else {
    Add-Check (New-Check "桌面端" "依赖目录" "warn" "尚未安装 Theia 依赖；首次运行开发启动前需要 yarn install。")
}

if ($flutterExe) {
    Add-Check (New-Check "移动端" "Flutter" "ok" $flutterExe)
} else {
    Add-Check (New-Check "移动端" "Flutter" "warn" "未找到 Flutter；不会影响 Core/桌面端，但无法本机打 Android 包。")
}

if (Test-Path $jdkHome) {
    Add-Check (New-Check "移动端" "JDK 17" "ok" $jdkHome)
} else {
    Add-Check (New-Check "移动端" "JDK 17" "warn" "未找到本地 JDK 17 工具链；Android 构建可能不可用。")
}

if (Test-Path $androidSdk) {
    Add-Check (New-Check "移动端" "Android SDK" "ok" $androidSdk)
} else {
    Add-Check (New-Check "移动端" "Android SDK" "warn" "未找到本地 Android SDK；Android 构建可能不可用。")
}

if (Test-Path $mobileDebugApk) {
    Add-Check (New-Check "移动端" "Android debug APK" "ok" $mobileDebugApk)
} else {
    Add-Check (New-Check "移动端" "Android debug APK" "warn" "尚未生成 debug APK；可在 apps/mobile 执行 flutter build apk --debug。")
}

Add-Check (New-Check "日志" "本地运行目录" "ok" $runRoot)

$blockingCount = @($checks | Where-Object { $_.blocking }).Count
$warnCount = @($checks | Where-Object { $_.status -eq "warn" }).Count
$failCount = @($checks | Where-Object { $_.status -eq "fail" }).Count

$report = [pscustomobject]@{
    generated_at = (Get-Date).ToString("s")
    core_url = $CoreUrl
    blocking_count = $blockingCount
    warning_count = $warnCount
    failure_count = $failCount
    checks = $checks
}

if ($Json) {
    $report | ConvertTo-Json -Depth 8
} else {
    Write-Host "Dubhe 本机体检"
    Write-Host "Core 地址：$CoreUrl"
    Write-Host ""
    foreach ($check in $checks) {
        Write-CheckLine $check
    }
    Write-Host ""
    if ($blockingCount -gt 0) {
        Write-Host "结论：发现 $blockingCount 个阻断项，请先处理后再启动 Dubhe。"
    } elseif ($warnCount -gt 0 -or $failCount -gt 0) {
        Write-Host "结论：可以继续本地体验，但有 $warnCount 个提示项和 $failCount 个非阻断缺失项需要后续补齐。"
    } else {
        Write-Host "结论：本机环境已准备好。"
    }
}

if ($blockingCount -gt 0) {
    exit 1
}
